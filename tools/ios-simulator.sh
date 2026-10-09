#!/bin/sh
# Exports the iOS preset as an Xcode project, builds it for the simulator and
# opens it on the "BB iPhone 16 (iOS 18)" simulator against the local Nakama.
# Godot 4.6.3's simulator library is x86_64 only and iOS 26 simulators no longer
# run x86_64 apps, so this needs the iOS 18 runtime:
#   xcodebuild -downloadPlatform iOS -buildVersion 18.6
set -eu
cd "$(dirname "$0")/.."
godot=${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}
sim="BB iPhone 16 (iOS 18)"
presets=$PWD/client/export_presets.cfg
# Godot refuses to export without a Team ID; the simulator needs no signing.
cp "$presets" "$presets.bak"
trap 'mv "$presets.bak" "$presets"' EXIT
sed -i '' 's/^application\/app_store_team_id=""/application\/app_store_team_id="SIMULATOR0"/' "$presets"
mkdir -p build/ios
"$godot" --headless --path client --export-debug "iOS" ../build/ios/BigBusiness.ipa
cd build/ios
xcodebuild -quiet -project BigBusiness.xcodeproj -scheme BigBusiness -configuration Debug \
  -sdk iphonesimulator ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO -derivedDataPath dd CODE_SIGNING_ALLOWED=NO build
if ! xcrun simctl list devices | grep -q "$sim"; then
  xcrun simctl create "$sim" "iPhone 16" com.apple.CoreSimulator.SimRuntime.iOS-18-6
fi
xcrun simctl boot "$sim" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$sim" >/dev/null
xcrun simctl install "$sim" dd/Build/Products/Debug-iphonesimulator/BigBusiness.app
xcrun simctl launch "$sim" com.talmeshali.bigbusiness
