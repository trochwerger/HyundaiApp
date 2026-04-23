from __future__ import annotations

import datetime as dt


def test_trips_happy_path(client, auth_headers, fake_car_service):
    response = client.get(
        "/trips?from=2026-04-01&to=2026-04-07",
        headers=auth_headers,
    )

    assert response.status_code == 200
    assert response.json()["from"] == "2026-04-01"
    assert fake_car_service.calls[-1] == (
        "trips",
        {
            "from_date": dt.date(2026, 4, 1),
            "to_date": dt.date(2026, 4, 7),
        },
    )


def test_trips_requires_from(client, auth_headers):
    response = client.get("/trips?to=2026-04-07", headers=auth_headers)

    assert response.status_code == 422


def test_trips_requires_to(client, auth_headers):
    response = client.get("/trips?from=2026-04-01", headers=auth_headers)

    assert response.status_code == 422


def test_trips_rejects_from_after_to(client, auth_headers):
    response = client.get(
        "/trips?from=2026-04-08&to=2026-04-07",
        headers=auth_headers,
    )

    assert response.status_code == 400


def test_trips_rejects_range_over_92_days(client, auth_headers):
    response = client.get(
        "/trips?from=2026-01-01&to=2026-04-04",
        headers=auth_headers,
    )

    assert response.status_code == 400


def test_trips_requires_api_key(client):
    response = client.get("/trips?from=2026-04-01&to=2026-04-07")

    assert response.status_code == 401
