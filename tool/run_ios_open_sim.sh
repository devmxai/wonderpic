#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
open -a Simulator
flutter run -d ios
