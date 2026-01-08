# Documentation Usage Guide

> **Problem**: Reading all 21 documentation files would consume ~150K tokens per conversation.
> **Solution**: Use this index to read ONLY the specific docs you need.

## Quick Decision Tree

### 1. Before Starting Any Task

**Read this first** (5K tokens):
```
docs/mapbox/README.md
```

This gives you the full overview and helps decide which specific doc to read next.

### 2. For Specific Tasks

Use this table to find the RIGHT doc to read:

| Task | Read This File | Tokens |
|------|---------------|--------|
| **Initial SDK Setup** | `installation-setup.md` | ~5K |
| **MapboxNavigation init** | `initialization.md` | ~6K |
| **Display map with route** | `route-line.md` | ~6K |
| **Camera following user** | `navigation-camera.md` | ~7K |
| **Audio directions** | `voice-instructions.md` | ~7K |
| **Turn arrows/text** | `maneuver-instructions.md` | ~6K |
| **Show ETA/distance** | `trip-progress.md` | ~5K |
| **Show user location dot** | `location-component.md` | ~6K |
| **Handle off-route** | `rerouting.md` | ~6K |
| **Show speed limit** | `speed-limit.md` | ~5K |
| **Download offline maps** | `offline-navigation.md` | ~6K |
| **Background navigation** | `foreground-service.md` | ~6K |
| **Highlight destination** | `building-highlights.md` | ~5K |
| **Multiple stops** | `waypoints.md` | ~7K |
| **Request a route** | `apis/directions-api.md` | ~5K |
| **Fix build errors** | `troubleshooting.md` | ~7K |
| **Token configuration** | `reference/token-scopes.md` | ~6K |

### 3. Search Before Reading

**Use Grep to find specific topics**:

```bash
# Example: Find all mentions of "observer" pattern
grep -r "Observer" docs/mapbox/navigation/ --include="*.md"

# Example: Find voice instruction examples
grep -A 10 "voiceInstructions" docs/mapbox/navigation/voice-instructions.md

# Example: Find error solutions
grep -i "error" docs/mapbox/troubleshooting.md
```

## Token-Efficient Workflow

### Starting a New Feature

1. **Quick scan** (5K tokens):
   ```
   Read: docs/mapbox/README.md
   ```
   Look for feature in "Quick Navigation" section

2. **Deep dive** (5-7K tokens):
   ```
   Read: The ONE specific doc for that feature
   ```
   Only read the file you need

3. **Cross-reference** (optional, 5K tokens):
   ```
   Read: Related docs linked at bottom of file
   ```
   Only if you need deeper integration

**Total: 10-15K tokens vs 150K tokens**

### Debugging an Issue

1. **Check troubleshooting first** (7K tokens):
   ```
   Read: docs/mapbox/troubleshooting.md
   ```
   Search for your specific error

2. **If not found, read feature doc** (5-7K tokens):
   ```
   Read: Specific feature doc (e.g., route-line.md)
   ```
   Look for "Common Issues" section

3. **Check token scopes if 401/403** (6K tokens):
   ```
   Read: reference/token-scopes.md
   ```

**Total: 7-13K tokens**

## What NOT To Do

❌ **Don't read all navigation docs at once**
- 15 files × 6K tokens = 90K tokens wasted

❌ **Don't read docs for features you're not using**
- Building waypoint navigation? Skip speed-limit.md

❌ **Don't re-read docs you already understand**
- If you know how to init MapboxNavigation, skip initialization.md next time

## Smart Reading Strategies

### Strategy 1: Index Scanning

**Step 1**: Always read README.md first (5K tokens)
**Step 2**: Identify 1-2 relevant docs
**Step 3**: Read ONLY those docs (10-14K tokens)

**Total**: 15-19K tokens instead of 150K

### Strategy 2: Grep First, Read Second

```bash
# Find which file has info about "lane guidance"
grep -l "lane guidance" docs/mapbox/navigation/*.md

# Output: maneuver-instructions.md
# Now read ONLY that file
```

### Strategy 3: Section Reading

Many docs have clear sections. Use `Read` tool with line ranges:

```kotlin
// Instead of reading entire file (6K tokens)
Read: docs/mapbox/navigation/voice-instructions.md (lines 1-100)

// Only read "Basic Implementation" section (1.5K tokens)
```

## Documentation Size Reference

```
Small docs (3-5K tokens):
- installation-setup.md
- speed-limit.md
- building-highlights.md
- directions-api.md

Medium docs (5-7K tokens):
- initialization.md
- route-line.md
- voice-instructions.md
- maneuver-instructions.md
- trip-progress.md
- location-component.md
- rerouting.md
- offline-navigation.md
- foreground-service.md
- waypoints.md
- troubleshooting.md
- token-scopes.md

Large docs (7-9K tokens):
- navigation-camera.md
- README.md

Total library: ~110K tokens
```

## Practical Examples

### Example 1: "Add voice instructions"

**Bad approach** (150K tokens):
```
1. Read all 21 files
2. Find voice instructions info
3. Implement
```

**Good approach** (12K tokens):
```
1. Read README.md → find "Voice Instructions" link (5K)
2. Read voice-instructions.md → get implementation (7K)
3. Done!
```

**Savings: 138K tokens (92% reduction)**

### Example 2: "Fix 401 error"

**Bad approach** (150K tokens):
```
1. Read all navigation docs
2. Read all reference docs
3. Read troubleshooting
```

**Good approach** (13K tokens):
```
1. Read troubleshooting.md → find "401 Unauthorized" (7K)
2. Read token-scopes.md → understand token types (6K)
3. Done!
```

**Savings: 137K tokens (91% reduction)**

### Example 3: "Build navigation from scratch"

**Bad approach** (150K tokens):
```
1. Read everything
```

**Good approach** (35K tokens):
```
1. Read README.md (5K)
2. Read installation-setup.md (5K)
3. Read initialization.md (6K)
4. Read route-line.md (6K)
5. Read navigation-camera.md (7K)
6. Read voice-instructions.md (6K)

Skip: speed-limit, offline, building-highlights, waypoints, etc.
```

**Savings: 115K tokens (77% reduction)**

## Quick Reference: "What Do I Need?"

### Minimum Viable Navigation (Read 3 files, 16K tokens)
1. installation-setup.md
2. initialization.md
3. directions-api.md

### Basic Turn-by-Turn (Read 5 files, 29K tokens)
1. installation-setup.md
2. initialization.md
3. route-line.md
4. navigation-camera.md
5. voice-instructions.md

### Production-Ready Navigation (Read 8 files, 48K tokens)
1. installation-setup.md
2. initialization.md
3. route-line.md
4. navigation-camera.md
5. voice-instructions.md
6. maneuver-instructions.md
7. rerouting.md
8. troubleshooting.md

### Feature-Specific Additions (5-7K each)
- Trip progress bar? + trip-progress.md
- Multiple stops? + waypoints.md
- Offline mode? + offline-navigation.md
- Background nav? + foreground-service.md

## Context Management Rules

### For Claude Code Assistant

1. **Rule #1: Always start with README.md**
   - It's the index (5K tokens)
   - Points to specific docs

2. **Rule #2: Read maximum 3 docs per task**
   - Most tasks need 1-2 docs
   - Complex tasks need 3 max
   - Total: 15-21K tokens

3. **Rule #3: Use Grep for searches**
   - Finding specific topics: use grep
   - Don't read entire file to find one thing

4. **Rule #4: Trust the index**
   - README has cross-references
   - Follow the links, don't guess

5. **Rule #5: Bookmark what you read**
   - If you read initialization.md in this session
   - Don't re-read it unless user asks

## Cost Comparison

**Reading everything**:
- Input: 150K tokens
- Cost: ~$0.45 per request (with Sonnet)
- 10 requests: $4.50

**Reading smartly** (3 docs per task):
- Input: 15-20K tokens
- Cost: ~$0.06 per request
- 10 requests: $0.60

**Savings: $3.90 (87% cost reduction)**

## Guidelines for Future Updates

When adding new docs:

1. **Update this file** with new doc in decision table
2. **Add to README.md** in appropriate section
3. **Estimate tokens** (wc -w file.md / 0.75)
4. **Create cross-references** to related docs

## Summary

✅ **DO**:
- Read README.md first (5K)
- Identify 1-2 relevant docs
- Use grep to find specific topics
- Read only what you need

❌ **DON'T**:
- Read all 21 files at once
- Read docs for features you're not implementing
- Re-read docs you already know

**Target**: 15-25K tokens per task vs 150K tokens
**Savings**: 83-90% token reduction
