#!/usr/bin/env fish
# Generate the project, build it, and launch it on a watchOS simulator.
#
# Usage:
#   ./Scripts/run-sim.fish                       # uses default device below
#   ./Scripts/run-sim.fish "Apple Watch Ultra 3 (49mm)"

set -l device $argv[1]
if test -z "$device"
    set device "Apple Watch Series 11 (46mm)"
end

set -l scriptdir (dirname (status --current-filename))
set -l root (cd $scriptdir/..; and pwd)
cd $root

echo "==> Generating Xcode project"
xcodegen generate; or exit 1

echo "==> Building for '$device'"
xcodebuild -project WaterLogged.xcodeproj -scheme WaterLogged \
    -destination "platform=watchOS Simulator,name=$device" \
    -configuration Debug build \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO; or exit 1

set -l app_path (xcodebuild -project WaterLogged.xcodeproj -scheme WaterLogged \
    -destination "platform=watchOS Simulator,name=$device" \
    -configuration Debug -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')

echo "==> Booting simulator"
xcrun simctl boot "$device" 2>/dev/null
open -a Simulator
xcrun simctl bootstatus "$device"

echo "==> Installing $app_path"
xcrun simctl install "$device" "$app_path"; or exit 1

echo "==> Launching"
xcrun simctl launch "$device" com.tbremer.waterlogged
echo "Done. The app is running in the Simulator."
