"""Vehicle snapshot routes."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from app.auth import require_api_key
from app.snapshots import SnapshotStore

router = APIRouter(dependencies=[Depends(require_api_key)])


def get_store(request: Request) -> SnapshotStore:
    return request.app.state.snapshot_store


@router.get("/snapshots")
async def get_snapshots(
    from_: datetime | None = Query(None, alias="from"),
    to: datetime | None = None,
    limit: int = Query(1000, ge=1, le=5000),
    store: SnapshotStore = Depends(get_store),
) -> dict:
    snapshots, has_more = await store.query(
        from_dt=from_,
        to_dt=to,
        limit=limit,
    )
    return {"snapshots": snapshots, "has_more": has_more}


@router.get("/snapshots/latest")
async def get_latest_snapshot(
    store: SnapshotStore = Depends(get_store),
) -> dict:
    latest = await store.latest()
    if latest is None:
        raise HTTPException(status_code=404, detail="no snapshots yet")
    return latest
