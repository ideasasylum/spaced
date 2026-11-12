#!/bin/sh
# Builds a release Spaced.app into build/, with the CLI at Contents/Helpers/spaced.
set -eu

cd "$(dirname "$0")/.."

swift build -c release --product SpacedApp
swift build -c release --product SpacedCLI
bin="$(swift build -c release --show-bin-path)"

app="build/Spaced.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin/SpacedApp" "$app/Contents/MacOS/Spaced"
cp "$bin/SpacedCLI" "$app/Contents/Helpers/spaced"
if [ -f Resources/AppIcon.icns ]; then
	cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$app/Contents/Helpers/spaced"
codesign --force --sign - "$app"
echo "Built $app"
