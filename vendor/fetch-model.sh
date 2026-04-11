#!/usr/bin/env bash
# Download a VOSK speech model from alphacephei.com, verify its SHA256 against
# vendor/models.sha256, and unpack it into the target directory.
#
# Usage:
#     ./vendor/fetch-model.sh [MODEL_ZIP] [DEST_DIR]
#
# Defaults:
#     MODEL_ZIP = vosk-model-small-en-us-0.15.zip
#     DEST_DIR  = ~/.config/nerd-dictation
#
# The model zip is downloaded to a temp dir, hash-verified, and only then
# unpacked. If the hash does not match vendor/models.sha256, the zip is deleted
# and this script exits non-zero. Never unpack a model that failed verification.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HASH_FILE="$HERE/models.sha256"

MODEL_ZIP="${1:-vosk-model-small-en-us-0.15.zip}"
DEST_DIR="${2:-$HOME/.config/nerd-dictation}"
MIRROR="${VOSK_MIRROR:-https://alphacephei.com/kaldi/models}"

if [[ ! -f "$HASH_FILE" ]]; then
    echo "error: $HASH_FILE not found" >&2
    exit 1
fi

# Confirm the requested model is actually pinned. We refuse to download
# something we don't have a hash for.
if ! grep -qE "[[:space:]]${MODEL_ZIP}\$" "$HASH_FILE"; then
    echo "error: $MODEL_ZIP is not listed in $HASH_FILE" >&2
    echo "       Add its SHA256 hash there before fetching." >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $MODEL_ZIP from $MIRROR"
# --fail: error on HTTP 4xx/5xx. --location: follow redirects. --proto =https
# refuses any non-HTTPS redirect target. --tlsv1.2 floors TLS version.
curl --fail --location --proto '=https' --tlsv1.2 \
    -o "$tmp/$MODEL_ZIP" \
    "$MIRROR/$MODEL_ZIP"

echo "Verifying SHA256..."
# sha256sum -c reads the canonical "<hash>  <filename>" format. We grep out
# just the matching line so unrelated models aren't checked.
( cd "$tmp" && grep -E "[[:space:]]${MODEL_ZIP}\$" "$HASH_FILE" | sha256sum -c - )

mkdir -p "$DEST_DIR"
echo "Unpacking into $DEST_DIR"
# -q quiet, -o overwrite without prompting. We unzip into DEST_DIR directly;
# the zip is expected to contain a top-level directory named after the model.
unzip -q -o "$tmp/$MODEL_ZIP" -d "$DEST_DIR"

# Convenience: if the user unpacked into ~/.config/nerd-dictation and there is
# no "model" symlink yet, point it at the just-unpacked directory so that
# nerd-dictation's default --vosk-model-dir works without extra flags.
unpacked="${MODEL_ZIP%.zip}"
if [[ -d "$DEST_DIR/$unpacked" && ! -e "$DEST_DIR/model" ]]; then
    ln -s "$unpacked" "$DEST_DIR/model"
    echo "Created symlink $DEST_DIR/model -> $unpacked"
fi

echo "Done."
