"""Snapshot persistence and collector loop."""

from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


class SnapshotStore:
    """SQLite-backed vehicle status snapshot store."""

    def __init__(self, path: str) -> None:
        self._path = path
        self._conn: sqlite3.Connection | None = None
        self._lock = threading.Lock()

    async def initialize(self) -> None:
        await asyncio.to_thread(self._initialize_sync)

    async def insert(self, status: dict, *, vehicle_id: str | None) -> bool:
        return await asyncio.to_thread(self._insert_sync, status, vehicle_id)

    async def latest(self, vehicle_id: str | None = None) -> dict | None:
        return await asyncio.to_thread(self._latest_sync, vehicle_id)

    async def query(
        self,
        *,
        from_dt: datetime | None = None,
        to_dt: datetime | None = None,
        limit: int = 1000,
        vehicle_id: str | None = None,
    ) -> tuple[list[dict], bool]:
        return await asyncio.to_thread(
            self._query_sync,
            from_dt,
            to_dt,
            limit,
            vehicle_id,
        )

    async def close(self) -> None:
        await asyncio.to_thread(self._close_sync)

    def _initialize_sync(self) -> None:
        if self._path != ":memory:":
            Path(self._path).parent.mkdir(parents=True, exist_ok=True)

        with self._lock:
            self._conn = sqlite3.connect(self._path, check_same_thread=False)
            self._conn.row_factory = sqlite3.Row
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.execute(
                """
                CREATE TABLE IF NOT EXISTS snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    vehicle_id TEXT,
                    status_json TEXT NOT NULL,
                    odometer_km REAL,
                    fuel_percent INTEGER,
                    ev_battery_percent INTEGER,
                    is_locked INTEGER,
                    is_charging INTEGER,
                    engine_is_running INTEGER,
                    latitude REAL,
                    longitude REAL
                )
                """
            )
            self._conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp "
                "ON snapshots(timestamp)"
            )
            self._conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_snapshots_vehicle_timestamp "
                "ON snapshots(vehicle_id, timestamp)"
            )
            self._conn.commit()

    def _insert_sync(self, status: dict, vehicle_id: str | None) -> bool:
        conn = self._require_conn()
        values = self._extract_columns(status)

        with self._lock:
            latest = self._latest_row_sync(vehicle_id)
            if latest is not None and self._matches_dedup_fields(latest, values):
                return False

            conn.execute(
                """
                INSERT INTO snapshots (
                    timestamp,
                    vehicle_id,
                    status_json,
                    odometer_km,
                    fuel_percent,
                    ev_battery_percent,
                    is_locked,
                    is_charging,
                    engine_is_running,
                    latitude,
                    longitude
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    datetime.now(timezone.utc).isoformat(),
                    vehicle_id,
                    json.dumps(status, sort_keys=True, default=str),
                    values["odometer_km"],
                    values["fuel_percent"],
                    values["ev_battery_percent"],
                    values["is_locked"],
                    values["is_charging"],
                    values["engine_is_running"],
                    values["latitude"],
                    values["longitude"],
                ),
            )
            conn.commit()
            return True

    def _latest_sync(self, vehicle_id: str | None = None) -> dict | None:
        with self._lock:
            row = self._latest_row_sync(
                vehicle_id=vehicle_id,
                filter_vehicle=vehicle_id is not None,
            )
            return self._row_to_dict(row) if row is not None else None

    def _query_sync(
        self,
        from_dt: datetime | None,
        to_dt: datetime | None,
        limit: int,
        vehicle_id: str | None,
    ) -> tuple[list[dict], bool]:
        conn = self._require_conn()
        clauses: list[str] = []
        params: list[Any] = []

        if vehicle_id is not None:
            clauses.append("vehicle_id = ?")
            params.append(vehicle_id)
        if from_dt is not None:
            clauses.append("timestamp >= ?")
            params.append(from_dt.isoformat())
        if to_dt is not None:
            clauses.append("timestamp <= ?")
            params.append(to_dt.isoformat())

        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        params.append(limit + 1)

        with self._lock:
            rows = conn.execute(
                f"""
                SELECT *
                FROM snapshots
                {where}
                ORDER BY timestamp ASC, id ASC
                LIMIT ?
                """,
                params,
            ).fetchall()

        has_more = len(rows) > limit
        trimmed = rows[:limit]
        return [self._row_to_dict(row) for row in trimmed], has_more

    def _close_sync(self) -> None:
        with self._lock:
            if self._conn is not None:
                self._conn.close()
                self._conn = None

    def _latest_row_sync(
        self,
        vehicle_id: str | None,
        *,
        filter_vehicle: bool = True,
    ) -> sqlite3.Row | None:
        conn = self._require_conn()
        if not filter_vehicle:
            return conn.execute(
                """
                SELECT *
                FROM snapshots
                ORDER BY timestamp DESC, id DESC
                LIMIT 1
                """
            ).fetchone()

        if vehicle_id is None:
            return conn.execute(
                """
                SELECT *
                FROM snapshots
                WHERE vehicle_id IS NULL
                ORDER BY timestamp DESC, id DESC
                LIMIT 1
                """
            ).fetchone()

        return conn.execute(
            """
            SELECT *
            FROM snapshots
            WHERE vehicle_id = ?
            ORDER BY timestamp DESC, id DESC
            LIMIT 1
            """,
            (vehicle_id,),
        ).fetchone()

    def _require_conn(self) -> sqlite3.Connection:
        if self._conn is None:
            raise RuntimeError("snapshot store is not initialized")
        return self._conn

    def _row_to_dict(self, row: sqlite3.Row) -> dict:
        data = dict(row)
        data["status"] = json.loads(data.pop("status_json"))
        return data

    def _extract_columns(self, status: dict) -> dict[str, Any]:
        location = status.get("location") or {}
        if not isinstance(location, dict):
            location = {}

        return {
            "odometer_km": status.get("odometer"),
            "fuel_percent": status.get("fuel_level"),
            "ev_battery_percent": status.get("ev_battery_percentage"),
            "is_locked": self._coerce_bool(
                status.get("is_locked")
                if "is_locked" in status
                else status.get("door_is_locked")
            ),
            "is_charging": self._coerce_bool(status.get("ev_battery_is_charging")),
            "engine_is_running": self._coerce_bool(status.get("engine_is_running")),
            "latitude": location.get("latitude"),
            "longitude": location.get("longitude"),
        }

    def _matches_dedup_fields(
        self,
        latest: sqlite3.Row,
        values: dict[str, Any],
    ) -> bool:
        return all(
            latest[key] == values[key]
            for key in (
                "odometer_km",
                "ev_battery_percent",
                "fuel_percent",
                "is_locked",
            )
        )

    def _coerce_bool(self, value: Any) -> int | None:
        if value is None:
            return None
        return 1 if bool(value) else 0


async def run_collector_loop(
    store: SnapshotStore,
    car_service: Any,
    *,
    interval_seconds: int,
) -> None:
    while True:
        try:
            status = await asyncio.to_thread(car_service.get_status, False)
            vehicle_id = status.get("id") if isinstance(status, dict) else None
            inserted = await store.insert(status, vehicle_id=vehicle_id)
            logger.info(
                "snapshot collected" if inserted else "snapshot skipped (no change)"
            )
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("snapshot collection failed; will retry next cycle")
        await asyncio.sleep(interval_seconds)
