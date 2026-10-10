#!/bin/sh
# Builds the "Android emulator" preset, boots the bb_pixel virtual phone if it is
# not running, installs the game and opens it against the local Nakama
# (adb reverse makes the lobby's default 127.0.0.1:7350 reach this Mac).
# One-time setup: docs/TODO-local.md section B.
set -eu
cd "$(dirname "$0")/.."
sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
godot=${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}
adb=$sdk/platform-tools/adb
apk=build/android/big-business-emulator.apk
mkdir -p build/android
"$godot" --headless --path client --export-debug "Android emulator" "../$apk"
if ! "$adb" devices | grep -q '^emulator-'; then
  nohup "$sdk/emulator/emulator" -avd bb_pixel -no-snapshot-save -no-boot-anim >/dev/null 2>&1 &
fi
"$adb" wait-for-device
until [ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
"$adb" install -r "$apk"
"$adb" reverse tcp:7350 tcp:7350
"$adb" shell am start -n com.talmeshali.bigbusiness/com.godot.game.GodotAppLauncher
