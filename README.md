# Dorico Voice Control

A separate native macOS application for controlling Dorico by voice.

This repository is intentionally independent from Dorico Xbox Bridge. It has its own process, bundle identifier, permissions, preferences, tests, installer, and release lifecycle so microphone or speech-recognition failures cannot destabilize the controller bridge.

## What it does

- Recognizes ordinary Dorico and music-language phrases.
- Keeps ordered multi-command speech in order.
- Supports durations, pitches, accidentals, bars, navigation, meters, keys, clefs, dynamics, tempo, ornaments, playing techniques, rehearsal marks, playback, editing, and note input.
- Supports `Dorico command …` for any command available through Dorico's Jump Bar.
- Includes a reusable five-phrase voice setup and custom pronunciation aliases.
- Previews every recognized command plan before execution by default.
- Can optionally auto-run only high-confidence, fully recognized plans.

## Safety architecture

The app is not embedded in Dorico Xbox Bridge. Speech permissions, microphone access, audio taps, recognition tasks, preferences, logs, and crashes are isolated to this app.

Before sending any event to Dorico, the core validates command count, step count, repeated actions, typed text length, delays, unknown segments, and recognition confidence. Contextual speech hints are deduplicated and capped at Apple's 100-phrase limit. Invalid microphone formats are rejected before an AVAudioEngine tap can be installed.

## Build

```sh
swift test
bash scripts/build-app.sh
```

The macOS build creates a universal Apple Silicon + Intel app, ZIP, and DMG in `dist/`.
