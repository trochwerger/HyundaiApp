"""Vehicle metadata route."""

from fastapi import APIRouter, Depends, Request

from app.auth import require_api_key

router = APIRouter(dependencies=[Depends(require_api_key)])


def get_car_service(request: Request):
    return request.app.state.car


@router.get("/vehicle")
def get_vehicle(car_service=Depends(get_car_service)) -> dict:
    return car_service.get_vehicle_metadata()
