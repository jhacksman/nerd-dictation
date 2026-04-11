#!/usr/bin/env bash
# Offline, hash-verified install of nerd-dictation's Python dependency tree
# into a virtual environment, using only the wheels under vendor/wheels/.
#
# Usage:
#     ./vendor/install-offline.sh [VENV_DIR]
#
# Default VENV_DIR is ./venv relative to the repo root. Pass an existing venv
# path to install into it, or a new path to create one.
#
# This script refuses to touch PyPI. --no-index tells pip not to talk to any
# index server, --find-links points pip at the local wheel directory, and
# --require-hashes makes pip reject any file whose SHA256 does not match
# vendor/requirements.txt.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
REQ="$HERE/requirements.txt"
WHEELS="$HERE/wheels"
VENV="${1:-$REPO/venv}"

if [[ ! -d "$WHEELS" ]]; then
    echo "error: $WHEELS does not exist. Run vendor/fetch-wheels.sh first, or" >&2
    echo "       check out the repo with the vendored wheels included." >&2
    exit 1
fi
if [[ ! -f "$REQ" ]]; then
    echo "error: $REQ not found" >&2
    exit 1
fi

if [[ ! -d "$VENV" ]]; then
    echo "Creating venv at $VENV"
    python3 -m venv "$VENV"
fi

# shellcheck disable=SC1091
source "$VENV/bin/activate"

# Upgrade pip *from the local wheel cache only* if a newer pip wheel was
# vendored. Otherwise leave pip alone. We do NOT reach out to PyPI for pip.
echo "Installing pinned requirements from $WHEELS"
pip install \
    --no-index \
    --find-links "$WHEELS" \
    --require-hashes \
    --requirement "$REQ"

echo
echo "Sanity check: importing vosk"
python3 -c "import vosk; vosk.SetLogLevel(-1); print('vosk import OK')"

echo
echo "Done. Activate with:  source $VENV/bin/activate"
echo "Then run nerd-dictation as usual, e.g.:"
echo "  $REPO/nerd-dictation begin --vosk-model-dir=\$HOME/.config/nerd-dictation/model"
