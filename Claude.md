# Claude Instructions for RouteWhisper

## Project Overview
RouteWhisper is a Flutter navigation app with native Android integration using Mapbox Navigation SDK. The app provides turn-by-turn navigation with intelligent POI discovery and time budget management for road trips.

## Core Principles

### 1. Use Native SDK Components First
- **Always use Mapbox's official navigation UI components** (NavigationView, DropInUI)
- Don't build custom UI until basic native functionality works perfectly
- Leverage native Android features before creating Flutter alternatives

### 2. Test-Driven Development
- **Every feature must have integration tests before being considered complete**
- Write tests that verify real user flows, not just unit tests
- Tests should be in `frontend/integration_test/` directory
- Test files follow pattern: `{feature_name}_test.dart`

### 3. Clean Git Commits
- **Commit messages must reference roadmap steps**: `feat(Step 2.5): Add native Mapbox navigation activity`
- One feature per commit
- Commits should match features in `documentation/Development-Roadmap.md`
- Use conventional commit format: `feat`, `fix`, `refactor`, `test`, `docs`

### 4. Incremental Development
- Build navigation foundation FIRST
- Add features one at a time AFTER navigation works
- Don't mix unrelated features in same commit

## Project Structure

```
RouteWhisper/
├── frontend/
│   ├── android/
│   │   └── app/src/main/kotlin/com/routewhisper/route_whisper_app/
│   │       ├── MainActivity.kt           # Main Flutter activity
│   │       ├── MapActivity.kt            # Native Mapbox navigation (full-screen)
│   │       ├── navigation/               # Navigation logic
│   │       └── ui/                       # UI components (MapViewManager, etc.)
│   ├── lib/
│   │   ├── screens/                      # Flutter screens
│   │   ├── services/                     # Flutter business logic
│   │   └── widgets/                      # Reusable Flutter widgets
│   └── integration_test/                 # Integration tests (REQUIRED)
├── documentation/
│   └── Development-Roadmap.md            # Source of truth for features
└── Claude.md                             # This file
```

## Current Focus (January 2026)

**Step 2.5: Native Mapbox Navigation** - See `documentation/Development-Roadmap.md`

### Phase 1: Native Navigation (IN PROGRESS)
- [ ] Create/verify MapActivity uses Mapbox NavigationView
- [ ] Flutter method channel to launch MapActivity
- [ ] Write integration test for navigation flow
- [ ] Commit: `feat(Step 2.5): Add native Mapbox navigation`

### Phase 2: Feature Addition (AFTER Phase 1)
- POI discovery (salvaged from commit 9b95a3a)
- Budget tracking (salvaged from commit 9b95a3a)
- Waypoint management (salvaged from commit 9b95a3a)

## Working with This Codebase

### Before Making Changes
1. Read relevant section in `documentation/Development-Roadmap.md`
2. Check if integration test exists for this feature
3. Understand the current navigation state

### Making Changes
1. **Code** → Implement feature using native components
2. **Test** → Write integration test that verifies user flow
3. **Verify** → Build, install, run test: `flutter test integration_test/{feature}_test.dart`
4. **Commit** → Use roadmap-aligned commit message
5. **Update** → Mark step as complete in roadmap if done

### Testing Commands
```bash
# Build and install
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Run specific integration test
flutter test integration_test/navigation_test.dart

# Run all integration tests
flutter test integration_test/
```

### Key Files to Know
- `MainActivity.kt` - Entry point, method channels, launches MapActivity
- `MapActivity.kt` - Native full-screen navigation with Mapbox UI
- `NavigationService` (Flutter) - Bridge between Flutter and native
- `navigation_dashboard.dart` - Main Flutter UI

## Common Patterns

### Method Channel Communication
```kotlin
// Android side (MainActivity.kt)
methodChannel.invokeMethod("onNavigationStarted", null)

// Flutter side (NavigationService)
static final _channel = MethodChannel('routewhisper.com/navigation');
_channel.setMethodCallHandler(_handleMethodCall);
```

### Launching Native Navigation
```dart
// Flutter
await NavigationService.openMapView();

// Triggers in MainActivity.kt
startActivity(Intent(this, MapActivity::class.java))
```

## Don't Do This
- ❌ Build custom navigation UI in Flutter
- ❌ Create features without integration tests
- ❌ Make commits without roadmap reference
- ❌ Mix multiple features in one commit
- ❌ Skip testing on real device/emulator

## Questions to Ask Before Starting Work
1. Does this use Mapbox native components?
2. Can I write an integration test for this?
3. Which roadmap step does this implement?
4. Is navigation foundation working first?

---

**Last Updated:** January 5, 2026
**Current Commit:** db48d90 (clean slate after architecture reset)
