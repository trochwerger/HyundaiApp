from __future__ import annotations

import datetime as dt
import os
import pathlib
import tempfile

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

os.environ.setdefault("BLUELINK_EMAIL", "driver@example.com")
os.environ.setdefault("BLUELINK_PASSWORD", "password")
os.environ.setdefault("BLUELINK_PIN", "1234")
os.environ.setdefault("API_KEY", "test-api-key")
os.environ.setdefault("REGION", "canada")
os.environ.setdefault("BRAND", "hyundai")
os.environ.setdefault("FORCE_REFRESH_MIN_INTERVAL_SECONDS", "600")
os.environ.setdefault("COMMAND_RATE_LIMIT_PER_MINUTE", "2")
os.environ.setdefault("COMMAND_RATE_LIMIT_WINDOW_SECONDS", "60")
os.environ.setdefault("SNAPSHOT_INTERVAL_SECONDS", "900")
os.environ.setdefault(
    "SNAPSHOT_DB_PATH",
    str(pathlib.Path(tempfile.gettempdir()) / "hyundaiapp-test-snapshots.db"),
)

from app.config import Settings
from app.main import create_app


class FakeCarService:
    def __init__(self) -> None:
        self.metadata = {
            "id": "vehicle-1",
            "name": "Tucson",
            "model": "Tucson Ultimate PHEV",
            "year": 2025,
            "vin": "KM8TEST1234567890",
            "registration_date": "2025-01-01",
        }
        self.cached_status = {
            "id": "vehicle-1",
            "name": "Tucson",
            "engine_is_running": False,
            "car_battery_percentage": 82,
            "last_updated_at": "2026-04-22T12:00:00+00:00",
            "source": "cached",
        }
        self.forced_status = {
            "id": "vehicle-1",
            "name": "Tucson",
            "engine_is_running": True,
            "car_battery_percentage": 81,
            "last_updated_at": "2026-04-22T12:05:00+00:00",
            "source": "force",
        }
        self.force_calls = 0
        self.last_force_refresh_at: dt.datetime | None = None
        self.force_rate_limited = False
        self.calls: list[tuple[str, dict]] = []
        self.raise_upstream: str | None = None

    def get_vehicle_metadata(self) -> dict:
        return self.metadata

    def get_status(self, force: bool = False) -> dict:
        if not force:
            return self.cached_status

        if self.force_rate_limited:
            raise HTTPException(
                status_code=429,
                detail={
                    "error": "rate_limited",
                    "retry_after_seconds": 600,
                },
                headers={"Retry-After": "600"},
            )

        self.force_calls += 1
        self.last_force_refresh_at = dt.datetime.now(dt.timezone.utc)
        self.force_rate_limited = True
        return self.forced_status

    def lock(self) -> dict:
        return self._command("lock")

    def unlock(self) -> dict:
        return self._command("unlock")

    def start_climate(
        self,
        temp: float | None,
        defrost: bool | None,
        duration: int | None,
    ) -> dict:
        return self._command(
            "start",
            temp=temp,
            defrost=defrost,
            duration=duration,
        )

    def stop_climate(self) -> dict:
        return self._command("stop")

    def start_charge(self) -> dict:
        return self._command("charge-start")

    def stop_charge(self) -> dict:
        return self._command("charge-stop")

    def get_trips(self, from_date: dt.date, to_date: dt.date) -> dict:
        self.calls.append(
            (
                "trips",
                {
                    "from_date": from_date,
                    "to_date": to_date,
                },
            )
        )
        return {
            "from": from_date.isoformat(),
            "to": to_date.isoformat(),
            "trips": [],
        }

    def _command(self, command: str, **kwargs) -> dict:
        if self.raise_upstream == command:
            self.raise_upstream = None
            raise RuntimeError("upstream exploded")

        self.calls.append((command, kwargs))
        return {"ok": True, "command": command, **kwargs}


@pytest.fixture()
def test_settings(monkeypatch: pytest.MonkeyPatch, tmp_path: pathlib.Path) -> Settings:
    monkeypatch.setenv("BLUELINK_EMAIL", "driver@example.com")
    monkeypatch.setenv("BLUELINK_PASSWORD", "password")
    monkeypatch.setenv("BLUELINK_PIN", "1234")
    monkeypatch.setenv("API_KEY", "test-api-key")
    monkeypatch.setenv("REGION", "canada")
    monkeypatch.setenv("BRAND", "hyundai")
    monkeypatch.setenv("FORCE_REFRESH_MIN_INTERVAL_SECONDS", "600")
    monkeypatch.setenv("COMMAND_RATE_LIMIT_PER_MINUTE", "2")
    monkeypatch.setenv("COMMAND_RATE_LIMIT_WINDOW_SECONDS", "60")
    monkeypatch.setenv("SNAPSHOT_INTERVAL_SECONDS", "900")
    monkeypatch.setenv("SNAPSHOT_DB_PATH", str(tmp_path / "snapshots.db"))
    return Settings()


@pytest.fixture()
def fake_car_service() -> FakeCarService:
    return FakeCarService()


@pytest.fixture()
def client(fake_car_service: FakeCarService, test_settings: Settings):
    app = create_app(car_service=fake_car_service, settings=test_settings)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def auth_headers(test_settings: Settings) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {test_settings.api_key.get_secret_value()}",
    }
