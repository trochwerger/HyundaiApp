"""Vehicle service wrapper around hyundai_kia_connect_api."""

from __future__ import annotations

import dataclasses
import datetime as dt
import logging
import math
from collections.abc import Mapping
from datetime import timezone
from typing import Any

from fastapi import HTTPException, status
from hyundai_kia_connect_api import ClimateRequestOptions, VehicleManager
from hyundai_kia_connect_api.const import BRANDS, REGIONS

from .config import Settings

logger = logging.getLogger(__name__)

REGION_NAME_TO_ID = {name.lower(): value for value, name in REGIONS.items()}
BRAND_NAME_TO_ID = {name.lower(): value for value, name in BRANDS.items()}


class CarService:
    """Small application service for a single Hyundai/Kia account."""

    def __init__(self, settings: Settings):
        self._settings = settings
        self._vehicle_manager = VehicleManager(
            region=self._resolve_region_id(settings.region),
            brand=self._resolve_brand_id(settings.brand),
            username=settings.bluelink_email,
            password=settings.bluelink_password.get_secret_value(),
            pin=settings.bluelink_pin.get_secret_value(),
        )
        self._vehicle_id: str | None = None
        self._last_force_refresh_at: dt.datetime | None = None

    def initialize(self) -> None:
        """Log in once on startup and fetch an initial cached snapshot."""

        had_token = self._vehicle_manager.token is not None
        refreshed = self._vehicle_manager.check_and_refresh_token()
        if refreshed:
            logger.info("token refreshed" if had_token else "logged in")

        self._vehicle_manager.update_all_vehicles_with_cached_state()
        self._vehicle_id = self._select_vehicle_id()

    def force_reauth(self) -> None:
        """Drop the cached session and log in again from configured credentials."""

        logger.info("forcing reauth")
        self._vehicle_manager.token = None
        self._vehicle_manager.check_and_refresh_token()
        self._vehicle_manager.update_all_vehicles_with_cached_state()
        self._vehicle_id = None
        self._vehicle_id = self._select_vehicle_id()
        logger.info("reauth complete")

    def get_vehicle_metadata(self) -> dict[str, Any]:
        vehicle = self._get_vehicle()
        return self._prune_none(
            {
                "id": getattr(vehicle, "id", None),
                "name": getattr(vehicle, "name", None),
                "model": getattr(vehicle, "model", None),
                "year": getattr(vehicle, "year", None),
                "vin": getattr(vehicle, "VIN", None),
                "registration_date": getattr(vehicle, "registration_date", None),
                "engine_type": self._json_safe(getattr(vehicle, "engine_type", None)),
            }
        )

    def get_status(self, force: bool = False) -> dict[str, Any]:
        if force:
            retry_after_seconds = self._retry_after_seconds()
            if retry_after_seconds is not None:
                logger.info("force refresh: denied")
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail={
                        "error": "rate_limited",
                        "retry_after_seconds": retry_after_seconds,
                    },
                    headers={"Retry-After": str(retry_after_seconds)},
                )

            logger.info("force refresh: allowed")
            self._vehicle_manager.force_refresh_all_vehicles_states()
            self._last_force_refresh_at = dt.datetime.now(timezone.utc)
        else:
            self._vehicle_manager.update_all_vehicles_with_cached_state()

        return self._serialize_vehicle(self._get_vehicle())

    def lock(self) -> dict[str, Any]:
        return self._run_command("lock")

    def unlock(self) -> dict[str, Any]:
        return self._run_command("unlock")

    def start_climate(
        self,
        temp: float | None,
        defrost: bool | None,
        duration: int | None,
    ) -> dict[str, Any]:
        options = ClimateRequestOptions(
            set_temp=temp,
            duration=duration,
            defrost=defrost,
        )
        return self._run_command(
            "start_climate",
            "start",
            options,
        )

    def stop_climate(self) -> dict[str, Any]:
        return self._run_command("stop_climate", "stop")

    def start_charge(self) -> dict[str, Any]:
        return self._run_command("start_charge", "charge-start")

    def stop_charge(self) -> dict[str, Any]:
        return self._run_command("stop_charge", "charge-stop")

    def get_trips(self, from_date: dt.date, to_date: dt.date) -> dict[str, Any]:
        vehicle_id = self._get_vehicle_id()

        if hasattr(self._vehicle_manager, "update_month_trip_info"):
            months = []
            current = from_date.replace(day=1)
            final = to_date.replace(day=1)
            while current <= final:
                yyyymm = current.strftime("%Y%m")
                self._vehicle_manager.update_month_trip_info(vehicle_id, yyyymm)
                vehicle = self._vehicle_manager.get_vehicle(vehicle_id)
                months.append(
                    self._prune_none(
                        {
                            "month": yyyymm,
                            "data": self._json_safe(
                                getattr(vehicle, "month_trip_info", None)
                            ),
                        }
                    )
                )
                current = self._next_month(current)

            return self._prune_none(
                {
                    "from": from_date,
                    "to": to_date,
                    "months": months,
                }
            )

        if hasattr(self._vehicle_manager, "update_day_trip_info"):
            days = []
            current = from_date
            while current <= to_date:
                yyyymmdd = current.strftime("%Y%m%d")
                self._vehicle_manager.update_day_trip_info(vehicle_id, yyyymmdd)
                vehicle = self._vehicle_manager.get_vehicle(vehicle_id)
                days.append(
                    self._prune_none(
                        {
                            "date": current,
                            "data": self._json_safe(
                                getattr(vehicle, "day_trip_info", None)
                            ),
                        }
                    )
                )
                current += dt.timedelta(days=1)

            return self._prune_none(
                {
                    "from": from_date,
                    "to": to_date,
                    "days": days,
                }
            )

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={
                "error": "upstream_method_missing",
                "message": (
                    "VehicleManager exposes neither update_month_trip_info nor "
                    "update_day_trip_info"
                ),
            },
        )

    def _resolve_region_id(self, region: str) -> int:
        region_id = REGION_NAME_TO_ID.get(region.lower())
        if region_id is None:
            raise ValueError(f"unsupported region: {region}")
        return region_id

    def _resolve_brand_id(self, brand: str) -> int:
        brand_id = BRAND_NAME_TO_ID.get(brand.lower())
        if brand_id is None:
            raise ValueError(f"unsupported brand: {brand}")
        return brand_id

    def _select_vehicle_id(self) -> str:
        if not self._vehicle_manager.vehicles:
            raise RuntimeError("no vehicles available for configured account")
        return next(iter(self._vehicle_manager.vehicles))

    def _get_vehicle_id(self) -> str:
        vehicle_id = self._vehicle_id or self._select_vehicle_id()
        self._vehicle_id = vehicle_id
        return vehicle_id

    def _get_vehicle(self) -> Any:
        return self._vehicle_manager.get_vehicle(self._get_vehicle_id())

    def _run_command(
        self,
        method_name: str,
        command: str | None = None,
        *args: Any,
    ) -> dict[str, Any]:
        command_name = command or method_name
        method = getattr(self._vehicle_manager, method_name, None)
        if method is None:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail={
                    "error": "upstream_method_missing",
                    "command": command_name,
                    "message": f"VehicleManager.{method_name} is unavailable",
                    "type": "AttributeError",
                },
            )

        try:
            result = method(self._get_vehicle_id(), *args)
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail={
                    "error": "upstream_error",
                    "command": command_name,
                    "message": str(exc),
                    "type": exc.__class__.__name__,
                },
            ) from exc

        response: dict[str, Any] = {"ok": True, "command": command_name}
        if result is not None:
            response["result"] = self._json_safe(result)
        return self._prune_none(response)

    def _next_month(self, value: dt.date) -> dt.date:
        if value.month == 12:
            return value.replace(year=value.year + 1, month=1)
        return value.replace(month=value.month + 1)

    def _retry_after_seconds(self) -> int | None:
        if self._last_force_refresh_at is None:
            return None

        now = dt.datetime.now(timezone.utc)
        elapsed = (now - self._last_force_refresh_at).total_seconds()
        min_interval = self._settings.force_refresh_min_interval_seconds
        if elapsed >= min_interval:
            return None
        return max(1, math.ceil(min_interval - elapsed))

    def _serialize_vehicle(self, vehicle: Any) -> dict[str, Any]:
        if dataclasses.is_dataclass(vehicle):
            raw = dataclasses.asdict(vehicle)
            data = {
                key: value
                for key, value in raw.items()
                if not key.startswith("_") and key not in {"key", "data"}
            }
        elif isinstance(vehicle, Mapping):
            data = dict(vehicle)
        else:
            data = {
                "id": getattr(vehicle, "id", None),
                "name": getattr(vehicle, "name", None),
                "model": getattr(vehicle, "model", None),
                "year": getattr(vehicle, "year", None),
                "vin": getattr(vehicle, "VIN", None),
            }

        if "VIN" in data:
            data["vin"] = data.pop("VIN")

        data.update(
            self._prune_none(
                {
                    "last_updated_at": getattr(vehicle, "last_updated_at", None),
                    "total_driving_range": getattr(vehicle, "total_driving_range", None),
                    "total_driving_range_unit": getattr(
                        vehicle, "total_driving_range_unit", None
                    ),
                    "odometer": getattr(vehicle, "odometer", None),
                    "odometer_unit": getattr(vehicle, "odometer_unit", None),
                    "outside_temperature": getattr(vehicle, "outside_temperature", None),
                    "outside_temperature_unit": getattr(
                        vehicle, "_outside_temperature_unit", None
                    ),
                    "air_temperature": getattr(vehicle, "air_temperature", None),
                    "air_temperature_unit": getattr(
                        vehicle, "_air_temperature_unit", None
                    ),
                    "next_service_distance": getattr(
                        vehicle, "next_service_distance", None
                    ),
                    "next_service_distance_unit": getattr(
                        vehicle, "_next_service_distance_unit", None
                    ),
                    "last_service_distance": getattr(
                        vehicle, "last_service_distance", None
                    ),
                    "last_service_distance_unit": getattr(
                        vehicle, "_last_service_distance_unit", None
                    ),
                    "ev_driving_range": getattr(vehicle, "ev_driving_range", None),
                    "ev_driving_range_unit": getattr(
                        vehicle, "_ev_driving_range_unit", None
                    ),
                    "fuel_driving_range": getattr(vehicle, "fuel_driving_range", None),
                    "fuel_driving_range_unit": getattr(
                        vehicle, "_fuel_driving_range_unit", None
                    ),
                    "location": self._build_location(vehicle),
                }
            )
        )

        return self._prune_none(self._json_safe(data))

    def _build_location(self, vehicle: Any) -> dict[str, Any] | None:
        location = self._prune_none(
            {
                "latitude": getattr(vehicle, "location_latitude", None),
                "longitude": getattr(vehicle, "location_longitude", None),
                "last_updated_at": getattr(vehicle, "location_last_updated_at", None),
            }
        )
        if not location:
            return None
        return location

    def _json_safe(self, value: Any) -> Any:
        if dataclasses.is_dataclass(value):
            return self._json_safe(dataclasses.asdict(value))
        if isinstance(value, Mapping):
            return {key: self._json_safe(item) for key, item in value.items()}
        if hasattr(value, "model_dump"):
            return self._json_safe(value.model_dump())
        if isinstance(value, list):
            return [self._json_safe(item) for item in value]
        if isinstance(value, tuple):
            return [self._json_safe(item) for item in value]
        if isinstance(value, dt.datetime):
            return value.isoformat()
        if isinstance(value, dt.date):
            return value.isoformat()
        if isinstance(value, dt.time):
            return value.isoformat()
        if isinstance(value, dt.tzinfo):
            return str(value)
        if hasattr(value, "value"):
            return value.value
        return value

    def _prune_none(self, value: Any) -> Any:
        if isinstance(value, dict):
            cleaned = {
                key: self._prune_none(item)
                for key, item in value.items()
                if item is not None
            }
            return {key: item for key, item in cleaned.items() if item not in ({}, [])}
        if isinstance(value, list):
            cleaned = [self._prune_none(item) for item in value if item is not None]
            return [item for item in cleaned if item not in ({}, [])]
        return value
