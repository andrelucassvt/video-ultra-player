#!/usr/bin/env bash
# Copies the editor + media-picker Dart templates into a consumer Flutter app
# and rewrites the package token to the app's own package name.
#
# Usage: scaffold.sh <app_root> <app_package_name>
#   app_root          absolute path to the Flutter app (the dir with pubspec.yaml)
#   app_package_name  the `name:` field from that pubspec.yaml
#
# The only string rewritten is `video_ultra_player_example` (the template's
# package token). The plugin import `package:video_ultra_player/...` has no
# `_example` suffix, so it is left untouched.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scaffold.sh <app_root> <app_package_name>" >&2
  exit 2
fi

APP_ROOT="$1"
APP_PKG="$2"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SKILL_DIR/assets/app_template/lib"

if [[ ! -d "$APP_ROOT/lib" ]]; then
  echo "error: $APP_ROOT/lib not found — is this a Flutter app root?" >&2
  exit 1
fi

mkdir -p "$APP_ROOT/lib/editor" "$APP_ROOT/lib/media"
cp -R "$TEMPLATE/editor/." "$APP_ROOT/lib/editor/"
cp -R "$TEMPLATE/media/." "$APP_ROOT/lib/media/"

# BSD sed (macOS) needs the empty '' after -i; GNU sed users: drop the ''.
find "$APP_ROOT/lib/editor" "$APP_ROOT/lib/media" -name '*.dart' -print0 \
  | xargs -0 sed -i '' "s/video_ultra_player_example/${APP_PKG}/g"

echo "Scaffolded editor + media into $APP_ROOT/lib (package: $APP_PKG)."
echo "Next: wire MediaPickerScreen as the app's home — see the main.dart template at:"
echo "  $TEMPLATE/main.dart"
