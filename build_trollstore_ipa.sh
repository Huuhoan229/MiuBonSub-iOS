#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT_DIR/ios/App/App.xcodeproj"
DERIVED="$ROOT_DIR/build/DerivedData"
OUT_DIR="$ROOT_DIR/dist"
PAYLOAD="$OUT_DIR/Payload"
APP_PATH="$DERIVED/Build/Products/Release-iphoneos/App.app"
IPA_PATH="$OUT_DIR/MiuBonVietsub-TrollStore.ipa"

rm -rf "$OUT_DIR" "$DERIVED"
mkdir -p "$OUT_DIR"

echo "Installing xcodeproj gem to patch Xcode project..."
gem install xcodeproj --no-document || true
echo "Running update_pbxproj.rb to add new Swift files..."
ruby update_pbxproj.rb

xcodebuild \
  -project "$PROJECT" \
  -scheme App \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Cannot find built app at $APP_PATH" >&2
  exit 1
fi

mkdir -p "$PAYLOAD"
cp -R "$APP_PATH" "$PAYLOAD/"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$PAYLOAD/App.app" || true
fi

(
  cd "$OUT_DIR"
  rm -f "$IPA_PATH"
  zip -qry "$IPA_PATH" Payload
)

echo "IPA ready: $IPA_PATH"
