#!/bin/zsh
set -euo pipefail
notype_root="${0:A:h:h}"
cd "$notype_root"
swift scripts/make-icon.swift "$notype_root"
iconutil -c icns .analysis/NoType.iconset -o Resources/NoType.icns
swift build -c release
notype_bin="$(swift build -c release --show-bin-path)"
notype_app="$notype_root/dist/NoType.app"
mkdir -p "$notype_app/Contents/MacOS" "$notype_app/Contents/Resources"
cp "$notype_bin/NoType" "$notype_app/Contents/MacOS/NoType"
cp Resources/Info.plist "$notype_app/Contents/Info.plist"
cp Resources/speech-test.wav "$notype_app/Contents/Resources/speech-test.wav"
if [[ -f Resources/NoType.icns ]]; then
  cp Resources/NoType.icns "$notype_app/Contents/Resources/NoType.icns"
fi
python3 scripts/sign-local.py "$notype_app"
codesign --verify --deep --strict "$notype_app"
print "Built: $notype_app"
