#!/usr/bin/env sh
set -eu

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK is required. Install Flutter 3.29 or newer first.' >&2
  exit 1
fi

flutter create . --platforms=windows,android --org com.mizanlaw --project-name mizan_law
flutter pub get
