# Mapbox Documentation Quick Index

**Purpose**: Ultra-compact index (1.5K tokens) to find the right doc instantly.

## Task → Doc Mapping

| What I Need | Read This | Size |
|-------------|-----------|------|
| **Setup & Init** |
| Install Navigation SDK | `installation-setup.md` | 5K |
| Initialize MapboxNavigation | `initialization.md` | 6K |
| Configure tokens | `reference/token-scopes.md` | 6K |
| **Core Navigation** |
| Display route on map | `route-line.md` | 6K |
| Auto-follow camera | `navigation-camera.md` | 7K |
| Voice guidance | `voice-instructions.md` | 7K |
| Turn arrows/text | `maneuver-instructions.md` | 6K |
| Show ETA/distance | `trip-progress.md` | 5K |
| **Location & Routing** |
| Show user location | `location-component.md` | 6K |
| Request route | `apis/directions-api.md` | 5K |
| Handle off-route | `rerouting.md` | 6K |
| **Advanced** |
| Speed limit | `speed-limit.md` | 5K |
| Offline maps | `offline-navigation.md` | 6K |
| Background nav | `foreground-service.md` | 6K |
| Multiple stops | `waypoints.md` | 7K |
| Highlight building | `building-highlights.md` | 5K |
| **Debugging** |
| Fix errors | `troubleshooting.md` | 7K |

## Common Workflows

**New Navigation App** (3 files, 16K):
1. installation-setup.md
2. initialization.md
3. route-line.md

**Add Audio** (1 file, 7K):
- voice-instructions.md

**Fix Build Error** (1-2 files, 7-13K):
1. troubleshooting.md
2. reference/token-scopes.md (if auth error)

**Multiple Stops** (1 file, 7K):
- waypoints.md

## Grep Shortcuts

```bash
# Find topic across all docs
grep -r "TOPIC" docs/mapbox/navigation/

# Find code example
grep -A 10 "fun " docs/mapbox/navigation/FILE.md

# Find error solution
grep -i "error name" docs/mapbox/troubleshooting.md
```

## Token Budget

- **Minimum**: 10K (README + 1 doc)
- **Typical**: 15K (README + 2 docs)
- **Maximum**: 25K (README + 3 docs)

**Never exceed 25K tokens for a single task.**
