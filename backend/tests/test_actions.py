import threading
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.car import CarService
from app.login_guard import LoginBackoff


def test_action_status_requires_auth(client):
    assert client.get("/actions/abc123").status_code == 401


def test_action_status_returns_status(client, auth_headers, fake_car_service):
    fake_car_service.action_status = "success"

    response = client.get("/actions/tx-42_A", headers=auth_headers)

    assert response.status_code == 200
    assert response.json() == {"action_id": "tx-42_A", "status": "success"}
    assert fake_car_service.calls[-1] == ("action_status", {"action_id": "tx-42_A"})


@pytest.mark.parametrize("bad_id", ["a b", "a%0Ab", "x" * 129, "id;rm"])
def test_action_status_rejects_unsafe_ids(client, auth_headers, fake_car_service, bad_id):
    response = client.get(f"/actions/{bad_id}", headers=auth_headers)

    assert response.status_code in (404, 422)
    assert not any(call[0] == "action_status" for call in fake_car_service.calls)


def test_action_status_is_rate_limited_separately_from_commands(client, auth_headers):
    for _ in range(12):
        assert client.get("/actions/tx1", headers=auth_headers).status_code == 200

    limited = client.get("/actions/tx1", headers=auth_headers)
    assert limited.status_code == 429
    assert "Retry-After" in limited.headers

    # Command routes keep their own budget.
    assert client.post("/command/lock", headers=auth_headers).status_code == 200


class ActionVehicleManager:
    def __init__(self, result) -> None:
        self.result = result
        self.calls: list[tuple] = []
        self.vehicles = {"vehicle-1": SimpleNamespace(id="vehicle-1")}

    def check_action_status(self, vehicle_id, action_id, synchronous=False):
        self.calls.append((vehicle_id, action_id, synchronous))
        if isinstance(self.result, Exception):
            raise self.result
        return self.result

    def start_climate(self, vehicle_id, options):
        return "tx-123"


def make_service(vm) -> CarService:
    service = CarService.__new__(CarService)
    service._settings = SimpleNamespace(force_refresh_min_interval_seconds=600)
    service._vehicle_manager = vm
    service._vehicle_id = None
    service._last_force_refresh_at = None
    service._ready = True
    service._login_lock = threading.Lock()
    service._login_backoff = LoginBackoff(initial_seconds=900, max_seconds=3600)
    return service


def test_get_action_status_maps_enum_and_never_waits():
    from hyundai_kia_connect_api.const import ORDER_STATUS

    vm = ActionVehicleManager(ORDER_STATUS.SUCCESS)
    result = make_service(vm).get_action_status("tx-123")

    assert result == {"action_id": "tx-123", "status": "success"}
    assert vm.calls == [("vehicle-1", "tx-123", False)]


def test_get_action_status_upstream_error_is_502():
    vm = ActionVehicleManager(KeyError("result"))

    with pytest.raises(HTTPException) as exc:
        make_service(vm).get_action_status("tx-123")
    assert exc.value.status_code == 502


def test_command_response_exposes_action_id():
    response = make_service(ActionVehicleManager(None)).start_climate(22, False, 10)

    assert response["action_id"] == "tx-123"
    assert response["result"] == "tx-123"
