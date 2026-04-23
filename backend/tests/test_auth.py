def test_status_requires_auth(client):
    response = client.get("/status")

    assert response.status_code == 401
    assert response.json() == {"detail": "unauthorized"}
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_status_rejects_bad_key(client):
    response = client.get(
        "/status",
        headers={"Authorization": "Bearer wrong"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "unauthorized"}
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_status_accepts_good_key(client, auth_headers):
    response = client.get("/status", headers=auth_headers)

    assert response.status_code == 200
    assert response.json()["source"] == "cached"


def test_health_does_not_require_auth(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
