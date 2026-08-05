#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

selected="$(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print | /usr/bin/python3 -c '
import re
import sys
paths = [line.strip() for line in sys.stdin if line.strip()]
paths = [path for path in paths if not re.search(r"(?:beta|release candidate|\brc\b)", path, re.I)]
if not paths:
    raise SystemExit(1)
def version_key(path):
    numbers = tuple(int(value) for value in re.findall(r"\d+", path))
    return (numbers, path == "/Applications/Xcode.app", path)
print(max(paths, key=version_key))
')"

if [[ -z "$selected" ]]; then
  echo "No stable Xcode installation was found."
  exit 1
fi

sudo xcode-select --switch "$selected/Contents/Developer"
echo "Selected $selected"
xcodebuild -version
swift --version
