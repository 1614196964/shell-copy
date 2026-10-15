#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 || ! -f "$1" ]]; then
  echo "Usage: bash scripts/prepare-release.sh /path/to/release-notes.md" >&2
  exit 2
fi
case "${ALLOW_ADHOC_RELEASE:-0}" in
  1)
    export CODE_SIGN_IDENTITY=-
    echo "WARNING: Preparing an ad-hoc release without Apple notarization. Gatekeeper may block first launch." >&2
    ;;
  0)
    : "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY, or explicitly set ALLOW_ADHOC_RELEASE=1}"
    : "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to your notarytool keychain profile}"
    if [[ "$CODE_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
      echo "Expected Developer ID Application signing, or explicitly set ALLOW_ADHOC_RELEASE=1." >&2
      exit 2
    fi
    ;;
  *) echo "ALLOW_ADHOC_RELEASE must be 0 or 1." >&2; exit 2 ;;
esac
if [[ -n "${RELEASE_CONFIG:-}" ]]; then
  echo "Public releases must use the committed Config/Release.plist." >&2
  exit 2
fi
notes=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Release.plist)
key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Config/Release.plist)
[[ -x "$tools/generate_keys" ]] || { echo "Run bash scripts/check.sh first." >&2; exit 1; }
[[ "$("$tools/generate_keys" --account local.shell-copy.app.sparkle -p)" == "$key" ]] || {
  echo "Signing key does not match Config/Release.plist. Restore the original key; do not silently rotate it." >&2
  exit 1
}
out="$PWD/build/releases/$version"
[[ ! -e "$out" ]] || { echo "Refusing to overwrite existing release directory: $out" >&2; exit 1; }
UNIVERSAL=1 bash scripts/check.sh
app="$PWD/build/Shell Copy.app"
lipo "$app/Contents/MacOS/ShellCopy" -verify_arch arm64 x86_64
mkdir -p "$out"
archive="$out/ShellCopy-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ "${ALLOW_ADHOC_RELEASE:-0}" != 1 ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose "$app"
  # Stapling changes the bundle. Archive again BEFORE generating Sparkle signatures.
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
fi
cp "$notes" "$out/ShellCopy-$version.md"
"$tools/generate_appcast" --account local.shell-copy.app.sparkle \
  --download-url-prefix "https://github.com/doriansu/shell-copy/releases/download/v$version/" \
  --embed-release-notes --maximum-deltas 0 "$out"
python3 scripts/verify-release.py "$out/appcast.xml" "$app" "$archive"
echo "Prepared and verified: $out"
echo "Upload the ZIP and appcast.xml to a draft v$version GitHub Release, then publish both together."
