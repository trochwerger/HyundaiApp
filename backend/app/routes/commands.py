"""Vehicle command routes."""

from collections.abc import Callable

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.auth import require_api_key
from app.rate_limit import command_rate_limit
from app.schemas import ClimateCommand

router = APIRouter(
    prefix="/command",
    dependencies=[Depends(require_api_key), Depends(command_rate_limit)],
)


def get_car_service(request: Request):
    return request.app.state.car


def run_command(command: str, call: Callable[[], dict]) -> dict:
    try:
        return call()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={
                "error": "upstream_error",
                "command": command,
                "message": str(exc),
                "type": exc.__class__.__name__,
            },
        ) from exc


@router.post("/lock")
def lock(car_service=Depends(get_car_service)) -> dict:
    return run_command("lock", car_service.lock)


@router.post("/unlock")
def unlock(car_service=Depends(get_car_service)) -> dict:
    return run_command("unlock", car_service.unlock)


@router.post("/start")
def start_climate(
    command: ClimateCommand,
    car_service=Depends(get_car_service),
) -> dict:
    return run_command(
        "start",
        lambda: car_service.start_climate(
            temp=command.temp,
            defrost=command.defrost,
            duration=command.duration,
        ),
    )


@router.post("/stop")
def stop_climate(car_service=Depends(get_car_service)) -> dict:
    return run_command("stop", car_service.stop_climate)


@router.post("/charge-start")
def start_charge(car_service=Depends(get_car_service)) -> dict:
    return run_command("charge-start", car_service.start_charge)


@router.post("/charge-stop")
def stop_charge(car_service=Depends(get_car_service)) -> dict:
    return run_command("charge-stop", car_service.stop_charge)
