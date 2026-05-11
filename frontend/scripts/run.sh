#!/usr/bin/env bash
# Launch the Flutter app with Supabase + Google config from .env.local.
#
# .env.local lives next to pubspec.yaml and is gitignored. Copy
# .env.local.example, fill in your values, then `./scripts/run.sh`.
#
# Any extra args pass through to `flutter run` — e.g.:
#   ./scripts/run.sh -d emulator-5554
#   ./scripts/run.sh --release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$FRONTEND_DIR/.env.local"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing $ENV_FILE"
  echo "   Copy .env.local.example and fill in your values."
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

: "${SUPABASE_URL:?SUPABASE_URL not set in .env.local}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY not set in .env.local}"
: "${GOOGLE_WEB_CLIENT_ID:?GOOGLE_WEB_CLIENT_ID not set in .env.local}"

cd "$FRONTEND_DIR"
exec flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
  "$@"
