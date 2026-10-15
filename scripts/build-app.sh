#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
build_args=(--disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local --configuration release)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then build_args+=(--arch arm64 --arch x86_64); fi
swift build "${build_args[@]}"
binary_dir=$(swift build "${build_args[@]}" --show-bin-path)
mkdir -p build
staging=$(mktemp -d "$PWD/build/staging.XXXXXX")
app="$staging/Shell Copy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$binary_dir/ShellCopy" "$app/Contents/MacOS/ShellCopy"
sparkle="$PWD/.build/artifacts/sparkle/Sparkle"
ditto "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ShellCopy</string>
  <key>CFBundleIdentifier</key><string>local.shell-copy.app</string>
  <key>CFBundleName</key><string>Shell Copy</string>
  <key>CFBundleDisplayName</key><string>Shell Copy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - "$app/Contents/Info.plist" "${RELEASE_CONFIG:-Config/Release.plist}" <<'PY'
import base64, plistlib, re, sys
from urllib.parse import urlparse
path, config = sys.argv[1:]
with open(path, 'rb') as f:
    info = plistlib.load(f)
with open(config, 'rb') as f:
    settings = plistlib.load(f)
assert re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', settings['CFBundleShortVersionString']), 'Expected x.y.z version'
assert re.fullmatch(r'[1-9][0-9]*', settings['CFBundleVersion']), 'Expected positive integer build number'
assert len(base64.b64decode(settings['SUPublicEDKey'], validate=True)) == 32, 'Invalid update public key'
url = urlparse(settings['SUFeedURL'])
assert url.scheme == 'https' and url.hostname and not url.username and not url.password, 'HTTPS feed required'
assert settings.get('SUVerifyUpdateBeforeExtraction') is True
assert settings.get('SURequireSignedFeed') is True
assert settings.get('SUAllowsAutomaticUpdates') is False, 'Installation requires user consent'
assert settings.get('SUAutomaticallyUpdate') is False
info.update(settings)
with open(path, 'wb') as f:
    plistlib.dump(info, f)
PY
plutil -lint "$app/Contents/Info.plist"
# Sign nested executables before their containers. Ad-hoc does not establish publisher identity.
identity="${CODE_SIGN_IDENTITY:--}"
sign_args=(--force --sign "$identity")
if [[ "$identity" != - ]]; then sign_args+=(--options runtime --timestamp); fi
framework="$app/Contents/Frameworks/Sparkle.framework"
for service in "$framework"/Versions/B/XPCServices/*.xpc; do
  codesign "${sign_args[@]}" --preserve-metadata=entitlements "$service"
done
codesign "${sign_args[@]}" "$framework/Versions/B/Autoupdate"
codesign "${sign_args[@]}" "$framework/Versions/B/Updater.app"
codesign "${sign_args[@]}" "$framework"
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"
if [[ -e "build/Shell Copy.app" ]]; then
  mv "build/Shell Copy.app" "$staging/Previous Shell Copy.app"
fi
mv "$app" "build/Shell Copy.app"
echo "Built $PWD/build/Shell Copy.app"
