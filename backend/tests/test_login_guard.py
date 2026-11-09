import threading
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

import app.main as main_module
from app.car import CarService
from app.login_guard import LoginBackoff, LoginUnavailable


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class LoginStubVehicleManager:
    """Fails the first `login_failures` logins, then succeeds."""

    def __init__(self, login_failures: int = 0) -> None:
        self.login_failures = login_failures
        self.login_calls = 0
        self.cached_refresh_calls = 0
        self.token = None
        self.vehicles = {"vehicle-1": SimpleNamespace(id="vehicle-1", name="Tucson")}

    def check_and_refresh_token(self) -> bool:
        self.login_calls += 1
        if self.login_failures:
            self.login_failures -= 1
            # What the upstream library raises when Bluelink answers HTTP 429.
            raise KeyError("responseHeader")
        self.token = "token"
        return True

    def update_all_vehicles_with_cached_state(self) -> None:
        self.cached_refresh_calls += 1

    def get_vehicle(self, vehicle_id: str) -> SimpleNamespace:
        return self.vehicles[vehicle_id]


def make_service(vm: LoginStubVehicleManager, clock: FakeClock) -> CarService:
    service = CarService.__new__(CarService)
    service._settings = SimpleNamespace(force_refresh_min_interval_seconds=600)
    service._vehicle_manager = vm
    service._vehicle_id = None
    service._last_force_refresh_at = None
    service._ready = False
    service._login_lock = threading.Lock()
    service._login_backoff = LoginBackoff(initial_seconds=900, max_seconds=3600, clock=clock)
    return service


def test_backoff_doubles_caps_and_resets():
    clock = FakeClock()
    backoff = LoginBackoff(initial_seconds=900, max_seconds=3600, clock=clock)

    assert backoff.retry_after_seconds() is None
    assert backoff.record_failure() == 900
    assert backoff.record_failure() == 1800
    assert backoff.record_failure() == 3600
    assert backoff.record_failure() == 3600
    assert backoff.retry_after_seconds() == 3600

    clock.now += 3600
    assert backoff.retry_after_seconds() is None

    backoff.record_success()
    assert backoff.record_failure() == 900


def test_failed_login_blocks_further_attempts_until_backoff_passes():
    clock = FakeClock()
    vm = LoginStubVehicleManager(login_failures=2)
    service = make_service(vm, clock)

    with pytest.raises(LoginUnavailable) as first:
        service.initialize()
    assert first.value.retry_after_seconds == 900
    assert first.value.status_code == 503

    # Inside the window: no new upstream login is attempted.
    for _ in range(5):
        with pytest.raises(LoginUnavailable):
            service.get_status(force=False)
    assert vm.login_calls == 1

    clock.now += 900
    with pytest.raises(LoginUnavailable) as second:
        service.get_status(force=False)
    assert second.value.retry_after_seconds == 1800
    assert vm.login_calls == 2

    clock.now += 1800
    status = service.get_status(force=False)
    assert status["id"] == "vehicle-1"
    assert vm.login_calls == 3


def test_successful_login_resets_backoff_and_is_not_repeated():
    clock = FakeClock()
    vm = LoginStubVehicleManager()
    service = make_service(vm, clock)

    service.initialize()
    service.get_status(force=False)
    service.get_status(force=False)

    assert vm.login_calls == 1
    assert service._login_backoff.failures == 0


def test_force_reauth_respects_backoff():
    clock = FakeClock()
    vm = LoginStubVehicleManager(login_failures=1)
    service = make_service(vm, clock)

    with pytest.raises(LoginUnavailable):
        service.force_reauth()
    with pytest.raises(LoginUnavailable):
        service.force_reauth()

    assert vm.login_calls == 1


def test_commands_are_not_sent_without_a_session():
    clock = FakeClock()
    vm = LoginStubVehicleManager(login_failures=1)
    vm.lock = lambda vehicle_id: pytest.fail("lock must not be sent without a session")
    service = make_service(vm, clock)

    with pytest.raises(LoginUnavailable):
        service.initialize()
    with pytest.raises(LoginUnavailable):
        service.lock()


class UnavailableCarService:
    def __init__(self, settings) -> None:
        self.status_calls = 0

    def initialize(self) -> None:
        raise LoginUnavailable(900, "Bluelink login failed (KeyError).")

    def get_status(self, force: bool = False) -> dict:
        self.status_calls += 1
        raise LoginUnavailable(900, "Bluelink login is backing off after earlier failures.")


def test_app_stays_up_when_startup_login_fails(monkeypatch, test_settings):
    monkeypatch.setattr(main_module, "CarService", UnavailableCarService)
    app = main_module.create_app(settings=test_settings)

    with TestClient(app) as client:
        assert client.get("/health").status_code == 200

        response = client.get(
            "/status",
            headers={"Authorization": f"Bearer {test_settings.api_key.get_secret_value()}"},
        )
        assert response.status_code == 503
        assert response.headers["Retry-After"] == "900"
        assert response.json()["detail"]["error"] == "upstream_login_unavailable"
