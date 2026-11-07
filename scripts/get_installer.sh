#!/bin/bash
# Prints the path of the Lumen OS installer/ that a build bundles. $LUMEN_OS_DIR/installer when that variable names a
# local checkout of Project-Lumen-OS/lumen-os; otherwise a sparse checkout of that repository (installer/ only) in
# vendor/lumen-os at $LUMEN_OS_REF (main by default), brought up to date on every call.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ -n "${LUMEN_OS_DIR:-}" ]; then
  [ -f "$LUMEN_OS_DIR/installer/lumen-install.sh" ] || { echo "no installer/lumen-install.sh in $LUMEN_OS_DIR" >&2; exit 1; }
  echo "$LUMEN_OS_DIR/installer"; exit 0
fi
REF=${LUMEN_OS_REF:-main}
DIR=$ROOT/vendor/lumen-os
if [ ! -d "$DIR/.git" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse --branch "$REF" https://github.com/Project-Lumen-OS/lumen-os.git "$DIR" >&2
  git -C "$DIR" sparse-checkout set installer >&2
else
  git -C "$DIR" fetch -q --depth 1 origin "$REF" >&2
  git -C "$DIR" checkout -q --detach FETCH_HEAD >&2
fi
echo "$DIR/installer"
