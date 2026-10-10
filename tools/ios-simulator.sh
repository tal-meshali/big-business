#!/bin/sh
# Exports the iOS preset as an Xcode project, builds it for the simulator and
# opens it on the "BB iPhone 16 (iOS 18)" simulator against the local Nakama.
# Godot 4.6.3's simulator library is x86_64 only and iOS 26 simulators no longer
# run x86_64 apps, so this needs the iOS 18 runtime:
#   xcodebuild -downloadPlatform iOS -buildVersion 18.6
set -eu
# The build output goes to build/ios-simulator: the exported project searches
# everything under build/ios for libraries, so simulator files there break the
# phone build.
cd "$(dirname "$0")/.."
sim="BB iPhone 16 (iOS 18)"
tools/ios-export.sh
cd build/ios
xcodebuild -quiet -project BigBusiness.xcodeproj -scheme BigBusiness -configuration Debug \
  -sdk iphonesimulator ONLY_ACTIVE_ARCH=NO -derivedDataPath ../ios-simulator CODE_SIGNING_ALLOWED=NO build
if ! xcrun simctl list devices | grep -q "$sim"; then
  xcrun simctl create "$sim" "iPhone 16" com.apple.CoreSimulator.SimRuntime.iOS-18-6
fi
xcrun simctl boot "$sim" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$sim" >/dev/null
xcrun simctl install "$sim" ../ios-simulator/Build/Products/Debug-iphonesimulator/BigBusiness.app
xcrun simctl launch "$sim" com.talmeshali.bigbusiness
