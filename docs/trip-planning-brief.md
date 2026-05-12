# Product brief: Trip planning

## Context

The recommendations brief (signed off, `docs/recommendations-brief.md`)
specs the *engine* that scores and ranks stop candidates. It references
"pre-trip planning" as one of the engine's four input surfaces but
doesn't define what that surface *is*. This brief defines it.

The user framed trip planning as a "real game changer" with two distinct
use modes:

1. **Local** — "Plan a local trip (fun things to do around me, events
   near me)"
2. **Long** — "A long road trip (things I want to do along the way,
   number of stops + distance or location-based overnight stays)"

Decided this session:
- **Two distinct products**, not one mode-aware surface. Local and long
  have different mental models, different inputs, different UIs.
- **v1 depth is user-controlled** — must support everything from "wing
  it entirely" to "pre-pinned overnight lodging + scheduled meal stops."
- **Events are v2** — v1 sticks to static Mapbox POIs.
- **Lodging in v1 is find + deep-link to booking site** (Booking.com,
  Airbnb, Hipcamp). True in-app booking (option 3) sketched separately
  as a known v3 path.
- **Long-trip UI is hybrid canvas + NL textbox** — canvas is source of
  truth, NL is a shortcut that mutates canvas.
- **"Wing it" regions** are explicit user marks that don't auto-suggest
  pre-trip but cause the in-nav engine to ramp up suggestion cadence
  inside that region.

Sources incorporated:
- `docs/recommendations-brief.md` — engine interface, four-dimension
  scoring, two-layer personalization (categories + interests)
- `Overview.md` — trip-scale tiers (local/regional/long), time-budget
  modes, Step 10 multi-day intent
- `Development-Roadmap.md` Step 10 — "Auto-segment >8h trips, suggest
  overnight cities, integrate hotel booking APIs"
- Conversation today — both products, user-controlled depth, NL textbox
  as input shortcut, wing-it semantics

## Two products

| | **What's around me?** | **Plan a road trip** |
|---|---|---|
| Entry | Tab/button on dashboard | Tab/button on dashboard |
| Inputs | Current location, time window | Origin, destination, date range |
| Output | Discovery feed (filtered, mapped) | Saved itinerary on a canvas |
| Persistence | Bookmarked places (lightweight) | Trip records (versioned, editable) |
| Cold-start | Works at minute one | Works at minute one (with prompts) |
| Surface complexity | Lower — feed + map | Higher — canvas + timeline + NL |

Both products call the same recommendation engine (see recs brief). They
differ in *invocation context* — `planning_local` vs `planning_long` —
and in how results are presented and persisted.

## Product 1 — "What's around me?" (local discovery)

### Goal
Help a user discover fun nearby stops without requiring a destination.
"It's Saturday, I have a few hours, what's good around here?"

### Entry & flow
- Top-level destination on the dashboard, peer of "Plan a road trip"
- Opens to a map + filter chip strip + result feed
- Defaults: current location, today, all categories
- User narrows by:
  - Time window (today / tomorrow / this weekend / next 7 days)
  - Distance from me (5 / 15 / 30 mi)
  - Categories + interests (pulled from profile, editable)
  - Free-text filter (LLM-normalized at submit, same path as interests
    in the recs brief)

### What the engine returns
- Calls the recs engine with `invocation: planning_local`, context =
  `{current_location, trip_scale: local, time_budget_mode: discovery}`
- Returns up to ~20 ranked candidates (the engine's `limit` cap)
- Local-trip *auto-discovery silence* (from the recs brief) does NOT
  apply here — this is the user-invoked planning surface, always
  responds.

### Display
- Map view with pins
- List view sorted by score (toggle)
- Tapping a candidate opens a detail sheet (name, photos when available,
  rating, distance, "Save" + "Plan a trip there")

### Persistence
- "Save" bookmarks a place to the user's profile (`bookmarked_pois`,
  new field). Persists across sessions, syncs through Supabase user.
- Saved places appear at the top of future "What's around me?" sessions
  in their area.
- NO trip-level persistence here. Saved places are just bookmarks.

### Cold-start
Works on minute one — current location is enough. With no profile data,
fall back to the engine's no-prefs path (broad categories, quality bar
in moderate mode). The screen never feels empty.

### v1 non-goals
- Events / time-filtered stuff (v2)
- Saving as a "trip" with route + ETA (use "Plan a road trip" for that)
- Group / share

## Product 2 — "Plan a road trip" (long-trip canvas)

### Goal
Let a user plan a multi-stop, multi-day road trip with any level of
planning depth — from a fully-specified itinerary with pre-booked
lodging to "drive from SF to Portland and wing the middle."

### Entry & flow
1. User taps "Plan a road trip" on the dashboard.
2. Wizard collects the minimum: origin, destination, date range
   (or "anytime"). Optional: arrival time, daily driving cap.
3. Land on the **canvas**. System pre-fills a draft based on:
   - The recs engine's planning response for the route
   - User's profile (interests, time-budget mode)
   - Auto-detected multi-day breaks if total drive > daily cap

### The canvas

Three coordinated panels:

1. **Timeline strip** (top) — horizontal scroll. One column per day.
   Each day shows the stops scheduled for it, with rough times. Daily
   driving total visible. Tap a day to focus it on the map.

2. **Map** (middle) — the route with all pin types drawn. Pinned stops
   in solid color, suggested stops greyed/dashed, wing-it regions
   shaded.

3. **NL textbox** (bottom) — "Tell me what to change." User types
   ("add a coffee stop in Eugene", "I already have a hotel in
   Mendocino, here's the address", "make day 2 scenic", "remove the
   Walmart"). LLM parses → emits structured canvas operations
   (`pin_stop`, `set_lodging`, `mark_wing_it`, `remove_stop`,
   `set_day_intent`). Canvas updates. Textbox is a shortcut, not a
   separate output channel.

### Four pin types on the canvas

| Pin type | Origin | Behavior |
|----------|--------|----------|
| **Anchor stop** | User pinned (canvas tap, NL, or imported) | Route routes through. Engine never replaces. |
| **Suggested stop** | Engine output, not yet committed | Greyed/dashed on map. User taps to promote → becomes anchor. Or taps "dismiss" → removed. |
| **Lodging anchor** | User-pinned OR engine-suggested overnight | Special anchor type. Carries time-of-day = "evening", drives day boundaries. |
| **Wing-it region** | User explicit mark (NL or canvas long-press on a route segment) | No stops planned. Pre-trip canvas stays empty here. **In-nav engine ramps up suggestion cadence inside this region.** |

### Multi-day & overnight logic

- **Daily driving cap** defaults to 6 hr / 350 mi (configurable per
  trip; future: per-user setting). When total drive exceeds the cap,
  the system inserts day boundaries.
- **Day boundary needs an overnight stop**. Engine searches for lodging
  near the natural break point (rough rule: within 30 mi of the daily
  total target).
- **Lodging types** the user can specify: hotel, Airbnb-style rental,
  campground. Profile interest tags can express preferences ("KOA
  campgrounds", "boutique hotels", "off-grid Airbnbs").
- User can mark any overnight as **"already booked"** — paste a name /
  address and the system uses it as a lodging anchor without
  re-searching. This handles the "I have the first hotel sorted but
  not the second" case cleanly.

### Lodging integration: v1 (find + deep-link)

- Lodging candidates returned by the engine include: name, photos
  (if Mapbox returns them), rating, price tier (if available),
  approximate detour cost.
- A "Book on [partner]" CTA on each card opens the partner's site in
  the device's web browser with affiliate-tagged URL.
- Required new pieces:
  - Lodging-as-a-category fan-out in the engine (`hotel`,
    `bed_and_breakfast`, `campground`, `hostel`, `vacation_rental`)
  - Affiliate ID configuration per provider (Booking.com,
    Hipcamp; Airbnb has no public booking API — treat as web-link
    only)
  - URL templating per provider
- What this v1 explicitly doesn't do: hold inventory, manage cancellations,
  surface live pricing, persist booking confirmations.

### Lodging integration: v3 sketch (in-app booking via partner APIs)

Documented here so it's a known path, not a surprise:

- **Partnerships required**: Booking.com Express (B2B agreement, ~2–6 wk
  approval), Hipcamp partner program, Expedia EAN. Airbnb has no
  third-party booking API — would remain deep-link only.
- **New backend surface**: per-provider adapter modules behind a
  unified `LodgingProvider` interface. Search, get-details, hold-rate,
  create-booking, cancel.
- **Auth + secret rotation**: each provider's tokens stored
  server-side; never sent to the client.
- **Payment**: either Stripe-on-our-side (we settle with providers)
  or the provider handles payment directly via their hosted checkout
  in an in-app webview. Second is much simpler legally.
- **Confirmation persistence**: a `BookedLodging` collection in
  MongoDB linked to a trip record. Includes provider, confirmation
  number, cancellation deadline, status (pending/confirmed/cancelled).
- **Customer support**: a real surface area we don't currently have.
  Cancellations, name corrections, missing nights — all flow through
  whatever support contract we have with the providers.
- **Estimated effort**: 6–8 weeks per provider for the first one,
  faster for subsequent ones thanks to the shared adapter contract.
- **Why deferred**: scope, partnership friction, real money on the
  line. v1 deep-link captures most of the "I want to book lodging
  during planning" value at a tiny fraction of the cost.

### NL textbox semantics

Examples and the structured operation each emits:

| User types | LLM-parsed operation |
|------------|----------------------|
| "Add a coffee stop in Eugene" | `pin_stop({category: coffee, location_constraint: "in Eugene"})` |
| "Make day 2 scenic" | `set_day_intent(day: 2, interests: [scenic])` |
| "I already booked a hotel at 123 Main St Mendocino" | `set_lodging(day: 1, status: booked, address: "123 Main St Mendocino")` |
| "Remove the Walmart" | `remove_stop(matching: "Walmart")` |
| "Wing it from Eureka to Crescent City" | `mark_wing_it(from: "Eureka", to: "Crescent City")` |
| "Arrive by 4pm on day 3" | `set_arrival_constraint(day: 3, time: "16:00")` |

The LLM runs at submit time, not on every keystroke. Failed parses
return a helpful "I didn't catch that — can you rephrase?" rather
than a stack trace.

### Persistence

- A `Trip` record per planned trip:
  `{id, user_id, name, origin, destination, dates, days[], pins[],
    constraints, created_at, updated_at}`
- Stored in MongoDB (consistent with profile / history collections)
- "My trips" list on the dashboard shows saved trips, last edited first
- Each day stores its pins, wing-it regions, lodging
- Edits are first-write-wins on the canvas; offline edits sync on
  reconnect (basic last-write-wins; no real merge needed in v1)

### Cold-start

Even with no profile, no history, the canvas works:
- Wizard asks origin/destination — the only required inputs
- Engine's planning-mode response always returns *something*, even
  without prefs (per the recs brief)
- The pre-filled draft has suggested stops the user can promote or
  dismiss. Empty canvas is never shown.

### v1 non-goals

- **Group / co-planning** — one user, one trip, one device for now
- **Calendar integration** — no Google/Apple calendar sync
- **Events (concerts / festivals / one-off)** — v2
- **In-app booking** — v3 (sketched above)
- **Real-time price tracking** for lodging — v3
- **Optimization solver** for "best order of N pinned stops" — v1 keeps
  the user-specified order; reorder is manual

## How both products plug into the recommendation engine

The engine designed in the recs brief takes `EngineRequest = {context,
intent}`. Trip-planning adds two new `intent.invocation` values:

- `planning_local` — context includes `current_location` and
  `time_window`; no `route_polyline` (no trip yet)
- `planning_long` — context includes `route_polyline` (full planned
  route), the canvas state (pinned, suggested, wing-it), the user's
  per-trip constraints

The engine returns ranked candidates as before. The planning UIs are
*consumers* of those candidates; they decide how to display, persist,
and let the user act on them. **The engine doesn't change** beyond
adding the two new invocation values + a planning-mode silence rule
(never silent — always returns).

## Wing-it regions: pre-trip vs in-nav behavior

| | Pre-trip canvas | In-nav |
|---|---|---|
| Suggestions inside region | None drawn / none persisted | Auto-poll cadence *ramps up* (e.g., 2x normal frequency, until 2 dismissals as usual) |
| Quality bar | n/a (no surface) | Same as user's time-budget mode |
| Manual "Suggest a stop" FAB | Works as always | Works as always |

So wing-it doesn't reduce the quality bar — it just opens the auto-poll
floodgates inside the user-marked zone. The user is telling the system
"this is the part where I want you to talk more."

## Cold-start as a unified concept

Cold-start was an open question in the recs brief. Trip planning
clarifies it:

- **The user's first interaction with the app is likely *planning a
  trip*, not driving one.** Planning happens first; nav happens
  later. Both products above work for new users on minute one.
- **By the time we're driving, the user has told us things** — through
  the planning wizard, the canvas pins, or the NL textbox.
- So the recs brief's "trip 1 silence on auto-poll" rule remains, but
  in practice trip 1 is the first navigated trip, which is rarely the
  first time the system has seen the user.

## What's NOT in scope for this brief

- The recommendation engine itself (covered separately)
- Step 4 narration (separate brief required)
- Voice input to the NL textbox (text-only v1; voice in a future LLM-
  layer brief)
- Sharing trips with other users
- Multi-user collaborative editing
- Calendar / contacts integration
- Webhook / push notifications about trip changes

## Open questions (revisit during implementation)

1. **Date constraint UX** — what does "anytime in October" mean to the
   system? Resolve to a representative date for engine scoring? Compute
   for each Saturday in October?
2. **Daily driving cap defaults** — 6 hr / 350 mi feels right for adults
   on highways; what about EV charging stops? Defer EV-awareness; brief
   stays gas-and-petrol for now.
3. **Lodging "already booked" data** — minimum is name + address. Do we
   want to capture confirmation number for the user? Probably yes, but
   purely as a note (we don't query the provider).
4. **Multi-traveler stop time** — a family of 4 stops longer than a
   solo driver. Profile setting?
5. **NL parse failure UX** — what does the user see on "I didn't
   catch that"? A toast? A modal? Inline error in the textbox?
6. **LLM provider for the textbox** — Anthropic / OpenAI / local. Cost
   per parse times typical edit volume = budget call. Per-trip parse
   count probably 10–30; not prohibitive.
7. **Trip versioning** — if the user edits a trip mid-journey, do we
   keep the original? Probably no in v1; trip is mutable single record.
8. **"What's around me?" and the existing in-nav POIDashboard widget**
   — different lifecycle (pre-nav vs in-nav) but visually similar.
   Worth reusing the cell/card components.

## Implementation impact (flagged, not implemented in this brief)

Two new top-level routes:
- `frontend/lib/screens/discovery_screen.dart` — "What's around me?"
- `frontend/lib/screens/trip_planner_screen.dart` — "Plan a road trip" canvas

Supporting widgets:
- `trip_canvas_timeline.dart` — day strip
- `trip_canvas_map.dart` — pinned/suggested/wing-it rendering
- `trip_canvas_nl_input.dart` — NL textbox
- `lodging_card.dart` — find + deep-link
- `pin_promotion_sheet.dart` — promote a suggested stop to anchor

Backend:
- `backend/app/services/trip_planner.py` — orchestrates engine calls
  for the planning surfaces; emits draft trips
- `backend/app/services/nl_parser.py` — LLM call wrapper; emits
  structured canvas operations
- `backend/app/database.py` — `Trip` document with the schema above
- `backend/app/main.py` — endpoints:
  - `POST /trips` — create
  - `GET /trips` — list
  - `GET /trips/{id}` — read
  - `PUT /trips/{id}` — update (full canvas state)
  - `POST /trips/{id}/nl` — submit NL textbox content, get back ops
  - `POST /recommendations/planning_local` — engine call with new intent
  - `POST /recommendations/planning_long` — engine call with canvas context
- `backend/app/services/mapbox_search.py` — extend category fan-out to
  include lodging categories
- New: affiliate URL templating module for lodging deep-links

Profile additions (`UserProfile`):
- `bookmarked_pois: list[str]` (POI ids saved from "What's around me?")
- `default_daily_drive_cap_hours: int = 6`

## Verification (when this brief is "done")

Signed off when:
- The two-product split is the right shape (local discovery vs road
  trip planning as distinct surfaces)
- The canvas + NL textbox hybrid is the right interaction model for
  long trips
- The four pin types are exhaustive enough
- The wing-it semantics (pre-trip silent, in-nav ramped) match intent
- The lodging v1 (deep-link) vs v3 (booking API) split is acceptable
- The v1 non-goals are the right things to cut

After signoff:
- This brief gets committed to `docs/trip-planning-brief.md`
- A code-focused implementation plan derives from this brief
- Nothing in the codebase changes until that plan is approved
