"""
Supabase JWT verification for FastAPI.

Supabase signs session JWTs with the project's `JWT secret` (HS256). Any
endpoint that needs the caller's identity declares `current_user` as a
dependency, which validates the token and returns the Supabase user id.

Why HS256 (shared secret) instead of pulling Supabase's JWKS for RS256:
the project secret is the documented Supabase pattern and avoids the
extra round-trip / key cache. If we ever want third-party verifiers, we
can swap to JWKS later.
"""

import os
from typing import Optional

import jwt
from fastapi import Depends, Header, HTTPException, status
from pydantic import BaseModel


class CurrentUser(BaseModel):
    """The authenticated caller, as derived from the Supabase JWT."""
    id: str  # Supabase user UUID — primary identity key everywhere.
    email: Optional[str] = None
    role: Optional[str] = None  # "authenticated" for normal users.


def _supabase_jwt_secret() -> str:
    secret = os.getenv("SUPABASE_JWT_SECRET")
    if not secret:
        # Fail loud at first request rather than at import — keeps tests
        # that don't hit auth endpoints from needing the secret.
        raise RuntimeError(
            "SUPABASE_JWT_SECRET is not set. Copy it from your Supabase "
            "project's Settings → API → JWT Secret."
        )
    return secret


async def current_user(
    authorization: Optional[str] = Header(default=None),
) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = authorization.split(" ", 1)[1].strip()
    try:
        payload = jwt.decode(
            token,
            _supabase_jwt_secret(),
            algorithms=["HS256"],
            # Supabase tokens are issued with audience "authenticated".
            audience="authenticated",
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {e}",
            headers={"WWW-Authenticate": "Bearer"},
        )

    sub = payload.get("sub")
    if not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing 'sub' claim.",
        )
    return CurrentUser(
        id=str(sub),
        email=payload.get("email"),
        role=payload.get("role"),
    )


# Re-export as a clean dependency alias so endpoint signatures read well:
#     async def handler(user: CurrentUser = Depends(get_current_user))
get_current_user = current_user
