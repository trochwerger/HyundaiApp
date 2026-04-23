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
