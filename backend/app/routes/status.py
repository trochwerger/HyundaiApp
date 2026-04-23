"""Vehicle status route."""

from fastapi import APIRouter, Depends, Request

from app.auth import require_api_key

router = APIRouter(dependencies=[Depends(require_api_key)])


def get_car_service(request: Request):
    return request.app.state.car


@router.get("/status")
def get_status(
    force: bool = False,
    car_service=Depends(get_car_service),
) -> dict:
    return car_service.get_status(force=force)
