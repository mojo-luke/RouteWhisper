# Development Roadmap

**Last updated:** 2026-05-06

This is the single source of truth for what's done. When in doubt, trust git over any other doc.

A note on numbering: commits sometimes used different step numbers than this doc (e.g., waypoint work was tagged "Step 5" in commits but is "Step 4.5" here; "Step 3.5" was added retroactively after POI-during-nav work landed). The numbering below is the canonical version going forward.

---

## Phase 1: Core application

### ✅ Step 1: Project setup & architecture
Flutter project + FastAPI backend + dev environment + database schema. Done.

### ✅ Step 2: Basic navigation foundation
Mapbox Navigation SDK integrated, route calc, location tracking, turn-by-turn UI, navigation camera, voice guidance, trip progress display. Commits `f56c701`, `381d9ab`, `e1f3f14`.

### ✅ Step 2.5: Native Mapbox navigation activity
`MapActivity` with Mapbox NavigationView, Flutter ↔ native method channel for launching it, shared `FlutterEngine` for state preservation. Commits `2a824a8`, `3e1926f`, `c959d72`.

### ✅ Step 3: POI data pipeline
Mapbox Search API integration (15 categories), `POST /api/v1/route/pois`, route corridor extraction (5-mile buffer), POI ranking, Redis caching with 1-hour TTL. Commit `5e8f4cf`.

### ✅ Step 3.5: POI discovery during active navigation
"Find Stops" FAB on `MapActivity`, opens POI modal via `TransparentFlutterActivity`, adding a POI updates the route in-place without leaving navigation. Commit `c959d72`.

### ❌ Step 4: Core narration system
**Headline feature, not started.** TTS integration, fact delivery timing, fact-ranking algorithm, audio queue management. The app's name is "RouteWhisper" — this is the product thesis.

### ✅ Step 4.5: Waypoint management
Add/remove/reorder waypoints, status tracking (pending/active/completed/skipped), stop duration tracking, arrival/departure detection (>50m AND >5mph), live waypoint progress card on `MapActivity`. Commits `58a2261`, `9b4183a`. *(Numbered "Step 5" in those commits.)*

### ❌ Step 5: Hierarchical POI strategy
Trip distance detection (long/regional/local), POI filtering by trip scale.

### ❌ Step 6: Time budget system
User-set time flexibility, suggestion filtering by time constraints, dynamic adjustment.

### ❌ Step 7: Road trip stop recommendations
Beyond the existing POI search — interest profiling, stop categorization (food/shopping/outdoor/etc.).

### ❌ Step 8: Essential travel services
Gas stations (GasBuddy), restroom finder, fuel level monitoring.

### ❌ Step 9: Buddy mode
Driver/passenger UI split, real-time route sync between devices.

### ❌ Step 10: Multi-day trip planning
Trip segmentation, hotel API integration, day-by-day itineraries.

### ❌ Step 11: UX & polish
Onboarding, preferences, trip history, performance/battery.

### ❌ Step 12: Testing & QA
Real-world drive tests, performance optimization, UAT.

---

## Phase 2: Vehicle integration

### ❌ Steps 13–15: CarPlay, Android Auto, polish

---

## Phase 3: Future enhancements

### ❌ Step 16: Advanced features
Weather, EV charging, community content, monetization, analytics.

---

## Infrastructure (not on the step list, but done)

- ✅ Provider state management migration (commits `691872e`, `d16d76e`)
- ✅ Docker support for backend services (commit `4f84d1c`)
- ✅ Local Mapbox docs library at `docs/mapbox/` (21 reference files)

---

## Honest status summary

- **Done:** Steps 1, 2, 2.5, 3, 3.5, 4.5 = 6 of 19 (~32%) — but several of these were unplanned additions, so the original roadmap is ~5/17 (~29%).
- **Headline feature unbuilt:** Step 4 (TTS narration). Time has gone into infrastructure (waypoints, POI plumbing, Provider migration, the Flutter↔native engine fix) rather than the product thesis.
- **Phase 2 and 3 should not be planned in detail until Phase 1 has the narration feature working** — without it, this is a generic Mapbox nav wrapper.
