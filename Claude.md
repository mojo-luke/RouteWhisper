# CLAUDE.md

RouteWhisper is a Flutter app with native Android (Kotlin) using the Mapbox Navigation SDK. iOS is planned but not yet built. Backend is Python FastAPI.

## Architecture

```
Flutter (lib/services/, lib/widgets/)
  - business logic, Provider state, non-nav UI
        ⇅  method channel
Native Android (MapActivity.kt)
  - Mapbox NavigationView during active turn-by-turn
        ⇅  method channel
Flutter overlays (TransparentFlutterActivity)
  - modals/sheets that appear over MapActivity
```

A shared `FlutterEngine` is created in `RouteWhisperApplication` and reused by `MainActivity`, `MapActivity`, and `TransparentFlutterActivity` so Provider state survives across activity boundaries.

**Layering rule:** business logic and calculations live in Flutter (`WaypointManager`, `NavigationController`). Native code displays results and forwards raw events. Method channels carry raw values up and formatted strings down. iOS port depends on this split.

## Key files

- `frontend/lib/services/navigation_service.dart` — Flutter↔Android bridge
- `frontend/lib/services/navigation_controller.dart` — navigation state machine
- `frontend/lib/services/waypoint_manager.dart` — waypoint state, arrival/departure, progress
- `frontend/lib/widgets/poi_dashboard.dart` — POI discovery UI (used both pre-nav and during nav)
- `frontend/android/.../MapActivity.kt` — native Mapbox navigation
- `frontend/android/.../RouteWhisperApplication.kt` — shared FlutterEngine setup
- `backend/app/main.py` — FastAPI POI / route endpoints

## Rules that have caused real bugs when broken

1. **Don't leave MapActivity during active navigation.** Use overlays (`showModalBottomSheet`, `TransparentFlutterActivity`), not new activities. Past break: launching a new activity killed the nav session.
2. **No calculation logic in native.** Send raw values to Flutter, compute, send formatted strings back.
3. **5-second undo SnackBar on destructive/state-changing actions** (waypoint add/remove/skip).
4. **Read `docs/mapbox/QUICK_INDEX.md` before touching a Mapbox feature.** The local Mapbox library is 21 files — start with the index, read 1-2 specific docs, don't guess at API.

See `frontend/UX.md` for full UX rationale and code patterns.

## Tests

- Dart integration: `frontend/integration_test/*.dart` → `flutter test integration_test/<name>.dart`
- Android unit: `frontend/android/app/src/test/kotlin/` → `cd frontend/android && ./gradlew test`
- Backend: `backend/tests/` → `pytest`

## Build & run

```bash
# Backend
cd backend && docker-compose up -d            # see backend/DOCKER_SETUP.md

# Frontend
cd frontend && flutter pub get
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Process notes

- **Status source:** `Development-Roadmap.md` is the single source for what's done. The old Step-N numbering became misleading after the product reframe around the companion — work now ships by feature surface (per-POI narration, drive monologue, trip CRUD, canvas, etc.) and the roadmap is organized accordingly. When in doubt, trust git over older docs.
- **Commits:** conventional format (`feat(Step N): ...` for legacy work, `feat(monologue): Slice X — ...` for the monologue v1 stack, also `fix:`, `docs:`, `research:`), one feature per commit.
- **Headline feature: shipped.** Both per-POI Wikipedia narration *and* the authored drive monologue (v1, slices A–F) run on the device. The app's name is "RouteWhisper" — narration is the product thesis, and as of 2026-05-16 the product thesis is load-bearing in code. See `docs/companion-monologue-v1-plan.md` for the architecture and `docs/companion-monologue-memo.md` for the research that informed it.
