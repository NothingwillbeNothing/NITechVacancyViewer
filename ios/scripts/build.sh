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
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build
ditto -c -k --sequesterRsrc --keepParent \
  build/simulator/Build/Products/Release-iphonesimulator/NITechVacancyViewer.app \
  build/artifacts/NITechSearch-iOS-Simulator.zip

xcodebuild -project "$project" -scheme "$scheme" -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
payload=$(mktemp -d)
trap 'rm -rf "$payload"' EXIT
mkdir -p "$payload/Payload"
cp -R build/device/Build/Products/Release-iphoneos/NITechVacancyViewer.app "$payload/Payload/"
ditto -c -k --sequesterRsrc "$payload" build/artifacts/NITechSearch-unsigned.ipa
echo "Built simulator ZIP and unsigned device IPA in ios/build/artifacts."
