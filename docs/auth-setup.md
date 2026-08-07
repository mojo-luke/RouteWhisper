# Auth setup checklist (Supabase + Google sign-in)

The code for sign-in, JWT verification, profile API, and preferences UI
is all wired up. To run it end-to-end you need to configure Supabase and
Google OAuth in the browser, then drop the resulting credentials into
local config. Steps below.

## 1. Supabase project

1. Sign in at <https://supabase.com> and create a new project.
2. Once it's ready, go to **Settings → API**. Copy:
   - **Project URL** (e.g. `https://xxxx.supabase.co`)
   - **anon public** API key
   - **JWT Secret** (this is a separate field, NOT the service role key)

## 2. Google Cloud OAuth

You need *two* OAuth client IDs: a **Web** client (used as the Supabase
provider's "client ID") and an **Android** client (validates the app).

1. Go to <https://console.cloud.google.com>, create a project (or reuse).
2. **APIs & Services → OAuth consent screen**: configure as External,
   add your email as a test user.
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - **Application type: Web application**
     - Name: "RouteWhisper Supabase"
     - Authorized redirect URIs: `https://<your-supabase-project>.supabase.co/auth/v1/callback`
     - Save the **Client ID** and **Client secret** — these go into Supabase.
   - **Application type: Android**
     - Package name: `com.routewhisper.route_whisper_app`
     - SHA-1 fingerprint: get it from your debug keystore:
       ```bash
       keytool -list -v -keystore ~/.android/debug.keystore \
         -alias androiddebugkey -storepass android -keypass android \
         | grep SHA1
       ```
     - You don't need a separate client ID/secret here — Android uses
       the Web client ID for the actual token exchange.

## 3. Wire Google → Supabase

1. Supabase dashboard → **Authentication → Providers → Google**: enable.
2. Paste the **Web client ID** and **Web client secret** you got above.
3. Save. Supabase will show the redirect URI it expects — confirm it
   matches what you set in Google Cloud.

## 4. Local config

### Backend (`backend/.env`)

Add these to the existing `.env` (created next to `docker-compose.yml`):

```env
SUPABASE_JWT_SECRET=<JWT secret from Supabase Settings → API>
MONGODB_URL=mongodb://mongo:27017   # already set if you've used Docker
MONGODB_DATABASE=routewhisper_content
```

Then rebuild the backend image so the new `pyjwt` dependency installs:

```bash
cd backend
docker-compose up --build -d
```

### Frontend (build-time `--dart-define`)

The Flutter build reads Supabase config from compile-time defines so
secrets stay out of source. Build/run with:

```bash
cd frontend
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public-key> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id-from-google-cloud>
```

For convenience, drop these into a script. Don't commit them.

## 5. End-to-end smoke test

1. `docker-compose up -d` (Postgres + Mongo + Redis + backend).
2. `flutter run --dart-define=...` against an emulator.
3. App launches → sign-in screen → tap "Continue with Google" → Google
   account chooser → land on RouteWhisper dashboard.
4. Tap the gear icon (top right) → preferences screen. Toggle a category,
   it should save without error.
5. From the dashboard, run a route end-to-end. Check backend logs for
   `📊 Stop persisted: <name> for user <uuid>` — that confirms the JWT
   verified, the user_id flowed through, and Mongo persisted.
6. `mongosh` smoke check:
   ```js
   use routewhisper_content
   db.waypoint_stop_history.find().limit(3)
   db.user_profiles.find()
   ```

## 6. Common gotchas

- **"GOOGLE_WEB_CLIENT_ID is not set"** at sign-in: you forgot to pass
  the dart-define. The app fails fast with this exact error.
- **Sign-in succeeds but backend returns 401**: `SUPABASE_JWT_SECRET`
  doesn't match the project the JWT came from, OR the audience claim
  isn't `authenticated`. Re-check the JWT secret in Supabase Settings → API.
- **`DEVELOPER_ERROR` from Google**: your debug keystore SHA-1 isn't
  registered with the Android OAuth client. Add it (you can have multiple
  SHA-1 fingerprints on one client — debug + release).
- **Sign-in screen flashes briefly on launch even when signed in**: the
  AuthGate uses the cached session for the first frame to avoid this; if
  you still see flicker, the cached session isn't restoring — check that
  `Supabase.initialize` is awaited in `main()` (it is, in the current code).

## Email/password sign-in

`SignInScreen` also has a plain email/password form (sign in or create an
account), calling `AuthService.signUpWithPassword` / `signInWithPassword` —
same `AuthGate` session path as Google, just a different front door. Needs
Supabase's **Email** provider enabled (Authentication → Providers → Email),
which is on by default for new projects.

If the project has **"Confirm email"** turned on (Authentication → Providers
→ Email → "Confirm email"), sign-up won't return a session immediately —
the response's `session` is null until confirmed.

**This app confirms via a 6-digit code, not the confirmation link.**
RouteWhisper is mobile-only with no web frontend and no deep-link URL
scheme registered, so the link's default redirect
(`http://localhost:3000/#access_token=...`) goes nowhere useful. Instead,
`SignInScreen` shows a "enter the code we emailed you" step that calls
`AuthService.verifySignupCode` (`auth.verifyOTP(type: OtpType.signup)`).

**Required dashboard step**: Supabase's default "Confirm signup" email
template only includes the link (`{{ .ConfirmationURL }}`), not the raw
code — you have to add it yourself:

1. Supabase dashboard → **Authentication → Email Templates → Confirm signup**.
2. Add `{{ .Token }}` somewhere in the template body (e.g. "Or enter this
   code in the app: `{{ .Token }}`").
3. Save. New signups will now receive the code; existing unconfirmed
   users need to hit "Resend code" in the app to get one under the
   updated template.

If you'd rather support both (tap-to-confirm on a future web presence,
code entry in the app today), keep `{{ .ConfirmationURL }}` in the
template too — they're independent, and either one confirms the account.

## What's deferred

- Apple sign-in (waits on iOS work).
- Magic-link sign-in.
- Refresh-token rotation handling beyond what supabase_flutter does for free.
- Linking an existing anonymous-device profile to a real account on first sign-in.
