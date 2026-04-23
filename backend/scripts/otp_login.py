#!/usr/bin/env python3
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dotenv import load_dotenv
from hyundai_kia_connect_api import VehicleManager
from hyundai_kia_connect_api.const import OTP_NOTIFY_TYPE


def main() -> int:
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if not env_path.exists():
        print(f"Missing {env_path}. Copy backend/.env.example to backend/.env and fill in your credentials.")
        return 1
    load_dotenv(env_path)

    from app.cf_patch import apply as _apply_cf_patch

    _apply_cf_patch()

    required = ["BLUELINK_EMAIL", "BLUELINK_PASSWORD", "BLUELINK_PIN"]
    values = {name: (os.environ.get(name) or "").strip() for name in required}
    missing = [name for name, value in values.items() if not value]
    if missing:
        print(f"Missing required env vars in {env_path}: {', '.join(missing)}")
        return 1

    region_name = (os.environ.get("REGION", "canada") or "canada").strip().lower()
    brand_name = (os.environ.get("BRAND", "hyundai") or "hyundai").strip().lower()
    region = {"canada": 2}.get(region_name)
    brand = {"hyundai": 2}.get(brand_name)
    if region is None or brand is None:
        print(f"Unsupported REGION/BRAND: REGION={region_name!r}, BRAND={brand_name!r}. Expected canada/hyundai.")
        return 1

    try:
        vm = VehicleManager(
            region=region,
            brand=brand,
            username=values["BLUELINK_EMAIL"],
            password=values["BLUELINK_PASSWORD"],
            pin=values["BLUELINK_PIN"],
        )
        result = vm.login()
        if result is True:
            print("Login succeeded without OTP.")
            return 0
        destination = getattr(result, "email", None) or getattr(result, "destination", None) or str(result)
        print(f"OTP destination: {destination}")
        vm.send_otp(OTP_NOTIFY_TYPE.EMAIL)
        otp_code = input("Enter the OTP from Hyundai: ").strip()
        vm.verify_otp_and_complete_login(otp_code)
        print(f"OTP verified. Vehicle IDs: {list(vm.vehicles.keys())}")
        return 0
    except Exception as exc:
        print(f"OTP login failed: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
