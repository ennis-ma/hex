#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir="$root/ios/build/unsigned"
output_dir="${1:-$root/dist/ios}"
mkdir -p "$build_dir" "$output_dir"
output_dir=$(cd -- "$output_dir" && pwd)
app_group="${HEX_APP_GROUP:-group.com.kitlangton.hex.mobile}"
build_number="${HEX_IOS_BUILD_NUMBER:-1}"

if [[ ! "$app_group" =~ ^group\.[A-Za-z0-9._-]+$ ]] || [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Set HEX_APP_GROUP to an App Group identifier and HEX_IOS_BUILD_NUMBER to a positive integer." >&2
  exit 1
fi

if [[ "$(uname -s)" != Darwin ]]; then
  echo "The iOS build requires macOS with Xcode 26+ and XcodeGen 2.46.0+." >&2
  exit 1
fi

xcodebuild -version
xcodegen generate --spec "$root/ios/project.yml" --project "$root/ios"
xcodebuild archive \
  -project "$root/ios/HEXMobile.xcodeproj" \
  -scheme HEXMobile \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$build_dir/HEX.xcarchive" \
  -derivedDataPath "$build_dir/DerivedData" \
  -clonedSourcePackagesDirPath "$build_dir/SourcePackages" \
  HEX_APP_GROUP="$app_group" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM=

app="$build_dir/HEX.xcarchive/Products/Applications/HEX.app"
test -d "$app"
for bundle in "$app" "$app/PlugIns/HEXKeyboard.appex" "$app/PlugIns/HEXWidgets.appex"; do
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Info.plist")
  xcrun lipo "$bundle/$executable" -verify_arch arm64
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Info.plist")" = "$build_number"
done
for bundle in "$app" "$app/PlugIns/HEXKeyboard.appex"; do
  test "$(/usr/libexec/PlistBuddy -c 'Print :HexAppGroup' "$bundle/Info.plist")" = "$app_group"
done

# Package the device archive directly; Xcode's export step requires signing.
staging=$(mktemp -d "$build_dir/Payload.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
mkdir "$staging/Payload"
ditto "$app" "$staging/Payload/HEX.app"
ipa="$output_dir/HEX-unsigned.ipa"
ditto -c -k --keepParent "$staging/Payload" "$ipa"
unzip -tq "$ipa"
(
  cd "$output_dir"
  shasum -a 256 HEX-unsigned.ipa > SHA256SUMS
)
echo "Unsigned IPA: $ipa"
