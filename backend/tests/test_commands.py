from __future__ import annotations

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.rate_limit import command_rate_limit


COMMANDS = [
    ("lock", "/command/lock", None, ("lock", {})),
    ("unlock", "/command/unlock", None, ("unlock", {})),
    (
        "start",
        "/command/start",
        {"temp": 22, "defrost": True, "duration": 10},
        ("start", {"temp": 22, "defrost": True, "duration": 10}),
    ),
    ("stop", "/command/stop", None, ("stop", {})),
    ("charge-start", "/command/charge-start", None, ("charge-start", {})),
    ("charge-stop", "/command/charge-stop", None, ("charge-stop", {})),
]


def post_command(client, path: str, headers: dict[str, str] | None, payload: dict | None):
    if payload is None:
        return client.post(path, headers=headers)
    return client.post(path, headers=headers, json=payload)


@pytest.mark.parametrize(("command", "path", "payload", "expected_call"), COMMANDS)
def test_command_happy_path(
    client,
    auth_headers,
    fake_car_service,
    command,
    path,
    payload,
    expected_call,
):
    response = post_command(client, path, auth_headers, payload)

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert response.json()["command"] == command
    assert fake_car_service.calls[-1] == expected_call


@pytest.mark.parametrize(("command", "path", "payload", "expected_call"), COMMANDS)
def test_command_requires_api_key(client, command, path, payload, expected_call):
    response = post_command(client, path, None, payload)

    assert response.status_code == 401


@pytest.mark.parametrize(
    "payload",
    [
        {"temp": 5},
        {"temp": 40},
        {"duration": 0},
        {"duration": 60},
    ],
)
def test_climate_start_rejects_invalid_payload(client, auth_headers, payload):
    response = client.post("/command/start", headers=auth_headers, json=payload)

    assert response.status_code == 422


@pytest.mark.parametrize(("command", "path", "payload", "expected_call"), COMMANDS)
def test_command_upstream_failure_is_structured(
    client,
    auth_headers,
    fake_car_service,
    command,
    path,
    payload,
    expected_call,
):
    fake_car_service.raise_upstream = command

    response = post_command(client, path, auth_headers, payload)

    assert response.status_code == 502
    detail = response.json()["detail"]
    assert detail["error"] == "upstream_error"
    assert detail["command"] == command
    assert detail["message"] == "upstream exploded"
    assert detail["type"] == "RuntimeError"


def test_command_rate_limit(client, auth_headers):
    first = client.post("/command/lock", headers=auth_headers)
    second = client.post("/command/lock", headers=auth_headers)
    third = client.post("/command/lock", headers=auth_headers)

    assert first.status_code == 200
    assert second.status_code == 200
    assert third.status_code == 429
    assert third.headers["Retry-After"]
    assert third.json()["detail"]["error"] == "rate_limited"


def test_command_rate_limit_is_per_ip(client):
    app = client.app

    def request_from(ip_address: str) -> Request:
        return Request(
            {
                "type": "http",
                "method": "POST",
                "path": "/command/lock",
                "headers": [],
                "client": (ip_address, 12345),
                "server": ("testserver", 80),
                "scheme": "http",
                "app": app,
            }
        )

    command_rate_limit(request_from("203.0.113.10"))
    command_rate_limit(request_from("203.0.113.10"))
    with pytest.raises(HTTPException) as exc_info:
        command_rate_limit(request_from("203.0.113.10"))

    # TestClient always uses request.client.host == "testclient" for normal
    # requests, regardless of X-Forwarded-For, so this exercises the dependency
    # directly with distinct ASGI client addresses.
    command_rate_limit(request_from("203.0.113.11"))

    assert exc_info.value.status_code == 429
    assert exc_info.value.detail["error"] == "rate_limited"
