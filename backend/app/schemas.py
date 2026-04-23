"""Request schemas."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class ClimateCommand(BaseModel):
    temp: float | None = Field(default=None, ge=17, le=27)
    defrost: bool | None = None
    duration: int | None = Field(default=None, ge=1, le=30)

    model_config = ConfigDict(extra="forbid")
