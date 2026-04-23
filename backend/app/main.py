"""FastAPI application entrypoint."""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request

from .car import CarService
from .config import Settings
from .rate_limit import FixedWindowRateLimiter
from .routes.commands import router as commands_router
from .routes.health import router as health_router
from .routes.status import router as status_router
from .routes.trips import router as trips_router
from .routes.vehicle import router as vehicle_router

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

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = resolved_settings
        app.state.command_rate_limiter = FixedWindowRateLimiter(
            limit=resolved_settings.command_rate_limit_per_minute,
            window_seconds=resolved_settings.command_rate_limit_window_seconds,
        )
        if car_service is not None:
            app.state.car = car_service
            yield
            return

        try:
            service = await asyncio.to_thread(CarService, resolved_settings)
            await asyncio.to_thread(service.initialize)
            app.state.car = service
        except Exception as exc:
            logger.exception("backend startup failed: %s", exc.__class__.__name__)
            raise

        yield

    app = FastAPI(
        title="Hyundai Companion Backend",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.include_router(health_router)
    app.include_router(vehicle_router)
    app.include_router(status_router)
    app.include_router(commands_router)
    app.include_router(trips_router)
    return app


app = create_app()
