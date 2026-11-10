"""Command outcome route."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Path, Request, status

from app.auth import require_api_key
from app.rate_limit import FixedWindowRateLimiter

router = APIRouter(dependencies=[Depends(require_api_key)])

# Clients poll this while waiting for the car (about every 10 s for up to
# 2 min). Each call reads Bluelink's server, never the car; the limit keeps a
# misbehaving client from turning that into a flood.
ACTION_STATUS_LIMIT = 12
ACTION_STATUS_WINDOW_SECONDS = 60


def action_status_rate_limit(request: Request) -> None:
    limiter = getattr(request.app.state, "action_status_limiter", None)
    if limiter is None:
        limiter = FixedWindowRateLimiter(
            limit=ACTION_STATUS_LIMIT, window_seconds=ACTION_STATUS_WINDOW_SECONDS
        )
        request.app.state.action_status_limiter = limiter

    retry_after_seconds = limiter.allow("action-status")
    if retry_after_seconds is None:
        return None
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={"error": "rate_limited", "retry_after_seconds": retry_after_seconds},
        headers={"Retry-After": str(retry_after_seconds)},
    )


@router.get("/actions/{action_id}", dependencies=[Depends(action_status_rate_limit)])
def get_action_status(
    request: Request,
    # Sent upstream as a header, so only allow the id's own character set.
    action_id: str = Path(min_length=1, max_length=128, pattern=r"^[A-Za-z0-9_-]+$"),
) -> dict:
    return request.app.state.car.get_action_status(action_id)
