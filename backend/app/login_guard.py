"""Backoff gate for Bluelink logins.

Every failed login is another hit on Hyundai's auth endpoint. Repeated
failures (for example a restart loop) get the account rate-limited with HTTP
429, which then makes every later login fail too. This gate spaces attempts
out exponentially after each failure and resets after a success.
"""

from __future__ import annotations

import math
import time
from collections.abc import Callable

from fastapi import HTTPException, status


class LoginUnavailable(HTTPException):
    """Raised when no Bluelink session exists and a login is not allowed yet,
    or when the login attempt itself failed. Routes surface it as a 503."""

    def __init__(self, retry_after_seconds: int, message: str) -> None:
        super().__init__(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": "upstream_login_unavailable",
                "retry_after_seconds": retry_after_seconds,
                "message": message,
            },
            headers={"Retry-After": str(retry_after_seconds)},
        )
        self.retry_after_seconds = retry_after_seconds


class LoginBackoff:
    def __init__(
        self,
        initial_seconds: int,
        max_seconds: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._initial = max(1, initial_seconds)
        self._max = max(self._initial, max_seconds)
        self._clock = clock
        self._failures = 0
        self._next_attempt_at: float | None = None

    @property
    def failures(self) -> int:
        return self._failures

    def retry_after_seconds(self) -> int | None:
        """Seconds until the next login may be attempted, or None if allowed now."""

        if self._next_attempt_at is None:
            return None
        remaining = self._next_attempt_at - self._clock()
        if remaining <= 0:
            return None
        return max(1, math.ceil(remaining))

    def record_failure(self) -> int:
        """Register a failed attempt and return the delay before the next one."""

        self._failures += 1
        delay = min(self._initial * 2 ** (self._failures - 1), self._max)
        self._next_attempt_at = self._clock() + delay
        return delay

    def record_success(self) -> None:
        self._failures = 0
        self._next_attempt_at = None
