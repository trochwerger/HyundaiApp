from __future__ import annotations

import logging
import time

_LOGGER = logging.getLogger(__name__)
_APPLIED = False


def apply() -> None:
    global _APPLIED
    if _APPLIED:
        return

    from curl_cffi import requests as curl_requests
    from hyundai_kia_connect_api import KiaUvoApiCA as kia_module

    class CurlCffiRetrySession(curl_requests.Session):
        def __init__(self, max_retries: int = 3, delay: int = 2, backoff: int = 2):
            super().__init__(impersonate="chrome")
            self.max_retries = max_retries
            self.delay = delay
            self.backoff = backoff

        def post(self, url, **kwargs):
            kwargs.setdefault("timeout", 30)
            attempt = 0
            current_delay = self.delay
            last_exception = None
            while attempt < self.max_retries:
                try:
                    return super().post(url, **kwargs)
                except curl_requests.exceptions.HTTPError:
                    raise
                except curl_requests.exceptions.ConnectionError as exc:
                    last_exception = exc
                    attempt += 1
                    if attempt >= self.max_retries:
                        break
                    time.sleep(current_delay)
                    current_delay *= self.backoff
                except curl_requests.exceptions.RequestException:
                    raise
            if last_exception is not None:
                raise last_exception

    kia_module.RetrySession = CurlCffiRetrySession
    _APPLIED = True
    _LOGGER.debug("CF patch applied")
