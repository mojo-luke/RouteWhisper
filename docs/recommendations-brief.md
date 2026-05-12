# Product brief: Smart stop suggestions

## Context

The recommendation surface (Step 7) is wired end-to-end but the *substance*
is shallow: scoring weights are pulled from intuition, there's no trip-type
awareness, no quality bar, no learning, no real model for when silence is
the right answer. After observing the system surface zero suggestions despite
a valid route + matching categories, the user flagged: "the suggestions need
to be very thought out and planned."

This brief defines what *good* looks like before another scoring weight gets
touched. It does **not** spec implementation — it sets the framework that
implementation and calibration happen inside. No weights are committed here;
weights are a calibration problem the system earns through real-trip data.

Sources incorporated:
- `Overview.md` — trip-scale tiers, time-budget modes, quality bar starters,
  narration spacing rules
- `Development-Roadmap.md` Step 7 — interest profiling, stop categorization
- `frontend/UX.md` — response-time rules (100ms tap reaction)
- Conversation today — role as polished concierge; engine must serve both
  pre-trip planning and in-nav; engine must be LLM-ready as a first-class
  concern

## One engine, four input contexts

A single scoring engine produces ranked stop candidates. It is reached from
four different surfaces, each with its own *intent context* but consuming
the same engine and the same quality / personalization rules.

| # | Surface | Invocation | Failure-mode posture |
|---|---------|------------|----------------------|
| 1 | **Pre-trip planning** | User explicitly asks before driving ("plan me a 6-hr trip with breakfast + scenic stops, arrive by 4pm") | Errs toward offering. User is in exploratory mode. |
| 2 | **In-nav auto-poll** | Background poll on a timer during navigation | Errs toward silence. Driver is task-focused. |
| 3 | **In-nav manual** | Driver taps "Suggest a stop" FAB | Always offers a best candidate, even on local trips. |
| 4 | **(Future) LLM-parsed voice** | "Find me a gas station off the highway" → parsed intent → engine | Same as the surface it imitates; LLM only translates language to intent. |

**Engine interface.** Every surface calls the same engine with a structured
intent. Designing this contract now keeps the LLM layer drop-in later.

```
EngineRequest = {
  context: {                       # who/where/when
    user_id,
    route_polyline,
    current_location?,             # null for pre-trip planning
    minutes_into_trip?,
    minutes_remaining?,
    hours_since_last_stop?,
    fuel_state?,                   # placeholder; no telematics yet
    time_of_day,
    trip_scale: local|regional|long,
    time_budget_mode: hurry|moderate|discovery,
  },
  intent: {                        # what
    invocation: auto|manual|planning|voice,
    desired_categories?: [...],    # explicit, may come from voice/LLM
    constraints?: {                # parseable from natural language
      max_detour_miles?,
      max_stop_minutes?,
      must_be_on_highway?,
      ...
    },
    natural_language_query?: str,  # raw user text if invocation==voice
  },
}

EngineResponse = {
  suggestions: [
    { poi, score, reason, surface_hints: {...} }
  ],
  silence_reason?: str             # null if at least one suggestion fires
}
```

The LLM layer's only job, when it arrives, is to translate
`"find me a gas station off the highway, soon"` into the `intent` shape
above. The engine itself is unchanged.

## Role

**Polished travel concierge.** Helpful, neutral, comprehensive. Tone
adapts subtly per surface:

- **Planning** — comprehensive, options-rich. ("Here are 4 strong stop
  candidates for your trip.")
- **In-nav auto** — minimal, confident, easy to dismiss. ("Lunch stop ahead:
  Bento Box, 12 min, on your route.")
- **In-nav manual** — present the single best pick. ("Closest strong fit:
  Bento Box.")
- **Voice (future)** — concise, answers the asked question directly.

Not a casual friend (tone too loose for ranked output users must trust);
not a pragmatic copilot only (under-uses the data we collect on long trips).

## The four core dimensions

Every scored suggestion is the joint output of all four. Any dimension
ignored is a way the system looks stupid.

### 1. Trip scale (auto-detected at trip start; route distance, not straight-line)

| Scale | Distance | In-nav auto | In-nav manual | Planning |
|-------|----------|-------------|---------------|----------|
| Local | <20 mi | Silent unless practical need flagged. **No automatic discovery.** | Best-pick along route, honoring quality bar | N/A — user wouldn't plan a local trip |
| Regional | 20–100 mi | 2–3 per trip max, balanced practical/preferred | Best pick on demand | Up to 5 options across trip |
| Long | 100+ mi | 3–5 per trip, lean into discovery + practical | Best pick on demand | Up to 10 options, surfaceable as itinerary |

**Crucially: local-trip users can ALWAYS invoke discovery manually** via the
"Suggest a stop" FAB or the planning surface. The "silent on local" rule
applies *only* to the auto-poll surface.

### 2. Time-budget mode (per-profile, per-trip override)

| Mode | Rating floor | Stop length | Detour cap | Categories surfaced |
|------|--------------|-------------|------------|---------------------|
| In a hurry | 4.5★ | ≤15 min | ≤0.5 mi | Practical only (gas / restroom) |
| Moderate (default) | 4.0★ | ≤30 min | ≤2 mi | Practical + preferred |
| Discovery | 3.5★ | ≤90 min | ≤5 mi | All; surface novel categories |

These thresholds are **calibration starting points**, not constants. The
engine reads them from the user's profile (already wired) and any per-trip
override the planning surface produces.

### 3. User-state context (per moment of evaluation)

- **Hours-since-last-stop** — > 2.5 hr biases toward food / restroom / coffee
  regardless of stated category prefs. ("You've been driving for a while.")
- **Time of day** — anchored defaults (breakfast 7–10, lunch 11–13, dinner
  17–19) blended with user's historical pattern from `/time-patterns`.
- **Remaining drive time** — never auto-suggest in last 15 min. Manual
  surface can still respond.
- **Fuel state** — placeholder. Reserve the slot.

### 4. Quality signal (independent of personalization)

- Rating floor per time-budget mode (above).
- Minimum review count: **≥ 25** to weed out fake/one-review listings.
- Chain repetition guard: don't surface a chain the user declined this trip
  OR over the last 5 trips. Suppresses the "Starbucks, Starbucks, Starbucks"
  failure mode.
- Multi-source confidence (future): prefer POIs that appear across Mapbox +
  Foursquare / Yelp once we add them.

## What "good" looks like (one example per surface)

1. **Planning surface, user types "6-hour drive to Tahoe, scenic + breakfast, arrive 4pm":**
   Engine returns: a breakfast stop in Davis (7am, 4.6★), a scenic overlook
   on Hwy 50 (10am, 4.7★), a coffee refill at Pollock Pines (12pm, 4.4★).
   Total trip including stops fits the arrival constraint.

2. **In-nav auto, 2.5 hr into a 4-hr road trip, 11:45 AM, restaurants preferred:**
   Surfaces a 4.6★ taco place 12 min ahead, 0.7 mi off-route. Reason:
   "Lunchtime, no stop in 2 hours, on your route." Then silent for the
   next leg.

3. **In-nav manual, Friday rush hour, 80 mi to grandma's, gas at ¼ tank, no prefs set:**
   Driver taps "Suggest a stop." Engine returns the nearest reputable gas
   station that's open. Reason: "Gas tank low, top station 4 min ahead."
   The auto-poll would have stayed silent (local scale, hurry-ish mode);
   manual invocation gets the answer regardless.

4. **(Future) Voice intent, "I want a quick gas stop right off the highway":**
   LLM parses intent → `{categories: [gas_station], constraints: {max_detour_miles: 0.3, must_be_on_route: true}}`.
   Engine returns the most efficient pick — not necessarily the nearest,
   but the one that adds the least overall trip time. Reason: "Costs you
   3 minutes total."

## What "bad" looks like (anti-examples)

1. **Commuter drive, 15-min route, 5:45 PM.** Auto-poll surfaces "popular
   bakery" 8 min off-route. ❌ Wrong trip scale. Auto-poll on local trips
   never surfaces discovery. (Manual tap is still allowed.)

2. **Mid-route, 30 sec after merging onto a freeway interchange.**
   Auto-poll surfaces a card. ❌ Wrong moment. Defer until in-lane and
   stable ≥ 60 sec.

3. **User dismissed 3 coffee suggestions in a row.** System surfaces a 4th
   coffee place. ❌ Wrong learning. Suppress category for the rest of the
   trip after 2 dismissals.

4. **User asks via voice "find me coffee" and the engine returns a place
   30 minutes off-route with a 4.9★ rating.** ❌ Wrong intent
   interpretation. Voice requests carry implicit "soon and convenient"
   context unless the user says otherwise.

## Cold-start strategy

The product has *two* surfaces, which radically changes cold-start:

- **The planning surface is the cold-start.** A new user lands in the app,
  is invited to plan a trip, and in doing so tells us what they want.
  "Cold start" only refers to behavior when the user has *not* declared
  intent and has no history.

- **In-nav auto-poll, truly cold (no history, no prefs, no plan):**
  - **Trip 1**: silent on `local`. On `regional`/`long`: at most ONE
    practical-only auto-suggestion if criteria are met (fuel low, food
    overdue). No discovery.
  - **Trips 2–3**: weights shift as accept/dismiss decisions come in.
    Discovery enters only if the user opts into Discovery mode or sets
    preferred categories.
  - **Trips 4+**: full concierge per the four dimensions.

- **In-nav manual, even on trip 1:** always responds. Trip 1 manual taps
  use a conservative scoring profile (higher rating floor, tighter detour)
  to maximize first-impression quality.

- **Planning surface, even on trip 1:** always responds, with explicit
  copy ("These are starting suggestions; tell me more about what you're
  looking for and they'll get better"). Restraint isn't the right tone in
  exploratory mode.

Rationale: a confident but wrong auto-suggestion on trip 1 teaches the user
the system doesn't know them. But silence in the *planning* surface or
after a *manual* tap teaches them the system doesn't work at all.

## When silent (hard rules — auto-poll only)

The auto-poll surface never fires when ANY of:

- Trip scale `local` *and* no practical need flagged
- Time-budget `in a hurry` *and* candidate isn't practical
- Within 15 min of arrival
- Within 60 sec of a turn maneuver
- User has dismissed 2 suggestions this trip
- `recommendations_enabled` is false in profile

Manual, planning, and voice surfaces are **user-initiated** — they always
return their best candidate (even if it's mediocre), with the score and
reason giving the user the signal to accept or reject.

## Personalization model

Three signals, in order of weight:

1. **Explicit preferences and intent** — chip multi-select, planning-time
   declarations, voice queries. Strongest, most legible.
2. **Trip-level behavior** — accept/dismiss in current trip. Suppresses
   categories the user just declined.
3. **Cross-trip history** — persisted category counts, time-of-day patterns,
   repeat-place affinity. Weakest per-trip, compounds with use.

Explicit non-goals:
- Group / companion preferences
- Mood / vibe signals
- Weather-aware recommendations
- Collaborative filtering ("users like you also stopped at…")

## Calibration plan

Replace "the weights feel right" with measurement:

1. **Persist accept/dismiss decisions** to the user's history (currently
   only suppressed in-memory per trip). This is implicit signal.
2. **Optional end-of-trip recap**: "How were today's suggestions?" with a
   1–5 tap. Single prompt per trip, dismissible. Explicit signal.
3. **Map implicit signal to ratings** for analysis: accept→4, dismiss→2,
   no-action→3, post-trip explicit overrides all.
4. **Offline review at ~50 rated trips**: do high-scoring suggestions
   actually have higher ratings? If not, weights are wrong. Iterate.
5. **Production A/B once volume exists** — alternate scoring profiles
   between cohorts, compare accept-rate and rating-mean.

## How we'll know it's working

- Median accept-rate on auto-poll suggestions trends up over user lifetime
- Median 1–5 rating on suggested stops ≥ 4 after the calibration phase
- Time-between-dismissals lengthens as the system learns to suppress
- Zero "fired during a turn" incidents
- Pre-trip planning sessions result in at least one accepted suggestion
  the majority of the time

## What is NOT in scope

- TTS narration (Step 4 — separate brief required)
- Booking integration
- Vehicle telematics (real fuel level, etc.)
- Collaborative filtering
- The LLM's *natural-language parsing implementation* — but the engine
  interface above MUST be designed so an LLM layer can drop in without
  reworking scoring

## Open questions (revisit before / during implementation)

1. **Trip-scale detection** — route distance, not straight-line. Verify in
   implementation that we have the route distance available before this
   determination is needed.
2. **Local-trip auto-discovery on/off via setting** — should there be a
   toggle "occasionally surprise me even on short trips" for users who
   want a more delight-leaning default? Lean *yes*; design as off by
   default.
3. **End-of-trip rating UI** — single 1–5 stars, or per-suggestion stars,
   or just a thumbs-up/down? Resolve when the calibration phase starts.
4. **Multi-source POI ingestion** (Foursquare, Yelp) — prerequisite for
   the "multi-source confidence" quality signal. Cost? Rate limits? Worth
   pricing before committing.
5. **Voice-intent invocation UI** — how does the user initiate voice asks?
   A press-and-hold of the Suggest FAB? A dedicated mic button? Connected
   to whether we ship a voice answer (Step 4 narration) or just text.

## Implementation impact (flagged, not implemented in this brief)

The current implementation has none of the four dimensions wired correctly:

| Dimension | Current state | Gap |
|-----------|---------------|-----|
| Trip scale | Not detected | Need at trip start, persist for trip |
| Time-budget mode | Field exists, unused by scorer | Wire to thresholds |
| User-state context | hour-of-day match only | Add hours-since-last-stop, remaining-drive-time |
| Quality signal | No rating filter, no review count, no chain guard | All new |

Critical files that will change when implementation lands:
- `backend/app/services/stop_recommendations.py` — score function rewrite
  around the four dimensions
- `backend/app/main.py` — `/recommendations/stops` endpoint accepts the
  full `EngineRequest` shape (context + intent)
- `frontend/lib/services/recommendation_service.dart` — sends context for
  trip scale + budget mode; surfaces accept/dismiss to persistence
- New: backend trip-scale detection helper (likely
  `backend/app/utils/polyline.py`)
- New: planning-surface UI (Flutter, future)
- New: post-trip rating UI (Flutter, future)

## Verification (when this brief is "done")

This brief is signed off when the user agrees:
- The four dimensions are the right framing
- The "one engine, four surfaces" split is the right shape
- The hard "When silent" rules apply only to auto-poll (manual / planning /
  voice are user-initiated and always respond)
- Cold-start strategy handles the planning surface correctly
- The calibration plan is something we'll *actually* do, not a wish
- The LLM-readiness commitment (engine interface designed for it) is what
  the user meant by "develop with the LLM layer in mind"

After signoff:
- The brief gets committed to `docs/recommendations-brief.md` (proposed
  permanent home) so it's referenceable as design intent
- A separate, code-focused implementation plan derives from this brief
- Nothing in the codebase changes until that derived plan is approved
