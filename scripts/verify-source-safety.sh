#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if grep -R --line-number -E 'fatalError\(|preconditionFailure\(|try!' Sources; then
  echo "Unsafe crash primitive found in source."
  exit 1
fi

if grep -R --line-number -E 'DoricoXboxBridge|DoricoBridgeCore' Sources Package.swift README.md; then
  echo "The separate voice app must not depend on the controller bridge."
  exit 1
fi

grep -q 'maximumContextualStrings = 100' Sources/DoricoVoiceCore/VoiceSafetyPolicy.swift
grep -q 'isValidAudioFormat' Sources/DoricoVoiceControl/SpeechController.swift
grep -q 'inputTapInstalled' Sources/DoricoVoiceControl/SpeechController.swift
grep -q 'request.contextualStrings = VoiceSafetyPolicy.prioritizedContextualStrings' Sources/DoricoVoiceControl/SpeechController.swift
grep -q 'autoExecuteHighConfidencePlans = false' Sources/DoricoVoiceControl/AppTypes.swift
grep -q 'blockUnknownSegments = true' Sources/DoricoVoiceCore/VoiceSafetyPolicy.swift

echo "Source safety rails verified."
