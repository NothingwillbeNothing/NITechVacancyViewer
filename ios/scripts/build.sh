#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo "This script requires macOS with Xcode installed." >&2
  exit 1
fi
python3 scripts/generate_project.py
mkdir -p build/artifacts
project=NITechVacancyViewer.xcodeproj
scheme=NITechVacancyViewer

xcodebuild -project "$project" -scheme "$scheme" -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
payload=$(mktemp -d)
trap 'rm -rf "$payload"' EXIT
mkdir -p "$payload/Payload"
cp -R build/device/Build/Products/Release-iphoneos/NITechVacancyViewer.app "$payload/Payload/"
ditto -c -k --sequesterRsrc "$payload" build/artifacts/NITechSearch-unsigned.ipa
python3 - <<'PY'
import plistlib, zipfile
path = 'build/artifacts/NITechSearch-unsigned.ipa'
with zipfile.ZipFile(path) as archive:
    base = 'Payload/NITechVacancyViewer.app/'
    info = plistlib.loads(archive.read(base + 'Info.plist'))
    assert info['CFBundlePackageType'] == 'APPL'
    assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
    assert info['CFBundleExecutable'] in [p.removeprefix(base) for p in archive.namelist()]
    assert info['CFBundleIdentifier'] == 'jp.nothingwillbenothing.nitechsearch'
    print('Validated device IPA:', info['CFBundleIdentifier'], info['MinimumOSVersion'])
PY
echo "Built unsigned device IPA in ios/build/artifacts."
