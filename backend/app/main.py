"""FastAPI application entrypoint."""

from __future__ import annotations

import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request

from .car import CarService
from .config import Settings
from .rate_limit import FixedWindowRateLimiter
from .routes.commands import router as commands_router
from .routes.health import router as health_router
from .routes.snapshots import router as snapshots_router
from .routes.status import router as status_router
from .routes.trips import router as trips_router
from .routes.vehicle import router as vehicle_router
from .snapshots import SnapshotStore, run_collector_loop

logger = logging.getLogger(__name__)


def get_car_service(request: Request) -> CarService:
    return request.app.state.car


def create_app(
    car_service: CarService | None = None,
    settings: Settings | None = None,
) -> FastAPI:
    from .cf_patch import apply as _apply_cf_patch

    _apply_cf_patch()
    resolved_settings = settings or Settings()
    collector_should_run = car_service is None

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = resolved_settings
        app.state.command_rate_limiter = FixedWindowRateLimiter(
            limit=resolved_settings.command_rate_limit_per_minute,
            window_seconds=resolved_settings.command_rate_limit_window_seconds,
        )
        if car_service is not None:
            app.state.car = car_service
        else:
            try:
                service = await asyncio.to_thread(CarService, resolved_settings)
                await asyncio.to_thread(service.initialize)
                app.state.car = service
            except Exception as exc:
                logger.exception("backend startup failed: %s", exc.__class__.__name__)
                raise

        store = SnapshotStore(path=resolved_settings.snapshot_db_path)
        await store.initialize()
        app.state.snapshot_store = store
        task = None
        if collector_should_run:
            task = asyncio.create_task(
                run_collector_loop(
                    store,
                    app.state.car,
                    interval_seconds=resolved_settings.snapshot_interval_seconds,
                )
            )
        app.state.snapshot_task = task
        try:
            yield
        finally:
            if task is not None:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
            await store.close()

    app = FastAPI(
        title="Hyundai Companion Backend",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.include_router(health_router)
    app.include_router(vehicle_router)
    app.include_router(status_router)
    app.include_router(snapshots_router)
    app.include_router(commands_router)
    app.include_router(trips_router)
    return app


app = create_app()
