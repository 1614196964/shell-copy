#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local --configuration release
binary_dir=$(swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local --configuration release --show-bin-path)
app="$PWD/build/Shell Copy.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/ShellCopy" "$app/Contents/MacOS/ShellCopy"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ShellCopy</string>
  <key>CFBundleIdentifier</key><string>local.shell-copy.app</string>
  <key>CFBundleName</key><string>Shell Copy</string>
  <key>CFBundleDisplayName</key><string>Shell Copy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built $app"
