import pytest
from curl_cffi import requests as curl_requests

from app.cf_patch import CurlCffiRetrySession, RETRYABLE_ENDPOINTS, is_retryable

API = "https://mybluelink.ca/tods/api/"

# Endpoints that act on the vehicle or have side effects (KiaUvoApiCA).
NEVER_RETRIED = [
    "drlck",  # lock
    "drulck",  # unlock
    "rmtstrt",  # climate start
    "rmtstp",  # climate stop
    "evc/rfon",
    "evc/rfoff",
    "evc/rcstrt",  # charge start
    "evc/rcstp",  # charge stop
    "evc/setsoc",
    "rltmvhclsts",  # force refresh, wakes the car
    "fndmcr",  # locate car
    "vrfypin",
    "mfa/sendotp",  # emails an OTP
    "mfa/validateotp",
    "mfa/genmfatkn",
    "some/future-endpoint",
]


class FakeTransport:
    def __init__(self, failures: int) -> None:
        self.failures = failures
        self.calls: list[str] = []

    # Patched onto curl_requests.Session as a plain object, so it is not bound
    # and receives only the call arguments.
    def __call__(self, url, **kwargs):
        self.calls.append(url)
        if self.failures:
            self.failures -= 1
            raise curl_requests.exceptions.ConnectionError("connection reset")
        return "ok"


@pytest.fixture()
def session():
    return CurlCffiRetrySession(max_retries=3, delay=2, backoff=2, sleep=lambda _: None)


@pytest.mark.parametrize("endpoint", NEVER_RETRIED)
def test_side_effect_endpoints_are_sent_once(monkeypatch, session, endpoint):
    transport = FakeTransport(failures=5)
    monkeypatch.setattr(curl_requests.Session, "post", transport)

    with pytest.raises(curl_requests.exceptions.ConnectionError):
        session.post(API + endpoint, json={})

    assert transport.calls == [API + endpoint]


def test_cached_status_read_still_retries(monkeypatch, session):
    transport = FakeTransport(failures=2)
    monkeypatch.setattr(curl_requests.Session, "post", transport)

    assert session.post(API + "lstvhclsts") == "ok"
    assert len(transport.calls) == 3


def test_retryable_read_gives_up_after_max_retries(monkeypatch, session):
    transport = FakeTransport(failures=10)
    monkeypatch.setattr(curl_requests.Session, "post", transport)

    with pytest.raises(curl_requests.exceptions.ConnectionError):
        session.post(API + "v2/login")
    assert len(transport.calls) == 3


def test_retry_delays_back_off(monkeypatch):
    delays: list[float] = []
    session = CurlCffiRetrySession(max_retries=3, delay=2, backoff=2, sleep=delays.append)
    monkeypatch.setattr(curl_requests.Session, "post", FakeTransport(failures=2))

    session.post(API + "vhcllst")
    assert delays == [2, 4]


def test_allowlist_has_no_command_endpoints():
    assert not RETRYABLE_ENDPOINTS & set(NEVER_RETRIED)
    assert not is_retryable("https://mybluelink.ca/other/lstvhclsts")
