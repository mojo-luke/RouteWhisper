# Mapbox Access Tokens Reference

## Token Types

### Public Tokens (pk.*)
- Contain **public scopes only**
- Safe to expose in client-side code
- Used in mobile apps and web applications
- Visible in browser DevTools and APK files

### Secret Tokens (sk.*)
- Include **secret scopes** for sensitive operations
- Must be kept server-side only
- **Never commit to version control**
- **Never embed in mobile apps**
- Used for SDK downloads and API management

### Temporary Tokens (tk.*)
- Support expiration up to 1 hour
- Don't appear on Access Tokens page
- Created programmatically via Tokens API

## Public Scopes

Safe for client-side use (read-only operations):

| Scope | Purpose | Usage |
|-------|---------|-------|
| `styles:read` | Initialize map styles in applications | MapView initialization |
| `styles:tiles` | Retrieve static maps or raster tiles | Static map images |
| `fonts:read` | Generate and retrieve font glyphs | Map text rendering |
| `datasets:read` | Access dataset information | Reading uploaded datasets |
| `vision:read` | Access Vision SDK features | AR navigation features |

## Secret Scopes

**Server-side only** - never expose these:

### Upload & Tileset Management
- `uploads:write` – Upload tilesets
- `uploads:read` – Read upload status
- `uploads:list` – List all uploads
- `tilesets:read` – Access tileset information
- `tilesets:write` – Modify tilesets
- `tilesets:list` – List all tilesets

### Style Management
- `styles:write` – Create and modify styles
- `styles:list` – List all styles
- `styles:protect` – Protect styles from deletion
- `styles:download` – Download style JSON

### Map & Data Operations
- `map:read` – Read map data
- `map:write` – Write map data
- `datasets:write` – Create and update datasets

### Token Management
- `tokens:read` – Read token information
- `tokens:write` – Create and revoke tokens programmatically

### Account Management
- `user:read` – Read account information
- `user:write` – Modify account settings

### Downloads
- `downloads:read` – **Required for SDK downloads from Maven** (most common secret scope)

## Token Security Best Practices

### 1. Principle of Least Privilege
**Key rule**: "Do not grant more scopes than necessary to each token."

Create separate tokens for:
- Mobile app (public token with styles:read, fonts:read)
- SDK downloads (secret token with downloads:read only)
- CI/CD pipeline (secret token with required scopes)
- Style editing (secret token with styles:write)

### 2. Token Rotation
- Regularly rotate tokens, especially if compromised
- Update all applications when rotating tokens
- Delete old tokens after rotation

### 3. Environment Separation
- Use different tokens for development, staging, and production
- Limit scope of development tokens
- Monitor production token usage

### 4. Storage Guidelines

**Public tokens**:
- Android: `res/values/developer-config.xml`
- iOS: Info.plist
- Web: Environment variables (still client-visible)

**Secret tokens**:
- Local: `~/.gradle/gradle.properties` (not in repo)
- CI/CD: Encrypted environment variables
- Never commit to git (add to .gitignore)

## URL Restrictions

Add security layer by restricting tokens to specific domains.

### Supported Formats
- Domain only: `mapbox.com`
- With paths: `mapbox.com/help/getting-started/access-tokens`
- Subdomains: Automatically authorized (`api.mapbox.com` when `mapbox.com` allowed)
- Subpaths: Automatically authorized

### Limitations
URL restrictions:
- Require referer headers
- Don't work with Mapbox GL JS < 0.53.1
- Don't work with mobile SDKs (iOS/Android)
- May fail in privacy-blocking browsers

## Token Management

### Create Tokens
**Via Dashboard**:
1. Go to Account page: https://account.mapbox.com/
2. Navigate to Access Tokens section
3. Click "Create a token"
4. Select required scopes
5. Optionally add URL restrictions

**Via Tokens API**:
```bash
curl -X POST "https://api.mapbox.com/tokens/v2/YOUR_USERNAME?access_token=YOUR_SECRET_TOKEN" \
  -d "scopes[]=styles:read" \
  -d "scopes[]=fonts:read" \
  -d "note=My App Token"
```

### List Tokens
```bash
curl "https://api.mapbox.com/tokens/v2/YOUR_USERNAME?access_token=YOUR_SECRET_TOKEN"
```

### Delete Tokens
**Warning**: "Deleting a token is an action that cannot be reversed - token deletion is permanent."

```bash
curl -X DELETE "https://api.mapbox.com/tokens/v2/YOUR_USERNAME/TOKEN_ID?access_token=YOUR_SECRET_TOKEN"
```

## Common Token Configurations

### Android Navigation App
**Public token** (in app):
```xml
<string name="mapbox_access_token">pk.YOUR_TOKEN_HERE</string>
```
Scopes: `styles:read`, `fonts:read`

**Secret token** (in gradle.properties):
```properties
MAPBOX_DOWNLOADS_TOKEN=sk.YOUR_SECRET_TOKEN_HERE
```
Scopes: `downloads:read`

### Web Application
**Public token** (in JS):
```javascript
mapboxgl.accessToken = 'pk.YOUR_TOKEN_HERE';
```
Scopes: `styles:tiles`, `fonts:read`

### Server-side Tilesets
**Secret token** (environment variable):
```bash
export MAPBOX_ACCESS_TOKEN=sk.YOUR_SECRET_TOKEN_HERE
```
Scopes: `uploads:write`, `tilesets:write`

## Troubleshooting

### 401 Unauthorized
- Verify token has required scope
- Check token hasn't been deleted
- Ensure using correct token type (secret vs public)
- For Maven: Check `MAPBOX_DOWNLOADS_TOKEN` in gradle.properties

### 403 Forbidden
- Token valid but lacks required scope
- Add necessary scope to token
- May need to create new token with broader permissions

### Token Not Working in Mobile App
- Ensure using public token (pk.*), not secret
- Verify token copied correctly (no extra spaces)
- Check token hasn't expired (temporary tokens)

## Documentation
- Tokens API Reference: https://docs.mapbox.com/api/accounts/tokens/
- Account Management: https://docs.mapbox.com/accounts/
- Security Best Practices: https://docs.mapbox.com/accounts/guides/security/
