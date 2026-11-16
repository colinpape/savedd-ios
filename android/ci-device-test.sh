#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/build/reports app/build/outputs/device-screenshots
collect() {
  adb logcat -d -s AndroidRuntime:E > app/build/reports/device-crash.log 2>&1 || true
  adb pull /sdcard/Download/savedd-device-screenshots/. app/build/outputs/device-screenshots/ >/dev/null 2>&1 || true
}
trap collect EXIT
./gradlew connectedDebugAndroidTest --no-daemon --max-workers=2
