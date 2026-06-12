#!/usr/bin/env bash
# Re-copies the VERBATIM design files from the plugin's example/ into this
# skill's bundled templates, so the bundled design doesn't drift as the
# example app evolves on feat/v2.
#
# Only pure-design files are synced. The adapted entry points
# (editor_controller.dart, editor_screen.dart, widgets/editor_top_bar.dart)
# and the new media/* + main.dart are intentionally NOT touched here — they
# carry consumer-app edits that must survive. Re-check them by hand if the
# example's equivalents change shape.
#
# Run from anywhere inside the repo. Usage: sync_from_example.sh
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
SRC="$REPO_ROOT/example/lib/editor"
DST="$SKILL_DIR/assets/app_template/lib/editor"

if [[ ! -d "$SRC" ]]; then
  echo "error: $SRC not found — run inside the plugin repo." >&2
  exit 1
fi

cp "$SRC/theme/editor_theme.dart" "$DST/theme/editor_theme.dart"

# All widgets are verbatim design EXCEPT editor_top_bar.dart (adapted).
for f in "$SRC"/widgets/*.dart; do
  base="$(basename "$f")"
  [[ "$base" == "editor_top_bar.dart" ]] && continue
  cp "$f" "$DST/widgets/$base"
done

echo "Synced verbatim design files from example/. Adapted files left untouched:"
echo "  editor_controller.dart, editor_screen.dart, widgets/editor_top_bar.dart"
echo "Review those by hand if the example versions changed structurally."
