# Companion Monologue v1 — Implementation Plan

**Status:** SHIPPED as of 2026-05-16. All six slices A–F merged to main.
Lifts the spike findings in `docs/companion-monologue-memo.md` into the
production v1.

**Date:** 2026-05-15 (initial), shipped 2026-05-16.

## Shipped commits

| Slice | Commit | What |
|---|---|---|
| Research | `da3bf39` | Spike scripts + this plan + memo |
| A | `5ee121d` | Backend authoring pipeline + endpoint |
| A | `eaa56f8` | End-to-end verification script |
| B | `d2fceea` | TTS pre-synthesis + audio serve endpoint |
| C | `1accd26` | Stop verification (Mapbox + OSM Overpass) |
| D | `e337de5` | Vibe selection UI on TripDetailScreen |
| E | `7a5e467` | Frontend track integration (NarrationService) |
| F | `336b5a1` | Trip-save + vibe-change prewarm |

What you actually see on-device today:

1. Open a saved trip → "What should the companion talk about?" chips
   + "Stop interests" list with add/edit/remove.
2. Save trip → backend fires both per-POI prewarm AND monologue
   prewarm in the background. By the time the user taps Start, the
   monologue artifact + mp3s are ready.
3. Edit a vibe and re-save → backend detects the change, warms the
   new `(polyline, vibe)` cache key. No re-Directions call.
4. Drive the trip → as GPS enters each town along the route, the
   companion speaks the next anchored utterance via the existing
   audio pipeline. Per-POI Wikipedia narration also fires for
   nearby POIs. Both tracks share the existing 30s spacing rule.

Section below is the original plan; left in place as the canonical
architectural description (what's built, why it's built that way,
and the decisions baked in along the way).

---

## What ships in v1

A new **monologue narration track** that runs alongside the existing per-POI
Wikipedia narration. The companion gets a coherent authorial voice across
the whole drive — short utterances (~30 words each, ~13s of speech), anchored
to towns the route passes through, shaped by a structured vibe object the
user fills in per trip.

### The vibe object — two dimensions

Per-trip preferences are structured (not free-text). The user fills in two
independent dimensions in the UI:

**1. Narration themes** — what the companion talks about
*Multi-select chips, default `["history"]`.*

| Theme | Content focus |
|---|---|
| **History** *(default)* | Stories about what happened along this route |
| **Landscape & nature** | What you're seeing — geology, ecosystems, weather |
| **Food culture** | Regional cuisines, food history, what's grown/eaten here |
| **Quirky / weird** | Oddities, roadside Americana, the strange stuff |

**2. Stop interests** — what you'd actually pull off the highway for
*List of items; user adds as many as they want. Default empty (no stops).*

Each stop interest = **category + optional free-text detail**:

| Category | Detail example |
|---|---|
| **Food** | *"Mexican, hole-in-the-wall"* or *"BBQ"* or *(empty)* |
| **Entertainment** | *"live music, blues"* or *"movie theater"* or *(empty)* |
| **Attractions / sights** | *"oddball museums"* or *"scenic viewpoints"* or *(empty)* |
| **Shopping** | *"antique stores"* or *"used bookshops"* or *(empty)* |

The detail is one free-text string the LLM understands — proved by the spikes.
Empty detail means "any stop in this category." Multiple interests stack
("Food: Mexican" AND "Entertainment: live music" = both kinds of stops
surface).

### Example trip vibe

A user might set:
- **Narration themes**: `["history"]`
- **Stop interests**: `[{category: "food", detail: "Mexican"}, {category: "entertainment", detail: "live music venues"}]`

The companion narrates Gold Rush + historical stories along the drive, and
also surfaces verified Mexican restaurants and live music venues as
stop cards. Both happen at the same time, on the same drive, from the same
vibe object.

### Explicitly in scope

- Two-dimensional structured vibe (narration themes + stop interests)
- Stop verification across all 4 stop categories (Mapbox Search Box + OSM Overpass fallback)
- Audio pre-synthesis at trip-save time, reusing existing TTS
- Per-(polyline, vibe) caching with sane invalidation
- Monologue plays in parallel with existing per-POI narration
- Editing the vibe regenerates content (idempotent via cache)

### Explicitly out of scope (deferred to v1.5 or later)

- User-defined constraints (kid-friendly, sober, max-detour-time, accessibility) — explicitly deferred
- Free-text natural-language vibe input (only structured chips + interest list)
- Fact-check pass via Opus (only needed for high-stakes vibes — true crime, politics, named people — which don't ship)
- Personalization from past Discoveries
- Canvas-side preview of the monologue script (audio-only delivery in v1)
- Multi-day trip handling (single polyline per monologue)
- Re-routes triggering monologue regeneration mid-drive
- "Tell me more" follow-ups specific to monologue utterances
- Marker-cluster fixes for monologue anchors

## Architecture (v1 concrete)

```
TRIP-SAVE (background, async)
  ↓
[1] Towns from polyline
    - Sample polyline ~every 25mi
    - Reverse-geocode each via Mapbox Geocoding
    - Dedupe by locality name; preserve along-route order
  ↓
[2] Route characterization
    - One Sonnet call with the route label
    - Returns ~500-word prose describing the corridor's identity
    - Cached by polyline_hash; effectively permanent
  ↓
[3] Monologue + stops authoring
    - One Sonnet call: characterization + town list + vibe object
      (narration_themes[], stop_interests[{category, detail}])
    - Returns 8-10 utterances tilted by narration_themes
    - Returns N stop suggestions for each stop_interest, each tied to a
      specific utterance (`tied_to_utterance: i`)
    - Cached by (polyline_hash, vibe_object_hash)
  ↓
[4] Stop verification (for every stop_interest the user set)
    - For each stop: Mapbox Search Box /forward → on-route check
    - Failover to OSM Overpass when Mapbox can't pin
    - Drop unverified, off-route, or business_status != OPERATIONAL
    - All four categories use the same verifier (Food, Entertainment,
      Attractions, Shopping)
  ↓
[5] TTS pre-synthesis
    - For each utterance: openai_tts.py → mp3
    - Cached by utterance-text hash
    - mp3 URLs stored in RouteMonologue

TRIP-START (foreground)
  ↓
[6] Trip-start refresh
    - Re-verify each stop's business_status + current_opening_hours
    - Drop newly-closed stops; keep monologue intact

DURING DRIVE (frontend)
  ↓
[7] NarrationService runs two queues
    - Monologue queue: fires when GPS enters a new town's vicinity;
      surfaces tied stop cards alongside the matching utterance
    - Per-POI queue: existing Wikipedia narration, unchanged
    - Existing 30s spacing rule deconflicts them
```

## Slices

### Slice A — Backend monologue generation
**Files (new):**
- `backend/app/services/town_extractor.py` — polyline → ordered town list
- `backend/app/services/monologue_pipeline.py` — characterize + author orchestration
- `backend/app/main.py` — add `POST /api/v1/route/monologue` endpoint

**Files (modify):**
- `backend/app/database.py` — extend `Trip` with `narration_themes: list[str]` (default `["history"]`) and `stop_interests: list[StopInterest]` (default `[]`); add `RouteMonologue` document

**Beanie model shapes:**
```python
class StopInterest(BaseModel):
    category: Literal["food", "entertainment", "attractions", "shopping"]
    detail: str  # free-text, can be empty

class RouteMonologue(Document):
    polyline_hash: str
    vibe_hash: str  # sha256 of canonical-form vibe object
    narration_themes: list[str]  # sorted
    stop_interests: list[StopInterest]  # canonicalized
    towns: list[dict]  # [{name, lat, lng}]
    characterization: str
    utterances: list[dict]  # [{i, anchor, utterance, audio_url?}]
    stops: list[dict]  # all verified stops across all stop_interests
    created_at: datetime
    class Settings:
        indexes = [
            [("polyline_hash", 1), ("vibe_hash", 1)],  # cache lookup
        ]
```

**Verification:**
- curl `POST /api/v1/route/monologue` for SF→Tahoe with `themes=["history"]`, `stop_interests=[]` → coherent monologue, 0 stops
- curl with `themes=["history"]`, `stop_interests=[{food, "Mexican"}, {entertainment, "live music"}]` → monologue tilted toward history themes, stops include Mexican places + live music venues, each tied to a real utterance
- curl twice with same key → second is cache hit (no LLM call)
- Edit detail field → new cache key, fresh authoring

**Effort:** 4-5 days

---

### Slice B — TTS pre-synthesis
**Files (modify):**
- `backend/app/services/monologue_pipeline.py` — wire openai_tts into the authoring flow
- `backend/app/services/openai_tts.py` — already async (reuse as-is)

**Behavior:**
- After Slice A authoring step, iterate over utterances and synthesize each
- Cache mp3 by `sha256(utterance_text)` so identical lines across different routes don't re-synthesize
- Store mp3 URL in each utterance dict
- Run as a background task at trip-save (same pattern as existing prewarm)

**Verification:**
- Each utterance's mp3 URL returns a playable file via `/api/v1/audio/...`
- Repeat utterances produce cache hits (no duplicate synthesis)

**Effort:** 1-2 days

---

### Slice C — Stop verification layer (Food now vibe only)
**Files (new):**
- `backend/app/services/poi_verifier.py` — Mapbox Search Box first, OSM Overpass fallback

**Files (modify):**
- `backend/app/services/monologue_pipeline.py` — call verifier when "food_now" in vibes
- `backend/app/database.py` — `RouteMonologue.stops[]` shape: `{name, town, lat, lng, place_formatted, business_status, hours, tied_to_utterance_i, source}` where `source` is `"mapbox"` or `"osm"`

**Behavior:**
- For each LLM-proposed stop: forward-geocode via Mapbox Search Box
- If no match or off-route: fall back to Overpass with the LLM-given name + a bounding box around the town
- Drop unverified picks (don't show user a stop we couldn't confirm exists)
- At trip-start: re-fetch `business_status` and `current_opening_hours` for each verified stop; drop if closed permanently

**Verification:**
- Spike a curl flow: monologue with `["food_now"]` for SF→Tahoe; ≥1 verified stop per town that has restaurants
- Manual test: closed-permanently sentinel place gets dropped at trip-start

**Effort:** 3-4 days

---

### Slice D — Vibe selection UI
**Files (modify):**
- `frontend/lib/models/trip.dart` — add `narrationVibes: List<String>` field
- `frontend/lib/screens/trip_detail_screen.dart` — multi-select chip row for the 4 vibes
- `frontend/lib/services/trip_service.dart` — include `narration_vibes` in JSON payload

**Behavior:**
- Default to `["history"]` on new trip
- Editing vibes triggers monologue regeneration server-side (idempotent — if cache hit for new key, no LLM work)
- Show a small "regenerating..." indicator while authoring runs

**Verification:**
- Toggle vibes on a saved trip; new monologue content reflects the change
- Default trip without explicit selection plays the History monologue

**Effort:** 2-3 days

---

### Slice E — Frontend track integration
**Files (modify):**
- `frontend/lib/services/narration_service.dart` — add `_monologueQueue`, town-entry detection
- `frontend/android/.../MapActivity.kt` — already plays mp3 via existing path; no change

**Behavior:**
- On trip-start, fetch the monologue (from cache if available) → populate `_monologueQueue`
- Track current town the GPS is in (via reverse-geocode or polygon containment when Tilequery lands)
- When GPS enters a new town anchor: fire next monologue utterance if any
- Existing 30s spacing rule prevents stepping on per-POI narrations
- Food now stops surface via the existing `narration_card` widget with Take Me There button (already built)

**Verification:**
- On-device drive of SF→Tahoe: both tracks fire correctly, spacing respected
- Switch off per-POI in Preferences (existing toggle) → only monologue fires
- Switch off monologue (new toggle? or just via vibe=[]?) → only per-POI fires

**Effort:** 4-5 days

---

### Slice F — Polish + tuning
**Verification:**
- E2E drive on a famous route (SF→Tahoe) and an obscure one (Bend→Burns equivalent)
- Cadence feels natural — utterances neither cram in clusters nor leave 90-minute silences
- No regression in existing per-POI narration tests
- Voice consistency check: 10 random monologue runs, voice doesn't drift across runs of same (route, vibes)

**Effort:** 2-3 days

---

**Total v1 effort: 16-22 days (~3-4 weeks of focused work).**

## Decisions baked in (from the planning conversation)

1. **One monologue per trip.** Re-routes mid-drive do not regenerate (deferred).
2. **Defaults to History** if user selects no vibes.
3. **Audio-only delivery** — no canvas-side script preview in v1.
4. **Both tracks run in parallel** — monologue does NOT replace per-POI.
5. **Verified stops only show for Food now vibe** — other vibes are pure narration.
6. **Same monologue on every replay of the same (route, vibes)** — variants are v2.
7. **Vibes blend without explicit weighting** — let the LLM distribute based on the route's character.

## Cache invalidation policy

| Object | Key | TTL | Invalidation triggers |
|---|---|---|---|
| `RouteMonologue.utterances` | `(polyline_hash, sorted_vibes_tuple)` | 90 days | Trip polyline changes; vibes change |
| Utterance mp3 | `sha256(utterance_text)` | effectively permanent | Never (text is the cache key) |
| `RouteMonologue.stops[].business_status` | per-stop | 24 hours | Trip-start refresh |
| Town list per polyline | `polyline_hash` | 90 days | Rare (Mapbox geocoding output is stable) |

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Multi-vibe monologue feels disjointed | Medium | Prompt explicitly asks for "thread across drive that weaves themes" — testable in Slice A |
| TTS voice doesn't match the monologue's intimate tone | Medium | Test OpenAI gpt-4o-mini-tts output on monologue utterances in Slice B; consider alt voices |
| Stops verification yield is too low for Food now to feel real | Medium-High | Slice C's OSM Overpass fallback is the mitigation; if still too low, ship Food now narration-only |
| Cadence feels wrong in real cars (too fast / too slow) | Medium | Slice F tunes on real drives; cadence is one config knob |
| Cache key explosion if users keep flipping vibes | Low | Bounded (4 vibes → 15 non-empty subsets); each combo costs only the LLM time, no permanent infra |
| Existing per-POI narration interferes with monologue spacing | Medium | The 30s rule is already in `NarrationService`; verify it covers both queues in Slice E |
| Monologue text contains a subtle factual error (low-stakes vibe) | Low-Medium | Acceptable risk for v1 with the 4 chosen vibes; user-saved facts is the existing audit trail |

## Open questions to resolve before Slice A starts

1. **Should we cap utterance count by trip length?** A 30-minute drive doesn't need 10 utterances. Proposal: 1 utterance per ~20 minutes of drive time, capped at 12.
2. **What's the GPS town-entry detection?** Options: (a) reverse-geocode current GPS every 30s, (b) precompute town bounding boxes at trip-save and check containment, (c) Mapbox Tilequery on place tiles. Lean toward (b) for offline safety.
3. **What happens on trip-start if the monologue isn't ready yet?** (background TTS still running). Proposal: per-POI narration plays as today; monologue plays whatever utterances are ready as they become available.
4. **Should the user be able to "skip" a monologue utterance mid-playback?** Existing narration_card has a dismiss button — propose reusing.
5. **Telemetry?** Are we tracking which vibes get picked, how often monologue utterances get skipped, etc.? Useful for v1.5 vibe tuning but not blocking.

## Rollback plan

- New `NARRATION_MONOLOGUE_ENABLED` feature flag, default `false` until proven on internal devices
- All backend artifacts are additive (no existing data modified)
- Frontend changes gated on the flag — when off, behaves exactly like today
- If feedback is bad, flag off → fully reverts; data persists for analysis

## Definition of done for v1

- All 6 slices verified
- E2E drives on SF→Tahoe and one obscure route pass without regression
- Existing 134 frontend tests + 35 backend tests still pass
- Internal feature-flag-on testing produces no defamation/false-claim flags
- Cost per route stays within budget (~$0.10–0.30 retail, near zero with cache)
- Decision log captured at end of build for v1.5 planning

## References

- Architecture memo: `docs/companion-monologue-memo.md`
- Spike scripts: `backend/scripts/spike_*.py` (six of them)
- Existing narration: `backend/app/services/wikipedia_facts.py`, `frontend/lib/services/narration_service.dart`
- Audio plumbing: `MapActivity.kt`, `backend/app/services/openai_tts.py`
- Companion-first reframe: `memory/companion_reframe.md`
- Spike guardrail (now lifted for this plan): `memory/spikes_dont_commit.md`
