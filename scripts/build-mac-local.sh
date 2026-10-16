#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mac_build_dir="$project_root/work/local/mac-native-release"
xcodebuild -project macos/JACMac.xcodeproj -scheme JACMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$mac_build_dir" build
mkdir -p "$project_root/outputs"
ditto "$mac_build_dir/Build/Products/Release/JAC Music.app" "$project_root/outputs/JAC Music.app"
codesign --verify --deep --strict "$project_root/outputs/JAC Music.app"
printf '%s\n' 'Lista para abrir: outputs/JAC Music.app'
