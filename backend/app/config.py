"""Application configuration."""

from __future__ import annotations

from pydantic import SecretStr

try:
    from pydantic_settings import BaseSettings, SettingsConfigDict
except ImportError:  # pragma: no cover - fallback for older environments
    from pydantic import BaseSettings  # type: ignore

    SettingsConfigDict = None  # type: ignore


class Settings(BaseSettings):
    """Environment-backed application settings."""

    bluelink_email: str
    bluelink_password: SecretStr
    bluelink_pin: SecretStr
    api_key: SecretStr
    region: str = "canada"
    brand: str = "hyundai"
    force_refresh_min_interval_seconds: int = 600
    command_rate_limit_per_minute: int = 6
    command_rate_limit_window_seconds: int = 60

    if SettingsConfigDict is not None:
        model_config = SettingsConfigDict(
            env_file=".env",
            env_file_encoding="utf-8",
            extra="ignore",
        )
    else:  # pragma: no cover - pydantic v1 fallback
        class Config:
            env_file = ".env"
            env_file_encoding = "utf-8"
            extra = "ignore"
