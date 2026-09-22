#!/usr/bin/env bash
# Builds AgentWorld.app (the macOS app: workspaces, agents and real
# terminals in one window) and installs it to ~/Applications.
#
#   ./scripts/build-app.sh            build + install
#   ./scripts/build-app.sh --no-install   just build into .build/app/
#
# The bundle is signed ad hoc (fine for your own Mac). Distributing it needs
# a Developer ID signature and notarization.
set -euo pipefail

cd "$(dirname "$0")/.."
version="0.1.0"
build_dir=".build/app"
app="$build_dir/AgentWorld.app"
install_dir="$HOME/Applications"

echo "==> Building (release)"
swift build -c release --product AgentWorldApp
swift build -c release --product agentworld-ctl
bin_dir="$(swift build -c release --show-bin-path)"
binary="$bin_dir/AgentWorldApp"

echo "==> Assembling $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/AgentWorld"
# On PATH in the app's terminals, so agents can drive the app.
cp "$bin_dir/agentworld-ctl" "$app/Contents/MacOS/agentworld-ctl"

echo "==> Drawing the icon"
iconset="$build_dir/AgentWorld.iconset"
rm -rf "$iconset"
"$app/Contents/MacOS/AgentWorld" --render-icon "$iconset"
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$iconset"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AgentWorld</string>
    <key>CFBundleDisplayName</key><string>AgentWorld</string>
    <key>CFBundleIdentifier</key><string>dev.agentworld.app</string>
    <key>CFBundleExecutable</key><string>AgentWorld</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing (ad hoc)"
codesign --force --deep --sign - "$app" >/dev/null

if [[ "${1:-}" == "--no-install" ]]; then
    echo "Built $app"
    exit 0
fi

echo "==> Installing to $install_dir"
mkdir -p "$install_dir"
if pgrep -x AgentWorld >/dev/null; then
    echo "    (AgentWorld is running: quit it to use the new version)"
fi
rm -rf "$install_dir/AgentWorld.app"
cp -R "$app" "$install_dir/"
# So Spotlight and Launchpad open this build (not an older one with the same name).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$install_dir/AgentWorld.app"

echo
echo "Done. Open it from Spotlight or Launchpad (AgentWorld), or run: agentworld app"
