"""Bearer API-key authentication helpers."""

from __future__ import annotations

import hmac

from fastapi import HTTPException, Request, status

UNAUTHORIZED_HEADERS = {"WWW-Authenticate": "Bearer"}


def _unauthorized() -> None:
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="unauthorized",
        headers=UNAUTHORIZED_HEADERS,
    )


def require_api_key(request: Request) -> None:
    """Require a valid Bearer API key."""

    authorization = request.headers.get("Authorization")
    if not authorization:
        _unauthorized()

    scheme, _, token = authorization.partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token:
        _unauthorized()

    expected = request.app.state.settings.api_key.get_secret_value()
    if not hmac.compare_digest(token, expected):
        _unauthorized()
