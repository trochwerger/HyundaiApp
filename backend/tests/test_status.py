from types import SimpleNamespace

import pytest
from hyundai_kia_connect_api.exceptions import AuthenticationError

from app.car import CarService


class StubVehicleManager:
    def __init__(self, *, force_errors: int = 0, cached_errors: int = 0) -> None:
        self.force_errors = force_errors
        self.cached_errors = cached_errors
        self.force_refresh_calls = 0
        self.cached_refresh_calls = 0
        self.vehicles = {"vehicle-1": SimpleNamespace(id="vehicle-1", name="Tucson")}

    def force_refresh_all_vehicles_states(self) -> None:
        self.force_refresh_calls += 1
        if self.force_errors:
            self.force_errors -= 1
            raise AuthenticationError("expired")

    def update_all_vehicles_with_cached_state(self) -> None:
        self.cached_refresh_calls += 1
        if self.cached_errors:
            self.cached_errors -= 1
            raise AuthenticationError("expired")

    def get_vehicle(self, vehicle_id: str) -> SimpleNamespace:
        return self.vehicles[vehicle_id]


def make_car_service(vehicle_manager: StubVehicleManager) -> tuple[CarService, list[int]]:
    service = CarService.__new__(CarService)
    service._settings = SimpleNamespace(force_refresh_min_interval_seconds=600)
    service._vehicle_manager = vehicle_manager
    service._vehicle_id = None
    service._last_force_refresh_at = None
    force_reauth_calls: list[int] = []

    def force_reauth() -> None:
        force_reauth_calls.append(1)

    service.force_reauth = force_reauth
    return service, force_reauth_calls


def test_status_cached_path(client, auth_headers):
    response = client.get("/status", headers=auth_headers)

    assert response.status_code == 200
    assert response.json()["source"] == "cached"


def test_status_force_path(client, auth_headers, fake_car_service):
    response = client.get("/status?force=true", headers=auth_headers)

    assert response.status_code == 200
    assert response.json()["source"] == "force"
    assert fake_car_service.force_calls == 1
    assert fake_car_service.last_force_refresh_at is not None


def test_status_force_rate_limit(client, auth_headers, fake_car_service):
    first = client.get("/status?force=true", headers=auth_headers)
    second = client.get("/status?force=true", headers=auth_headers)

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.headers["Retry-After"] == "600"
    assert second.json()["detail"]["error"] == "rate_limited"
    assert second.json()["detail"]["retry_after_seconds"] == 600


def test_get_status_retries_once_on_authentication_error():
    vehicle_manager = StubVehicleManager(force_errors=1)
    service, force_reauth_calls = make_car_service(vehicle_manager)

    status = service.get_status(force=True)

    assert status["id"] == "vehicle-1"
    assert len(force_reauth_calls) == 1
    assert vehicle_manager.force_refresh_calls == 2


def test_get_status_propagates_when_reauth_retry_also_fails():
    vehicle_manager = StubVehicleManager(force_errors=2)
    service, force_reauth_calls = make_car_service(vehicle_manager)

    with pytest.raises(AuthenticationError):
        service.get_status(force=True)

    assert len(force_reauth_calls) == 1
    assert vehicle_manager.force_refresh_calls == 2


def test_get_status_cached_path_retries_once_on_authentication_error():
    vehicle_manager = StubVehicleManager(cached_errors=1)
    service, force_reauth_calls = make_car_service(vehicle_manager)

    status = service.get_status(force=False)

    assert status["id"] == "vehicle-1"
    assert len(force_reauth_calls) == 1
    assert vehicle_manager.cached_refresh_calls == 2


def test_get_status_does_not_reauth_on_success():
    vehicle_manager = StubVehicleManager()
    service, force_reauth_calls = make_car_service(vehicle_manager)

    status = service.get_status(force=True)

    assert status["id"] == "vehicle-1"
    assert force_reauth_calls == []
    assert vehicle_manager.force_refresh_calls == 1
