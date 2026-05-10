from __future__ import annotations

import asyncio
import pathlib
import time
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from app.snapshots import SnapshotStore, run_collector_loop


def sample_status(**overrides) -> dict:
    status = {
        "id": "vehicle-1",
        "odometer": 12345.6,
        "fuel_level": 50,
        "ev_battery_percentage": 80,
        "is_locked": True,
        "ev_battery_is_charging": False,
        "engine_is_running": False,
        "location": {
            "latitude": 43.65,
            "longitude": -79.38,
        },
    }
    status.update(overrides)
    return status


@pytest.fixture()
async def snapshot_store(tmp_path: pathlib.Path):
    store = SnapshotStore(str(tmp_path / "snapshots.db"))
    await store.initialize()
    try:
        yield store
    finally:
        await store.close()


async def test_insert_extracts_indexed_columns(snapshot_store: SnapshotStore) -> None:
    status = sample_status()

    inserted = await snapshot_store.insert(status, vehicle_id=status["id"])
    rows, has_more = await snapshot_store.query()

    assert inserted is True
    assert has_more is False
    assert len(rows) == 1
    row = rows[0]
    assert row["vehicle_id"] == "vehicle-1"
    assert row["odometer_km"] == 12345.6
    assert row["fuel_percent"] == 50
    assert row["ev_battery_percent"] == 80
    assert row["is_locked"] == 1
    assert row["is_charging"] == 0
    assert row["engine_is_running"] == 0
    assert row["latitude"] == 43.65
    assert row["longitude"] == -79.38
    assert row["status"] == status


async def test_insert_dedups_identical_status(snapshot_store: SnapshotStore) -> None:
    status = sample_status()

    assert await snapshot_store.insert(status, vehicle_id=status["id"]) is True
    assert await snapshot_store.insert(status, vehicle_id=status["id"]) is False

    rows, _ = await snapshot_store.query()
    assert len(rows) == 1


async def test_insert_allows_changed_dedup_field(snapshot_store: SnapshotStore) -> None:
    status = sample_status()

    assert await snapshot_store.insert(status, vehicle_id=status["id"]) is True
    assert (
        await snapshot_store.insert(
            sample_status(odometer=12346.0),
            vehicle_id=status["id"],
        )
        is True
    )

    rows, _ = await snapshot_store.query()
    assert len(rows) == 2


async def test_latest_returns_most_recent_row_and_none_when_empty(
    snapshot_store: SnapshotStore,
) -> None:
    assert await snapshot_store.latest() is None

    await snapshot_store.insert(sample_status(odometer=1), vehicle_id="vehicle-1")
    await snapshot_store.insert(sample_status(odometer=2), vehicle_id="vehicle-2")

    latest = await snapshot_store.latest()
    assert latest is not None
    assert latest["vehicle_id"] == "vehicle-2"
    assert latest["odometer_km"] == 2


async def test_query_filters_from_to_limit_and_has_more(
    snapshot_store: SnapshotStore,
) -> None:
    await snapshot_store.insert(sample_status(odometer=1), vehicle_id="vehicle-1")
    await asyncio.sleep(0.001)
    await snapshot_store.insert(sample_status(odometer=2), vehicle_id="vehicle-1")
    await asyncio.sleep(0.001)
    await snapshot_store.insert(sample_status(odometer=3), vehicle_id="vehicle-1")

    all_rows, _ = await snapshot_store.query()
    rows, has_more = await snapshot_store.query(
        from_dt=datetime.fromisoformat(all_rows[1]["timestamp"]),
        to_dt=datetime.fromisoformat(all_rows[2]["timestamp"]),
        limit=1,
    )

    assert has_more is True
    assert [row["odometer_km"] for row in rows] == [2]


def test_get_snapshots_returns_ascending_and_respects_filters(
    client: TestClient,
    auth_headers: dict[str, str],
) -> None:
    store = client.app.state.snapshot_store
    asyncio.run(store.insert(sample_status(odometer=1), vehicle_id="vehicle-1"))
    time.sleep(0.001)
    asyncio.run(store.insert(sample_status(odometer=2), vehicle_id="vehicle-1"))
    time.sleep(0.001)
    asyncio.run(store.insert(sample_status(odometer=3), vehicle_id="vehicle-1"))

    all_rows, _ = asyncio.run(store.query())
    response = client.get(
        "/snapshots",
        headers=auth_headers,
        params={
            "from": all_rows[0]["timestamp"],
            "to": all_rows[2]["timestamp"],
            "limit": 2,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["has_more"] is True
    assert [row["odometer_km"] for row in payload["snapshots"]] == [1, 2]


def test_get_latest_snapshot_returns_latest(
    client: TestClient,
    auth_headers: dict[str, str],
) -> None:
    store = client.app.state.snapshot_store
    asyncio.run(store.insert(sample_status(odometer=1), vehicle_id="vehicle-1"))
    asyncio.run(store.insert(sample_status(odometer=2), vehicle_id="vehicle-1"))

    response = client.get("/snapshots/latest", headers=auth_headers)

    assert response.status_code == 200
    assert response.json()["odometer_km"] == 2


def test_get_latest_snapshot_404_if_empty(
    client: TestClient,
    auth_headers: dict[str, str],
) -> None:
    response = client.get("/snapshots/latest", headers=auth_headers)

    assert response.status_code == 404
    assert response.json()["detail"] == "no snapshots yet"


def test_snapshot_endpoints_require_auth(client: TestClient) -> None:
    snapshots_response = client.get("/snapshots")
    latest_response = client.get("/snapshots/latest")

    assert snapshots_response.status_code == 401
    assert latest_response.status_code == 401


async def test_collector_loop_inserts_one_cached_status(
    snapshot_store: SnapshotStore,
) -> None:
    class FakeCollectorCarService:
        def get_status(self, force: bool = False) -> dict:
            assert force is False
            return sample_status()

    task = asyncio.create_task(
        run_collector_loop(
            snapshot_store,
            FakeCollectorCarService(),
            interval_seconds=60,
        )
    )
    try:
        for _ in range(20):
            latest = await snapshot_store.latest()
            if latest is not None:
                break
            await asyncio.sleep(0.01)
        assert latest is not None
        assert latest["vehicle_id"] == "vehicle-1"
    finally:
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task


async def test_collector_loop_backs_off_on_consecutive_failures(
    snapshot_store: SnapshotStore,
) -> None:
    class FailingCollectorCarService:
        def get_status(self, force: bool = False) -> dict:
            assert force is False
            raise RuntimeError("upstream wedged")

    sleeps: list[float] = []

    async def recording_sleep(duration: float) -> None:
        sleeps.append(duration)
        if len(sleeps) >= 5:
            raise asyncio.CancelledError

    task = asyncio.create_task(
        run_collector_loop(
            snapshot_store,
            FailingCollectorCarService(),
            interval_seconds=10,
            max_consecutive_failures_before_reauth=999,
            max_backoff_seconds=1000,
            sleep=recording_sleep,
        )
    )

    with pytest.raises(asyncio.CancelledError):
        await task

    assert sleeps == [10, 20, 40, 80, 160]


async def test_collector_loop_caps_backoff_at_max(
    snapshot_store: SnapshotStore,
) -> None:
    class FailingCollectorCarService:
        def get_status(self, force: bool = False) -> dict:
            assert force is False
            raise RuntimeError("upstream wedged")

    sleeps: list[float] = []

    async def recording_sleep(duration: float) -> None:
        sleeps.append(duration)
        if len(sleeps) >= 5:
            raise asyncio.CancelledError

    task = asyncio.create_task(
        run_collector_loop(
            snapshot_store,
            FailingCollectorCarService(),
            interval_seconds=100,
            max_consecutive_failures_before_reauth=999,
            max_backoff_seconds=300,
            sleep=recording_sleep,
        )
    )

    with pytest.raises(asyncio.CancelledError):
        await task

    assert sleeps == [100, 200, 300, 300, 300]


async def test_collector_loop_triggers_reauth_after_threshold_and_resets_counter(
    snapshot_store: SnapshotStore,
) -> None:
    class ReauthingCollectorCarService:
        def __init__(self) -> None:
            self.get_status_calls = 0
            self.force_reauth_calls = 0

        def get_status(self, force: bool = False) -> dict:
            assert force is False
            self.get_status_calls += 1
            if self.get_status_calls <= 3:
                raise RuntimeError("upstream wedged")
            return sample_status()

        def force_reauth(self) -> None:
            self.force_reauth_calls += 1

    car_service = ReauthingCollectorCarService()
    sleeps: list[float] = []

    async def recording_sleep(duration: float) -> None:
        sleeps.append(duration)
        if len(sleeps) >= 4:
            raise asyncio.CancelledError

    task = asyncio.create_task(
        run_collector_loop(
            snapshot_store,
            car_service,
            interval_seconds=10,
            max_consecutive_failures_before_reauth=3,
            max_backoff_seconds=1000,
            sleep=recording_sleep,
        )
    )

    with pytest.raises(asyncio.CancelledError):
        await task

    latest = await snapshot_store.latest()
    assert car_service.force_reauth_calls == 1
    assert sleeps == [10, 20, 10, 10]
    assert latest is not None
    assert latest["vehicle_id"] == "vehicle-1"


async def test_collector_loop_continues_with_backoff_when_reauth_itself_fails(
    snapshot_store: SnapshotStore,
) -> None:
    class FailedReauthCollectorCarService:
        def __init__(self) -> None:
            self.force_reauth_calls = 0

        def get_status(self, force: bool = False) -> dict:
            assert force is False
            raise RuntimeError("upstream wedged")

        def force_reauth(self) -> None:
            self.force_reauth_calls += 1
            raise RuntimeError("reauth failed")

    car_service = FailedReauthCollectorCarService()
    sleeps: list[float] = []

    async def recording_sleep(duration: float) -> None:
        sleeps.append(duration)
        if len(sleeps) >= 4:
            raise asyncio.CancelledError

    task = asyncio.create_task(
        run_collector_loop(
            snapshot_store,
            car_service,
            interval_seconds=10,
            max_consecutive_failures_before_reauth=2,
            max_backoff_seconds=1000,
            sleep=recording_sleep,
        )
    )

    with pytest.raises(asyncio.CancelledError):
        await task

    assert car_service.force_reauth_calls == 3
    assert sleeps == [10, 20, 40, 80]
