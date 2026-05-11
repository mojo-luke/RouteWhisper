"""
Supabase JWT verification for FastAPI.

Handles both legacy HS256 tokens (signed with the project's JWT Secret)
and modern asymmetric tokens (ES256/RS256, verified against the project's
JWKS endpoint). Picks the right algorithm by reading the token header
first, then verifies with the appropriate key.

Set either `SUPABASE_JWT_SECRET` (legacy HS256 mode) or `SUPABASE_URL`
(JWKS fetched from `<url>/auth/v1/.well-known/jwks.json`). Most projects
should have both — we fall back gracefully.
"""

import logging
import os
from typing import Optional

import jwt
from jwt import PyJWKClient
from fastapi import Header, HTTPException, status
from pydantic import BaseModel

logger = logging.getLogger(__name__)


class CurrentUser(BaseModel):
    """The authenticated caller, as derived from the Supabase JWT."""
    id: str  # Supabase user UUID — primary identity key everywhere.
    email: Optional[str] = None
    role: Optional[str] = None  # "authenticated" for normal users.


_jwks_client: Optional[PyJWKClient] = None


def _get_jwks_client() -> Optional[PyJWKClient]:
    """Lazy-init a JWKS client keyed off SUPABASE_URL.

    PyJWKClient caches the fetched keys in-process, so the round-trip
    only happens once per backend boot (or on key rotation).
    """
    global _jwks_client
    if _jwks_client is not None:
        return _jwks_client
    url = os.getenv("SUPABASE_URL")
    if not url:
        return None
    jwks_url = f"{url.rstrip('/')}/auth/v1/.well-known/jwks.json"
    _jwks_client = PyJWKClient(jwks_url)
    return _jwks_client


def _verify(token: str) -> dict:
    """Decode a Supabase JWT, trying asymmetric (JWKS) first and falling
    back to symmetric (HS256 + JWT secret). Raises jwt.InvalidTokenError
    on any failure so callers can return 401.
    """
    # Peek at the header to pick the algorithm. Doesn't verify anything.
    header = jwt.get_unverified_header(token)
    alg = header.get("alg")

    common_kwargs = {
        "algorithms": [alg] if alg else ["HS256", "ES256", "RS256"],
        "audience": "authenticated",
    }

    # Asymmetric path
    if alg in ("ES256", "RS256"):
        jwks = _get_jwks_client()
        if jwks is None:
            raise jwt.InvalidTokenError(
                "Token is asymmetric but SUPABASE_URL is not set "
                "(can't fetch JWKS to verify)."
            )
        signing_key = jwks.get_signing_key_from_jwt(token).key
        return jwt.decode(token, signing_key, **common_kwargs)

    # Symmetric path (legacy)
    secret = os.getenv("SUPABASE_JWT_SECRET")
    if not secret:
        raise jwt.InvalidTokenError(
            "Token is HS256 but SUPABASE_JWT_SECRET is not set."
        )
    return jwt.decode(token, secret, **common_kwargs)


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
        payload = _verify(token)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError as e:
        logger.warning("JWT verification failed: %s", e)
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
