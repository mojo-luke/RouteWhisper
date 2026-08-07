#!/usr/bin/env python3
"""Create/delete a throwaway Supabase auth user for on-device testing.

The app's sign-in screen is Google-only, which is a real wall for manual or
scripted on-device verification (no way to script "log in as a real Google
account"). This script uses Supabase's Admin API (service_role key) to
create/delete a fixed-credential fixture user; the corresponding debug-only
"Sign in with test account" button in frontend/lib/screens/sign_in_screen.dart
(gated by kDebugMode) signs into it with a normal password grant — same
AuthGate/Supabase session code path as a real user, just a different front
door that only exists in debug builds.

TEST_EMAIL / TEST_PASSWORD here must match the constants in
frontend/lib/services/auth_service.dart exactly.

Usage:
    cd backend
    python scripts/manage_test_user.py create
    python scripts/manage_test_user.py delete
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import httpx
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

TEST_EMAIL = "routewhisper-test-fixture@example.com"
TEST_PASSWORD = "RW-test-fixture-2026!Zq9"

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
# Named SUPABASE_KEY in backend/.env (not SUPABASE_SERVICE_ROLE_KEY) —
# must hold the service_role/secret key, not the anon/public one. See
# verify_is_service_role_key().
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_KEY", "")


def _require_config() -> None:
    if not SUPABASE_URL or not SERVICE_ROLE_KEY:
        sys.exit(
            "Missing SUPABASE_URL or SUPABASE_KEY in backend/.env. "
            "Get the service_role/secret key from the Supabase dashboard: "
            "Settings -> API -> Project API keys -> service_role (or 'secret key')."
        )


def verify_is_service_role_key(client: httpx.Client) -> None:
    """Admin endpoints 401/403 for the anon key — confirms we actually
    have the service_role key before doing anything with it."""
    resp = client.get(f"{SUPABASE_URL}/auth/v1/admin/users", headers=_admin_headers())
    if resp.status_code in (401, 403):
        sys.exit(
            "SUPABASE_KEY was rejected by the Admin API "
            f"(HTTP {resp.status_code}) — this looks like the anon/public "
            "key, not the service_role/secret key. Check Settings -> API "
            "in the Supabase dashboard for the other one."
        )
    resp.raise_for_status()


def _admin_headers() -> dict[str, str]:
    return {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def find_user_id(client: httpx.Client, email: str) -> str | None:
    resp = client.get(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        params={"email": email},
    )
    resp.raise_for_status()
    users = resp.json().get("users", [])
    for user in users:
        if user.get("email") == email:
            return user["id"]
    return None


def create_test_user() -> None:
    with httpx.Client(timeout=15) as client:
        existing_id = find_user_id(client, TEST_EMAIL)
        if existing_id:
            print(f"Test user already exists ({existing_id}); deleting stale copy first.")
            client.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{existing_id}",
                headers=_admin_headers(),
            ).raise_for_status()

        resp = client.post(
            f"{SUPABASE_URL}/auth/v1/admin/users",
            headers=_admin_headers(),
            json={
                "email": TEST_EMAIL,
                "password": TEST_PASSWORD,
                "email_confirm": True,
            },
        )
        resp.raise_for_status()
        user_id = resp.json()["id"]
        print(f"Created test user {TEST_EMAIL} ({user_id}).")
        print("On the emulator: sign-in screen -> 'Sign in with test account' (debug builds only).")


def delete_test_user() -> None:
    with httpx.Client(timeout=15) as client:
        user_id = find_user_id(client, TEST_EMAIL)
        if not user_id:
            print("No test user found; nothing to delete.")
            return
        client.delete(
            f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
            headers=_admin_headers(),
        ).raise_for_status()
        print(f"Deleted test user {TEST_EMAIL} ({user_id}).")


if __name__ == "__main__":
    _require_config()
    if len(sys.argv) != 2 or sys.argv[1] not in {"create", "delete"}:
        sys.exit("Usage: python scripts/manage_test_user.py {create|delete}")
    with httpx.Client(timeout=15) as _client:
        verify_is_service_role_key(_client)
    if sys.argv[1] == "create":
        create_test_user()
    else:
        delete_test_user()
