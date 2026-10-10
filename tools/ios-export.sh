#!/bin/sh
# Exports the iOS preset to build/ios/BigBusiness.xcodeproj for Xcode.
# Godot 4.6.3's simulator library is x86_64 only, so simulator builds are made
# x86_64; they run on iOS 18 simulators (iOS 26 ones no longer run x86_64 apps).
# In Xcode, pick your iPhone or "BB iPhone 16 (iOS 18)" (tools/ios-simulator.sh
# creates it), not the iOS 26 simulators.
set -eu
cd "$(dirname "$0")/.."
godot=${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}
mkdir -p build/ios
"$godot" --headless --path client --export-debug "iOS" ../build/ios/BigBusiness.ipa
sed -i '' 's/^\([[:space:]]*\)ARCHS = "arm64";$/\1ARCHS = "arm64";\
\1"ARCHS[sdk=iphonesimulator*]" = x86_64;/' build/ios/BigBusiness.xcodeproj/project.pbxproj
