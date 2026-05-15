#!/usr/bin/env python3
"""Verify Slice B end-to-end.

After Slice A produced cached monologues, Slice B adds TTS
pre-synthesis. We:
  1. Clear any prior RouteMonologue + MonologueAudio for the test
     polyline so the cache-miss path runs.
  2. Generate a monologue.
  3. Confirm every utterance got an `audio_url`.
  4. Pull the first utterance's mp3 from MonologueAudio and verify
     bytes are valid mp3 (starts with ID3 or FF FB).
  5. Repeat call — same monologue should reuse the same audio docs
     (no fresh TTS).

Run inside the container:
    docker compose exec -T backend python < backend/scripts/verify_slice_b.py
"""

from __future__ import annotations

import asyncio
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import (  # type: ignore  # noqa: E402
    MONGODB_DATABASE, MONGODB_URL, MonologueAudio, RouteMonologue,
)
from app.services.mapbox_directions import fetch_polyline  # noqa: E402
from app.services.monologue_pipeline import (  # noqa: E402
    generate_monologue, polyline_hash,
)
from motor.motor_asyncio import AsyncIOMotorClient  # noqa: E402
from beanie import init_beanie  # noqa: E402


SF = (37.7749, -122.4194)
TAHOE = (38.9399, -119.9772)
ROUTE_LABEL = "San Francisco, CA -> South Lake Tahoe, CA"


async def init_db():
    client = AsyncIOMotorClient(MONGODB_URL)
    await init_beanie(
        database=client[MONGODB_DATABASE],
        document_models=[RouteMonologue, MonologueAudio],
    )


def _is_mp3(data: bytes) -> bool:
    """Cheap MP3 header check. Accepts ID3v2 tag prefix or raw frame sync."""
    if len(data) < 3:
        return False
    if data[:3] == b"ID3":
        return True
    # MPEG frame sync: first byte 0xFF, second byte 0xE0-0xFF (high nibble = 1110/1111)
    return data[0] == 0xFF and (data[1] & 0xE0) == 0xE0


async def main() -> int:
    print("Verify Slice B — TTS pre-synthesis on monologue utterances")
    print("=" * 72)

    if not os.getenv("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY not in env")
        return 1

    await init_db()
    polyline = await fetch_polyline(SF[0], SF[1], TAHOE[0], TAHOE[1])
    if not polyline:
        print("ERROR: no polyline")
        return 1
    p_hash = polyline_hash(polyline)

    # Clear prior RouteMonologue for this polyline AND any MonologueAudio
    # whose hash we'd be regenerating. We can't know the text hashes
    # without generating, so just nuke everything for this test polyline
    # in RouteMonologue, then let the audio cache handle itself.
    rm_deleted = await RouteMonologue.find(
        RouteMonologue.polyline_hash == p_hash,
    ).delete()
    print(f"Cleared {rm_deleted.deleted_count} prior RouteMonologue docs.")

    # --- Fresh generation with TTS ---
    print("\n--- Scenario 1: fresh generation (cache miss path includes TTS) ---")
    t0 = time.time()
    doc = await generate_monologue(
        polyline=polyline,
        route_label=ROUTE_LABEL,
        narration_themes=["history"],
        stop_interests=[],
    )
    dt = time.time() - t0
    if not doc:
        print("FAILED: no doc")
        return 1
    print(f"  generated in {dt:.1f}s (includes TTS for {len(doc.utterances)} utts)")

    audio_urls = [u.get("audio_url") for u in doc.utterances]
    with_audio = [u for u in audio_urls if u]
    print(f"  utterances with audio_url: {len(with_audio)}/{len(audio_urls)}")
    if len(with_audio) != len(audio_urls):
        print("  WARN: not every utterance got audio")

    # --- Inspect one mp3 ---
    print("\n--- Scenario 2: verify mp3 bytes for first utterance ---")
    first_url = doc.utterances[0].get("audio_url")
    if not first_url:
        print("FAILED: first utterance has no audio_url")
        return 1
    text_hash = first_url.rsplit("/", 1)[-1]
    audio_doc = await MonologueAudio.find_one(MonologueAudio.text_sha256 == text_hash)
    if not audio_doc:
        print(f"FAILED: MonologueAudio not found for {text_hash[:8]}...")
        return 1
    audio_bytes = bytes(audio_doc.audio_bytes)
    valid = _is_mp3(audio_bytes)
    print(f"  text_sha256       : {text_hash[:16]}...")
    print(f"  mp3 size          : {len(audio_bytes):,} bytes")
    print(f"  char_count        : {audio_doc.char_count}")
    print(f"  starts with mp3 magic: {valid}")
    if not valid:
        print(f"  first 8 bytes hex: {audio_bytes[:8].hex()}")

    # --- Scenario 3: RouteMonologue cache hit avoids TTS entirely ---
    # (LLM is non-deterministic, so regenerating the monologue produces
    # fresh text → fresh audio. That's by design. We instead verify
    # that a cache HIT on RouteMonologue skips TTS work.)
    print("\n--- Scenario 3: RouteMonologue cache hit, expect 0 new audio writes ---")
    audio_count_before = await MonologueAudio.find_all().count()
    t0 = time.time()
    doc_hit = await generate_monologue(
        polyline=polyline,
        route_label=ROUTE_LABEL,
        narration_themes=["history"],
        stop_interests=[],
    )
    dt = time.time() - t0
    audio_count_after = await MonologueAudio.find_all().count()
    new_audio_on_hit = audio_count_after - audio_count_before
    same_doc = doc_hit.id == doc.id if doc_hit else False
    print(f"  returned in {dt:.2f}s (expect <0.1s for cache hit)")
    print(f"  same doc as scenario 1: {same_doc}")
    print(f"  new audio docs written : {new_audio_on_hit}")
    cache_hit_clean = same_doc and new_audio_on_hit == 0

    # --- Scenario 4: direct text-hash dedupe ---
    # Construct a fake utterance list with one repeated text and one
    # new text. Call _attach_audio_urls. Verify: existing text reuses
    # cache; new text writes once.
    print("\n--- Scenario 4: direct text-hash dedupe via _attach_audio_urls ---")
    from app.services.monologue_pipeline import _attach_audio_urls
    repeat_text = doc.utterances[0]["utterance"]  # known to be in cache
    novel_text = "Slice B verification synthetic utterance " + str(int(time.time()))
    test_utts = [
        {"i": 100, "anchor": "test", "utterance": repeat_text},
        {"i": 101, "anchor": "test", "utterance": novel_text},
    ]
    audio_count_before = await MonologueAudio.find_all().count()
    await _attach_audio_urls(test_utts)
    audio_count_after = await MonologueAudio.find_all().count()
    new_audio_direct = audio_count_after - audio_count_before
    repeat_url_set = test_utts[0].get("audio_url") is not None
    novel_url_set = test_utts[1].get("audio_url") is not None
    print(f"  repeat-text got audio_url   : {repeat_url_set}")
    print(f"  novel-text got audio_url    : {novel_url_set}")
    print(f"  net new audio docs written  : {new_audio_direct} (expect 1)")
    dedupe_clean = repeat_url_set and novel_url_set and new_audio_direct == 1

    passed = (
        len(with_audio) == len(audio_urls)
        and valid
        and cache_hit_clean
        and dedupe_clean
    )
    print("\n" + "=" * 72)
    print("Slice B verification PASSED" if passed else "Slice B verification PARTIAL — check output")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
