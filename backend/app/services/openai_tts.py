"""
OpenAI TTS wrapper for narration audio.

The on-device Google TTS that ships with Android is functional but
robotic — it undercuts the "friend riding shotgun" voice that the LLM
worked so hard to produce. This service synthesizes the same text into
high-quality mp3 audio at fact-prep time. The device plays the mp3
directly; no on-device TTS engine is involved.

Synthesis happens once per (text, voice) tuple at trip-prep, cached in
POIContent alongside the text. Replays and re-trips cost zero
additional TTS calls.

Cost shape with tts-1 + nova at $15/1M chars:
  - 30 facts × (1 primary + ~2 follow-ups) × ~40 words × 5 chars/word
    = ~18,000 chars per route ≈ $0.27 cold first time
  - $0 for every re-drive or any user whose route overlaps a cached one

See: ~/.claude/plans/breezy-gliding-mountain.md → "Phase 1 — Cohesion (LLM)"
"""

from __future__ import annotations

import logging
import os
from typing import Optional

from openai import OpenAI, OpenAIError

logger = logging.getLogger(__name__)


# Primary model: gpt-4o-mini-tts. It's noticeably clearer than tts-1
# and accepts an `instructions` parameter that lets us prompt the
# delivery (warmth, pacing, "friend in the passenger seat") instead
# of leaving the model to guess. If a particular account / region
# doesn't have access, we fall back to tts-1-hd which is the next
# step down on the quality ladder and uses the same API surface.
_MODEL = "gpt-4o-mini-tts"
_FALLBACK_MODEL = "tts-1-hd"

# nova is the warm, natural-sounding voice that suits the "passenger-
# seat companion" framing. Other candidates: shimmer (gentler), sage
# (newer warm female), echo (warm male). Swap here if you want to
# A/B test — both models share the same voice set.
_VOICE = "nova"

# Tone instructions. Only honored by gpt-4o-mini-tts; tts-1-hd ignores
# it silently which is fine. Speaks directly to the magic we want:
# warm friend, not Wikipedia narrator.
_INSTRUCTIONS = (
    "You're riding shotgun on a road trip with a friend. Read this "
    "the way you'd actually tell them about a place — warm, curious, "
    "a little wry. Conversational pacing, never declamatory. Lean "
    "into the interesting beat and trust the listener to follow. "
    "Sound like a real person, not an audiobook narrator."
)

# Output format. mp3 is universally playable on Android via MediaPlayer
# without any extra decoder setup, and the file sizes are small.
_FORMAT = "mp3"


class TtsSynthesizer:
    """Thin sync wrapper around `client.audio.speech.create`.

    The client is injectable so tests can swap it for a stub. Production
    constructs the real OpenAI client off `OPENAI_API_KEY` from env.
    Returns raw mp3 bytes — caller decides where to store them.
    """

    def __init__(self, client: Optional[OpenAI] = None):
        self._client = client

    @property
    def client(self) -> OpenAI:
        if self._client is None:
            self._client = OpenAI()
        return self._client

    def synthesize(self, text: str) -> Optional[bytes]:
        """Synthesize [text] → mp3 bytes. Returns None on any failure
        so callers can fall back to local TTS gracefully. The text
        path remains usable regardless of whether synthesis succeeded.

        Tries `gpt-4o-mini-tts` first (with tone instructions) and falls
        back to `tts-1-hd` if the primary model isn't available on the
        caller's account. The fallback path silently drops the
        instructions parameter — older models don't accept it.
        """
        text = (text or "").strip()
        if not text:
            return None
        # Try primary model with instructions, then fall back.
        for attempt_model in (_MODEL, _FALLBACK_MODEL):
            audio = self._try_synthesize(attempt_model, text)
            if audio is not None:
                return audio
        return None

    def _try_synthesize(self, model: str, text: str) -> Optional[bytes]:
        """One attempt at a single model. Returns bytes on success,
        None on any failure (caller decides whether to retry with a
        different model)."""
        kwargs = {
            "model": model,
            "voice": _VOICE,
            "input": text,
            "response_format": _FORMAT,
        }
        # `instructions` is only meaningful for gpt-4o-mini-tts; the
        # older models will 400 on the unknown parameter, so we only
        # send it on the primary path.
        if model == _MODEL:
            kwargs["instructions"] = _INSTRUCTIONS
        try:
            response = self.client.audio.speech.create(**kwargs)
            audio = response.content
            if not audio:
                logger.warning(
                    "openai tts (%s): empty audio for %r", model, text[:40]
                )
                return None
            return audio
        except OpenAIError as e:
            # Don't escalate to error — primary-model misses are
            # expected when an account doesn't have access.
            logger.warning(
                "openai tts (%s) failed for %r: %s", model, text[:40], e
            )
            return None
        except Exception as e:
            logger.error(
                "openai tts (%s) unexpected error for %r: %s",
                model, text[:40], e,
            )
            return None
