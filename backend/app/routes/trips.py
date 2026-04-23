"""Trip history route."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from app.auth import require_api_key

router = APIRouter(dependencies=[Depends(require_api_key)])


def get_car_service(request: Request):
    return request.app.state.car


@router.get("/trips")
def get_trips(
    from_date: dt.date = Query(..., alias="from"),
    to_date: dt.date = Query(..., alias="to"),
    car_service=Depends(get_car_service),
) -> dict:
    if from_date > to_date:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "invalid_range", "message": "from must be before to"},
        )

    if (to_date - from_date).days > 92:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": "range_too_large",
                "message": "trip range must be 92 days or less",
            },
        )

    return car_service.get_trips(from_date, to_date)
