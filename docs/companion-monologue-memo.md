# Companion Monologue Architecture — research memo

**Status:** spike findings, not a commitment. Nothing in this doc is wired into
the product. The work is `backend/scripts/spike_*.py` only. We can discard the
whole thing without affecting anything we ship today.

**Date:** 2026-05-15 (initial), expand on revisit.

## Context

The product reframe (Overview.md, `memory/companion_reframe.md`) made narration
— the *companion that whispers things about what you're driving past* — the
headline feature. We've shipped a per-POI narration pipeline (Wikipedia
geosearch + LLM summarize, see `wikipedia_facts.py` and `llm_summarizer.py`).
It works, but the output is **isolated facts**: "this bridge has a story";
"that town was a Gold Rush camp." It surfaces *discoveries* but not
*companionship*.

The spikes in this memo explore a different output shape: an LLM-authored
**drive monologue** — a sequence of short utterances written as a single
voice, anchored to specific towns along the polyline, with optional stop
suggestions that emerge from the same narrative. Per-POI narration surfaces
surprises. The monologue surfaces "someone who knows where you're going."
They're complementary; this memo describes the second.

## The architecture (in five stages)

```
Trip-save  ─→  [1] polyline → towns the route passes through
                  (Mapbox Directions + reverse-geocoded samples)
                  Cacheable by polyline hash. Free.

           ─→  [2] LLM characterizes the route
                  (~3 paragraphs of history / arc / themes)
                  Cacheable by polyline hash. ~$0.02 via Sonnet.

           ─→  [3] LLM authors monologue + stops
                  (8 utterances + 4 stops, tied via "tied_to_utterance")
                  Vibe overlay flexes content; voice stays constant.
                  Cacheable by (polyline, vibe). ~$0.05 via Sonnet.

           ─→  [4] (Conditional) fact-check pass for high-stakes vibes
                  Different model (Opus) reviews every claim;
                  rates HIGH / MEDIUM / LOW; rewrites or drops as needed.
                  Cacheable by (polyline, vibe). ~$0.10 via Opus.

Trip-start ─→  [5] POI verification for stops only
                  Mapbox Search Box /forward + on-route polyline check.
                  OSM Overpass fallback for rural / specialty stops.
                  Per-trip refresh of business_status + hours.
                  Drop closed-permanently picks before user sees them.
```

Stages 1–3 always run. Stage 4 runs when the vibe classifier flags the
overlay as high-stakes (true crime, politics, named people, anything where
a fabricated detail is a real liability). Stage 5 runs at trip-start to
refresh volatile data (hours, status) that we can't cache.

## What's proven (and the spike file for each)

| Claim | Demonstrated by |
|---|---|
| Polyline → towns works for both famous and obscure routes | `spike_stop_suggester.py` (SF→Tahoe) |
| LLM characterization is genuinely good travel prose, route-specific | `spike_route_narrative.py` (both SF→Tahoe and Bend→Burns) |
| Characterization context measurably shifts downstream picks | Same — narrative picks beat baseline 2-to-0 on SF→Tahoe |
| Monologue voice is consistent and conversational | `spike_drive_monologue.py` (SF→Tahoe and Bend→Burns) |
| Vibe overlay flexes content without breaking voice | `spike_drive_monologue.py` with `"food history"` overlay |
| Multi-vibe (narration theme + stop categories) works in one prompt | `spike_factcheck_monologue.py` with true-crime + margaritas + antiques |
| Stops can be generated *with* the monologue (tied, narrative-coherent) | `spike_monologue_with_stops.py` |
| Fact-check pass catches fabricated claims while preserving voice | `spike_factcheck_monologue.py` — 0 dangerous claims survived |
| LLM-first stop generation finds cult-favorite places the pipeline misses | `spike_llm_first.py` (La Corneta in Glen Park) |
| Pipeline (Mapbox /category + LLM filter) works for narrow categories | `spike_stop_suggester.py` for attractions — strong picks |

## What's *not* proven

- **POI verification yield on rural and specialty stops is low.** Mapbox
  Search Box can't pin Hangman's Tree, Coffeebar Truckee, Glass Buttes,
  Stinkingwater Pass, Brothers Store, etc. The architecture proposes good
  picks; the verification step drops too many. The fix is OSM Overpass as a
  fallback verifier (free, much deeper rural coverage). Not spiked yet.
- **Whether users actually want the monologue track.** All testing has been
  eyeball + LLM critique. No on-device, no real users, no TTS playback.
- **Whether the architecture handles short trips, urban-only trips, or
  international trips.** Only US multi-hour drives tested.
- **Whether the Mapbox Directions polyline matches what the device's native
  Navigation SDK actually drives** (occasional small divergences from
  real-time traffic re-routes; probably acceptable, not verified).

## Cost model (verified by running spikes, not estimated)

| Operation | Cost per route (retail) |
|---|---|
| Stage 1 (towns from polyline) | ~$0 (Mapbox free tier) |
| Stage 2 (Sonnet characterization) | ~$0.02 |
| Stage 3 (Sonnet monologue + stops) | ~$0.05 |
| Stage 4 (Opus fact-check) | ~$0.10 (only for high-stakes vibes) |
| Stage 5 (Mapbox Search Box verifications) | ~$0.05 |
| **Total — low-stakes vibe** | **~$0.12 retail, $0 after first user (cache)** |
| **Total — high-stakes vibe** | **~$0.22 retail, $0.05 after first user (only stage 5 refreshes per-trip)** |

Per-route caching key: `(polyline_hash, vibe_string)`. Stage 5 alone refreshes
per-trip-start. After the first user on a given (route, vibe) pair, every
subsequent user pays only the per-trip refresh (~$0.05) — and most of that is
under Mapbox's free tiers anyway.

## How this fits with the existing narration system

This **doesn't replace** per-POI Wikipedia narration. They serve different
jobs:

| | Per-POI narration (current, shipped) | Drive monologue (this memo) |
|---|---|---|
| Surfaces | Surprises, discoveries near GPS | Coherent narrative arc across drive |
| Grounding | Wikipedia article per POI | Route characterization + town list |
| Voice consistency | Per-fact LLM call → voice drift | One author, one voice |
| Reactive vs proactive | Reactive (GPS triggers fact) | Proactive (script unfolds along route) |
| What it feels like | Knowledgeable friend who notices things | Knowledgeable friend who knows the drive |

They can run in parallel on the same drive — the monologue at lower frequency
(8–10 utterances over 4 hours), the per-POI narration filling in around it.
Both go through the existing `narration_card` widget and `speakNarration`
method channel. **No native or Flutter UI changes required to ship the
monologue track** — only new content authoring.

## Open architectural questions

1. **Vibe classifier for stage 4 gating.** Need a cheap (~$0.001 Haiku) check
   that decides "does this vibe involve high-stakes claims (true crime,
   specific named people, contested politics)?" Spike outline: pass the vibe
   string + a list of risk categories, return a boolean. Not yet built.
2. **OSM Overpass verifier as Mapbox fallback.** When Mapbox Search Box
   misses a stop, query Overpass with the LLM-given name + a bounding box.
   Free, no key, but slower (~1–3s per query, vs Mapbox's ~200ms). Probably
   acceptable as fallback only.
3. **Vibe builder UI.** The user types or speaks a natural-language vibe
   ("true crime + margaritas + antiques"); we parse it into the structured
   overlay used by stage 3. Could be a single text field, or a few
   suggested-vibes chips with a custom-input option. Not yet built.
4. **How frequently the monologue track plays.** ~8–10 utterances over a
   4-hour drive = one every ~25 min. Tune empirically vs per-POI cadence.
5. **Personalization from past Discoveries.** A user who saved 5 Gold Rush
   facts has revealed a vibe preference. Feed that into the vibe overlay
   automatically. Spike not yet built.
6. **Multi-day trips.** The monologue assumes a single continuous drive.
   For multi-day routes, do we generate a fresh monologue per day's
   polyline, or one arc that spans all of it? Untested.

## Production guardrails worth preserving

- **The fact-check pass is non-optional for high-stakes vibes.** A false
  true-crime claim about a real person is a defamation risk. The spike
  proved Opus catches what Sonnet slips through. Both stages required when
  the vibe involves named people or alleged crimes.
- **Voice consistency depends on the route characterization.** Without
  stage 2, downstream picks regress to "could-exist-anywhere" tourist
  bait. Don't skip the characterization step in any production pipeline.
- **No fabricated stops should reach the user.** Verification must happen
  before any UI surface. The monologue track can keep narrative references
  to places we can't pin (e.g., "an antique shop on Main Street") as
  ambient color, but a *clickable* stop must be verified.
- **Cache the artifact, not the API calls.** A polished monologue +
  verified stops is what the next user wants. Don't waste time re-running
  the pipeline if a previous user already produced and approved the artifact
  for the same (route, vibe). Cache invalidation: time (~90 days for
  monologue, ~24 hours for stop status).

## Decision points before any of this gets built for real

In order of "what to know first":

1. **Is the monologue track what we want to ship next?** Or do we want to
   put cycles back on (a) the existing narration polish, (b) the canvas
   surface, (c) something else?
2. **Which vibes ship at launch?** Probably a small curated set (history,
   landscape, food culture, oddities, nature/wildlife) before exposing
   free-text. The high-stakes ones (true crime, politics) ship later or
   never — even with fact-check, brand risk is real.
3. **Pre-trip canvas vs in-drive only.** Layer 1+2+3 produces a written
   monologue script we could *show on the canvas pre-trip* as "here's what
   you'll hear on the drive" — turning the canvas into a planning surface
   for the *audio experience*, not just the route. Untested but cheap to
   try.
4. **Cost ceiling.** At ~$0.22 per high-stakes route uncached, what's the
   user-volume budget? Even at $5,000/mo we'd cover ~20,000 unique
   (route, vibe) pairs per month — but most users repeat routes, so the
   effective per-active-user cost is much lower.

## References

- Memories: `memory/companion_reframe.md`, `memory/narration_voice.md`,
  `memory/check_official_docs_first.md`, `memory/spikes_dont_commit.md`
- Spike scripts: `backend/scripts/spike_*.py` (six of them today)
- Existing narration: `backend/app/services/wikipedia_facts.py`,
  `backend/app/services/llm_summarizer.py`, `frontend/lib/services/narration_service.dart`
- Audio plumbing: `MapActivity.kt` (speakNarration handler), Mapbox
  voice player, OpenAI TTS via `backend/app/services/openai_tts.py`
