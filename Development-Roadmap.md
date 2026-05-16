# Development Roadmap

**Last updated:** 2026-05-16

Single source of truth for what's done. When in doubt, trust git over any
other doc.

A note on numbering: the old step list (Steps 1–16) made sense before the
product reframe around the *companion*. The new structure below mirrors how
work actually shipped — by feature surface, not by sequential step. Step
numbers are preserved as labels where the work matches, but they're no
longer load-bearing.

---

## Shipped

### Foundation
- ✅ **Flutter + FastAPI + Mapbox stack**, dev environment, hybrid DB
  (Postgres + MongoDB + Redis), Docker for backend services.
- ✅ **Mapbox Navigation SDK integration** with turn-by-turn UI, route
  calc, voice guidance, native `MapActivity`, shared `FlutterEngine`,
  Flutter↔native method channel.
- ✅ **Mapbox SDK on stable `3.23.1`** (was `3.18.0-beta.1`) — paired with
  Maps `11.23.x` for the Flutter canvas. ABI conflict fix in commit
  `ef4116a` after the gradle/`dependencyResolutionManagement` debug.
- ✅ **Provider state management migration**, shared `FlutterEngine` to
  preserve state across activity boundaries.

### POI pipeline
- ✅ **POI data pipeline** — Mapbox Search API (15 categories), corridor
  extraction (5mi buffer), ranking, Redis caching. *(Step 3 in the old
  numbering.)*
- ✅ **POI discovery during active navigation** — "Find Stops" FAB,
  modal via `TransparentFlutterActivity`, in-place route update.
  *(Step 3.5.)*
- ✅ **Waypoint management** — add/remove/reorder, status tracking,
  arrival/departure detection, live progress card. *(Step 4.5.)*
- ✅ **Trip-scale detection** (`detect_trip_scale` in `polyline.py`) +
  per-kind distance filters in `fact_ranker`. *(Part of Step 5.)*

### Headline feature: the Whisper (Step 4) — SHIPPED
The product thesis: a companion that narrates interesting things about
what you're driving past. Two complementary tracks now in production:

- ✅ **Per-POI narration** — Wikipedia GeoSearch along the polyline,
  Claude Haiku summarization, OpenAI TTS pre-synthesis, on-device GPS
  triggers with 30s spacing, "Take me there" mid-nav re-routing, native
  banner inside `MapActivity`, narration markers + pulse animations.
- ✅ **Drive monologue** (v1 — see `docs/companion-monologue-v1-plan.md`)
  — LLM-authored sequence of utterances anchored to towns along the
  route, vibe-driven (history / landscape / food culture / quirky),
  verified stops surfaced for opt-in stop interests, audio pre-synthesized
  at trip-save time, plays in parallel with per-POI narration.
  Commits: `5ee121d` / `eaa56f8` / `d2fceea` / `1accd26` / `e337de5` /
  `7a5e467` / `336b5a1`.

### Trip planning (slice-A through slice-C)
- ✅ **Trip CRUD** — Beanie document, REST endpoints, Flutter model,
  MyTripsScreen, editable TripDetailScreen. *(Trip-planning brief
  slices A + B.)*
- ✅ **New trip wizard** with origin/destination Mapbox geocoding.
- ✅ **Trip canvas v1** — Flutter `mapbox_maps_flutter` map showing
  the route polyline + origin/destination pins. The canvas is a viewer
  in v1; typed pins / day strip / NL textbox are deferred. *(Trip-
  planning brief slice C v1.)*
- ✅ **Companion vibe UI on TripDetailScreen** — multi-select theme
  chips + add-stop-interest list. Vibe changes regenerate the monologue
  on save (cache hit if unchanged).

### Feedback + memory
- ✅ **Discoveries timeline** — server-side aggregation of `played` /
  `visited` / `saved` events per user, screen + dashboard entry.
- ✅ **Save / dismiss / tell-me-more / replay** events recorded for
  Phase 3 personalization.
- ✅ **Take-me-there** as the closed-loop "user actually went here"
  signal.
- ✅ **Narration mode preference** — Auto / Tap-to-hear / Off, plus
  the option to disable Mapbox turn-by-turn voice.

### Recommendations engine (Step 7 ancestor)
- ✅ **Four-dimensional scorer** (`stop_recommendations.py`),
  `EngineRequest` shape, `UserProfile.interests` curated + free-text
  inputs, PreferencesScreen.

---

## Active / next

Nothing in flight as of 2026-05-16. The monologue v1 was the last
focused effort; we're at a clean checkpoint.

Highest-leverage candidates for the next slice, in rough order of
product value:

1. **On-device E2E of monologue v1** — simulated drive on the emulator
   to confirm cadence, audio quality, and the new-vibe regeneration
   flow feel right. The pieces are individually green; the integrated
   experience hasn't been driven end-to-end yet.
2. **Yield tuning for verified stops** — Slice C produced 1 verified
   stop out of N proposed on the SF→Tahoe test. Loosen the on-route
   distance threshold, refine name-match heuristics, possibly raise
   the LLM's `stops_per_interest` cap.
3. **Trip-start business-status refresh** — re-verify each stop's
   `business_status` + current opening hours at drive-time so we
   never surface a "permanently closed" stop to the user. Skipped
   in v1 because it's only meaningful at trip-start.
4. **Visible monologue UX** — currently audio-only. A minimal
   inline indicator ("Companion: speaking @ Davis") would let users
   know the track is active without needing a full card. Cheap.
5. **Polygon-aware region triggers** — replace the proximity-to-
   centroid check with Mapbox Boundaries / Tilequery containment.
   See memory: `region_polygons_via_mapbox.md`. Cleaner semantics
   for big-area firing rules.
6. **Voice talkback (STT)** — natural driving-context way to react
   to whispers ("save that", "tell me more"). Push-to-talk + ~6
   commands. See memory: `voice_talkback.md`.
7. **Multi-day trip handling** — single polyline per monologue
   today; multi-day routes should generate per-day monologues or
   one long arc. See trip-planning brief.

---

## Deferred / parked

Real ideas with explicit owners that are not next:

- **Lodging integration** — explicitly deferred until we have a
  partnership (Booking.com / Amadeus / a real provider). Affiliate-
  link spam would undermine trust. Memory: nothing yet.
- **Buddy mode / passenger pairing** — pair a passenger's phone to
  the driver's trip so whispers can deepen with photos + Wikipedia
  links on their side, eyes-on-road on the driver's. Memory:
  `passenger_buddy_idea.md`.
- **iOS port** — Android-first until the companion has earned its
  keep here.
- **Step 8: Essential travel services** (gas / restrooms / EV) —
  not novel enough to be the next thing; layer in alongside the
  stop verifier when we expand stop categories.
- **Phase 2: CarPlay / Android Auto** — premature until we have a
  product worth integrating.
- **Phase 3: Weather, EV charging, monetization, analytics** —
  v2+ concerns.

---

## Honest status summary

- **Headline feature: shipped.** Both per-POI narration *and* the
  authored drive monologue are running. The product thesis is now
  load-bearing in code, not aspirational.
- **Trip planning surface: v1 viewer + vibe controls.** The canvas
  is a map view, not a full planner. Typed pins / day strip / NL
  textbox are real ideas that haven't been built.
- **Recommendations + Discoveries: shipped as supporting surfaces.**
  They feed the companion rather than standing on their own.
- **No active work in flight.** Clean checkpoint to either polish
  the monologue UX, expand the canvas, or open the next product
  thread.

## Infrastructure (not on the main list)

- ✅ Docker Compose stack (Postgres + MongoDB + Redis + backend)
- ✅ Local Mapbox docs library at `docs/mapbox/` (21 files)
- ✅ Auto-memory system at `~/.claude/projects/.../memory/`
- ✅ Companion-monologue spike scripts at `backend/scripts/spike_*.py`
- ✅ Per-slice verification scripts at `backend/scripts/verify_slice_*.py`
