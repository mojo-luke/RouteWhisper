# RouteWhisper — Product Overview

## Goal

A mobile navigation app that narrates interesting facts about towns, landmarks, and POIs as the user drives, and proactively suggests stops along the route. Differentiator vs. generic nav: passive storytelling + smart road-trip detours, not just turn-by-turn.

## Architecture summary

- **Client:** Flutter app, native Android (Kotlin) for Mapbox NavigationView, method channels bridging the two. iOS planned, not yet built.
- **Backend:** Python FastAPI. Returns route-scoped POIs and facts. Redis for caching.
- **External:** Mapbox (maps, navigation, search). TTS provider TBD (`flutter_tts` or pre-rendered audio).
- **Data sources for facts/POIs:** Mapbox Search API (POIs, currently used). Wikipedia / Wikidata / GeoNames (facts, planned). Yelp / Google Places (curated stops, planned).

## Core design decisions

### 1. Pre-fetch the whole route's POIs upfront, don't poll live

When the user sets a destination:

1. Fetch full route geometry from Mapbox Directions.
2. Compute a corridor (1–2 mile buffer either side of the polyline).
3. Batch-query POIs along the entire corridor.
4. Rank, cache, and organize by route position.
5. During the drive, trigger pre-loaded narrations from GPS position.

**Why:** Faster, more reliable, works in poor signal, lets us pick the best fact across the whole trip rather than locally optimizing each mile, cheaper API usage. Implemented for POI search; not yet for facts.

### 2. Fact selection: 1 best fact auto-narrated, more on demand

Each POI gets one auto-narration; 2–5 additional facts are available on tap or voice request.

Ranking criteria for the "best" fact:
- **Uniqueness** — quirky beats common
- **Historical significance** — major events beat minor trivia
- **Local relevance** — town-specific beats generic
- **Brevity** — 10–15 second narrations beat long stories

Spacing rules: minimum 30–60s between auto-narrations; density caps in dense areas; longer gaps at highway speeds.

### 3. POI density adapts to trip scale

- **Long distance (100+ mi):** state borders, national parks, historic battlefields, cities >50k pop, major roadside attractions.
- **Regional (20–100 mi):** county seats, regional history, notable architecture, festivals.
- **Local (<20 mi):** historic buildings, neighborhood stories, local restaurants, art installations.

This keeps a cross-country drive from being drowned in suburban-restaurant trivia, and a city errand from missing the cool corner cafe.

### 4. Time budget as a UX dial

Users set their flexibility level; the app adapts:

- **In a hurry** → narration only, no detour suggestions, fastest path.
- **Moderate** → only must-see suggestions (4.5+ stars, ≤30 min stops).
- **Discovery mode** → full suggestions including multi-hour activities, scenic detours.

Real-time adjustment: app can detect when the user is consistently skipping suggestions and offer to switch mode.

## Future considerations (not on near-term roadmap)

These have all been thought about but are deliberately deferred until the core narration product exists. Each is a one-line placeholder, not a commitment:

- **Multi-day trip planning** — auto-segment >8h trips, suggest overnight cities, integrate hotel booking APIs.
- **Buddy mode** — driver/passenger UI split with real-time route sync between two devices.
- **Essential services** — gas stations (GasBuddy pricing), restroom finder, fuel-level monitoring (OBD-II where available).
- **Vehicle integration** — Android Auto / CarPlay.
- **Weather awareness** — storm-aware indoor activity suggestions.
- **EV charging** — station finder integrated with stop suggestions.
- **Offline mode** — full trip data download for poor-signal areas.
- **Voice-first UX** — "Hey Google, add that winery to RouteWhisper."
- **Premium features / partnerships** — restaurant/hotel booking commissions, sponsored recommendations.
- **Trip memory** — saved discoveries, shareable journals.

The mistake to avoid: planning these in detail before the headline narration feature works. Each one expands the surface area of "what does the app do" before the answer to that question is even functional.
