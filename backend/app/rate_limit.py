"""Small in-memory rate limiter for command routes."""

from __future__ import annotations

import math
import threading
import time

from fastapi import HTTPException, Request, status


class FixedWindowRateLimiter:
    def __init__(self, limit: int, window_seconds: int) -> None:
        self._limit = limit
        self._window_seconds = window_seconds
        self._lock = threading.Lock()
        self._buckets: dict[str, tuple[float, int]] = {}

    def allow(self, key: str) -> int | None:
        now = time.monotonic()
        with self._lock:
            window_started_at, count = self._buckets.get(key, (now, 0))
            elapsed = now - window_started_at
            if elapsed >= self._window_seconds:
                self._buckets[key] = (now, 1)
                return None

            if count < self._limit:
                self._buckets[key] = (window_started_at, count + 1)
                return None

            return max(1, math.ceil(self._window_seconds - elapsed))


def command_rate_limit(request: Request) -> None:
    settings = request.app.state.settings
    limiter = getattr(request.app.state, "command_rate_limiter", None)
    if limiter is None:
        limiter = FixedWindowRateLimiter(
            limit=settings.command_rate_limit_per_minute,
            window_seconds=settings.command_rate_limit_window_seconds,
        )
        request.app.state.command_rate_limiter = limiter

    client_host = request.client.host if request.client else "unknown"
    retry_after_seconds = limiter.allow(client_host)
    if retry_after_seconds is None:
        return None

    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "error": "rate_limited",
            "retry_after_seconds": retry_after_seconds,
        },
        headers={"Retry-After": str(retry_after_seconds)},
    )
