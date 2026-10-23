#!/usr/bin/env python3

import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: verify_app_icon.py APP_PATH GENERATED_ICNS")

    app_path = Path(sys.argv[1]).resolve()
    generated_icon = Path(sys.argv[2]).resolve()
    plist_path = app_path / "Contents/Info.plist"
    packaged_icon = app_path / "Contents/Resources/FlightLog.icns"

    with plist_path.open("rb") as plist_file:
        info = plistlib.load(plist_file)
    if info.get("CFBundleIconFile") != "FlightLog.icns":
        raise SystemExit("Info.plist 的 CFBundleIconFile 不正确")
    if not packaged_icon.is_file():
        raise SystemExit("app 缺少 Contents/Resources/FlightLog.icns")
    if sha256(packaged_icon) != sha256(generated_icon):
        raise SystemExit("app 内图标与生成图标的 SHA256 不一致")

    subprocess.run(
        [
            "codesign",
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            str(app_path),
        ],
        check=True,
    )
    print(f"App 图标验证通过：sha256={sha256(packaged_icon)}")


if __name__ == "__main__":
    main()
