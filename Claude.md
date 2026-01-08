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
- **All backend (Android/Kotlin) code must have unit tests**
- Write tests that verify real user flows for integration tests
- Backend unit tests go in `frontend/android/app/src/test/kotlin/` directory
- Integration tests go in `frontend/integration_test/` directory
- Test files follow pattern: `{feature_name}_test.dart` or `{ClassName}Test.kt`
- Use JUnit, MockK, and Robolectric for Android unit tests

### 3. Clean Git Commits
- **Commit messages must reference roadmap steps**: `feat(Step 2.5): Add native Mapbox navigation activity`
- One feature per commit
- Commits should match features in `documentation/Development-Roadmap.md`
- Use conventional commit format: `feat`, `fix`, `refactor`, `test`, `docs`

### 4. Incremental Development
- Build navigation foundation FIRST
- Add features one at a time AFTER navigation works
- Don't mix unrelated features in same commit

### 5. Check Mapbox Documentation FIRST (MANDATORY)
- **ALWAYS check `docs/mapbox/` before implementing ANY Mapbox feature**
- **During planning phase**: Read QUICK_INDEX.md to find relevant docs
- **Before coding**: Read the specific doc for that feature
- **Never build custom solutions** without first checking if Mapbox provides it
- **Token budget**: 6.5-15K tokens per task (read 1-2 docs max)

#### Documentation Workflow (REQUIRED):

**Step 1: Find the Right Doc** (1.5K tokens)
```bash
# Always start here
Read: docs/mapbox/QUICK_INDEX.md
```

**Step 2: Read Specific Doc** (5-7K tokens)
```bash
# Example: Adding voice instructions
Read: docs/mapbox/navigation/voice-instructions.md
```

**Step 3: Implement Using Mapbox Components**
- Use the official SDK components from the doc
- Follow the code examples provided
- Don't reinvent features that exist

#### Quick Reference:
- **Setup/Init**: Read `installation-setup.md` or `initialization.md`
- **Navigation UI**: Read `route-line.md`, `navigation-camera.md`, `voice-instructions.md`
- **Errors**: Read `troubleshooting.md` first, then `token-scopes.md` if auth issue
- **New feature**: Read `QUICK_INDEX.md` → find relevant doc → read it

**❌ NEVER**:
- Implement a feature without checking docs first
- Read all 21 docs at once (150K tokens wasted)
- Build custom UI when Mapbox provides it
- Guess at API usage without reading docs

**✅ ALWAYS**:
- Read QUICK_INDEX.md to find relevant doc (1.5K tokens)
- Read that specific doc (5-7K tokens)
- Use Mapbox's official components from the doc
- Total: 6.5-8.5K tokens per feature

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
├── docs/
│   └── mapbox/                           # Local Mapbox documentation (CHECK FIRST!)
│       ├── QUICK_INDEX.md                # Task → Doc mapping (START HERE)
│       ├── USAGE_GUIDE.md                # Token-efficient usage guide
│       ├── README.md                     # Full documentation overview
│       ├── navigation/                   # 16 navigation docs
│       ├── maps/                         # 3 maps docs
│       ├── search/                       # 1 search doc
│       ├── apis/                         # 1 API doc
│       ├── reference/                    # 1 reference doc
│       └── troubleshooting.md            # Common issues
├── documentation/
│   └── Development-Roadmap.md            # Source of truth for features
└── CLAUDE.md                             # This file
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
1. **Check Mapbox docs** → Read `docs/mapbox/QUICK_INDEX.md` to find relevant doc
2. **Read specific doc** → Read the doc for your feature (voice, camera, etc.)
3. Read relevant section in `documentation/Development-Roadmap.md`
4. Check if integration test exists for this feature
5. Understand the current navigation state

### Making Changes
1. **Plan** → Identify Mapbox components from docs (don't build custom)
2. **Code** → Implement feature using official Mapbox SDK components
3. **Unit Test** → Write unit tests for backend code in `frontend/android/app/src/test/kotlin/`
4. **Integration Test** → Write integration test that verifies user flow
5. **Verify** → Build, install, run tests: `./gradlew test` for unit tests, `flutter test integration_test/{feature}_test.dart` for integration
6. **Commit** → Use roadmap-aligned commit message
7. **Update** → Mark step as complete in roadmap if done

### Testing Commands
```bash
# Run Android unit tests
cd android && ./gradlew test

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
- ❌ **Implement Mapbox features without reading docs first** (CRITICAL)
- ❌ Read all 21 docs at once (150K tokens wasted)
- ❌ Build custom navigation UI in Flutter
- ❌ Build custom solutions when Mapbox provides them
- ❌ Write backend code without unit tests
- ❌ Create features without integration tests
- ❌ Make commits without roadmap reference
- ❌ Mix multiple features in one commit
- ❌ Skip testing on real device/emulator

## Questions to Ask Before Starting Work
1. **Have I checked `docs/mapbox/QUICK_INDEX.md` for this feature?** (MANDATORY)
2. **Have I read the specific Mapbox doc for this feature?** (MANDATORY)
3. Does this use Mapbox's official SDK components (not custom)?
4. Have I written unit tests for backend code?
5. Can I write an integration test for this?
6. Which roadmap step does this implement?
7. Is navigation foundation working first?

---

## Documentation Quick Reference

**Adding voice instructions?**
```bash
1. Read: docs/mapbox/QUICK_INDEX.md (find "Voice guidance")
2. Read: docs/mapbox/navigation/voice-instructions.md
3. Use: MapboxSpeechApi + MapboxVoiceInstructionsPlayer
```

**Fixing build errors?**
```bash
1. Read: docs/mapbox/troubleshooting.md
2. If 401: Read docs/mapbox/reference/token-scopes.md
```

**Any Mapbox feature?**
```bash
1. Read: docs/mapbox/QUICK_INDEX.md (1.5K tokens)
2. Find your task in the table
3. Read that specific doc (5-7K tokens)
4. Total: 6.5-8.5K tokens (94% savings vs reading all docs)
```

---

**Last Updated:** January 7, 2026
**Current Commit:** db48d90 (clean slate after architecture reset)
**Documentation Library**: 21 docs ready in `docs/mapbox/`
