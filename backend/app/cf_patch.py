"""Swap the upstream Canada client's HTTP session for a curl_cffi one.

Bluelink Canada sits behind Cloudflare, which rejects plain Python TLS
fingerprints, so requests impersonate Chrome.

The session also retries connection errors, but only for endpoints that
cannot act on the vehicle. A connection can drop after the request already
reached Bluelink; re-sending a lock, climate, charge or wake-up request would
then hit the car twice (see the battery-safety rules in AGENTS.md). Anything
not on the allowlist, including endpoints added by future library versions,
is sent exactly once.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from urllib.parse import urlsplit

from curl_cffi import requests as curl_requests

_LOGGER = logging.getLogger(__name__)
_APPLIED = False

_API_PREFIX = "/tods/api/"

# Login and read-only endpoints of the Canada API (KiaUvoApiCA).
RETRYABLE_ENDPOINTS = frozenset(
    {
        "v2/login",
        "mfa/selverifmeth",
        "vhcllst",
        "lstvhclsts",  # cached status; does not wake the car
        "nxtsvc",
        "rmtsts",  # polls a command's result; does not send one
        "evc/selsoc",
        "alerts/maintenance/evTripDetails",
    }
)


def endpoint_for(url: str) -> str:
    path = urlsplit(url).path
    _, found, endpoint = path.partition(_API_PREFIX)
    return endpoint if found else ""


def is_retryable(url: str) -> bool:
    return endpoint_for(url) in RETRYABLE_ENDPOINTS


class CurlCffiRetrySession(curl_requests.Session):
    def __init__(
        self,
        max_retries: int = 3,
        delay: int = 2,
        backoff: int = 2,
        sleep: Callable[[float], None] = time.sleep,
    ):
        super().__init__(impersonate="chrome")
        self.max_retries = max_retries
        self.delay = delay
        self.backoff = backoff
        self._sleep = sleep

    def post(self, url, **kwargs):
        kwargs.setdefault("timeout", 30)
        if not is_retryable(url):
            return super().post(url, **kwargs)

        attempt = 0
        current_delay = self.delay
        while True:
            try:
                return super().post(url, **kwargs)
            except curl_requests.exceptions.HTTPError:
                raise
            except curl_requests.exceptions.ConnectionError:
                attempt += 1
                if attempt >= self.max_retries:
                    raise
                _LOGGER.warning(
                    "connection error on %s; retry %d/%d in %ss",
                    endpoint_for(url),
                    attempt,
                    self.max_retries - 1,
                    current_delay,
                )
                self._sleep(current_delay)
                current_delay *= self.backoff


def apply() -> None:
    global _APPLIED
    if _APPLIED:
        return

    from hyundai_kia_connect_api import KiaUvoApiCA as kia_module

    kia_module.RetrySession = CurlCffiRetrySession
    _APPLIED = True
    _LOGGER.debug("CF patch applied")
