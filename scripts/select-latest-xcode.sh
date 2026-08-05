#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

mapfile -t candidates < <(
  find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print \
    | grep -Ev '(beta|Beta|RC|Release Candidate)' \
    | sort -V
)

if (( ${#candidates[@]} == 0 )); then
  echo "No stable Xcode installation was found."
  exit 1
fi

selected="${candidates[-1]}"
sudo xcode-select --switch "$selected/Contents/Developer"
echo "Selected $selected"
xcodebuild -version
swift --version
