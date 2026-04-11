#!/usr/bin/env bash
# Refetch all Python dependencies referenced by vendor/requirements.txt and
# verify every file on disk against the hashes pinned there.
#
# Use this when you intentionally want to refresh the vendored wheels (for
# example after bumping vosk). For normal offline installs you DO NOT need to
# run this; the wheels are already committed under vendor/wheels/ and can be
# installed with ./vendor/install-offline.sh.
#
# Most packages are fetched as binary wheels from PyPI. One dependency (srt)
# is published only as an sdist on PyPI. To avoid running setup.py on every
# install, we download the sdist, verify it against its upstream PyPI hash,
# build it into a wheel in a clean venv, and then verify the built wheel
# against the hash in requirements.txt. This means the srt wheel is NOT
# byte-identical to anything published on PyPI and can only be reproduced by
# rebuilding it the same way.
#
# This script is deliberately strict: any hash mismatch is fatal.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REQ="$HERE/requirements.txt"
WHEELS="$HERE/wheels"

# Upstream SHA256 of srt-3.5.3.tar.gz as published on PyPI. This is the hash
# we verify before we trust the sdist enough to build it locally.
SRT_SDIST_SHA256="4884315043a4f0740fd1f878ed6caa376ac06d70e135f306a6dc44632eed0cc0"

# Pinned build toolchain for the srt rebuild. These versions plus
# SOURCE_DATE_EPOCH + PYTHONHASHSEED below make the srt wheel build
# bit-reproducible, so its hash in vendor/requirements.txt is stable.
#
# If you bump these versions the vendored srt-*.whl hash WILL change and you
# must update vendor/requirements.txt to match. Do not mix-and-match tool
# versions without updating the hash.
BUILD_PIP_VERSION="24.2"
BUILD_SETUPTOOLS_VERSION="75.1.0"
BUILD_WHEEL_VERSION="0.44.0"

# Frozen timestamp used by SOURCE_DATE_EPOCH to make zip entry mtimes
# deterministic. 2020-01-01 00:00:00 UTC. Arbitrary, just has to be stable.
export SOURCE_DATE_EPOCH=1577836800
# Deterministic dict ordering / hashing in the build subprocess.
export PYTHONHASHSEED=0

if [[ ! -f "$REQ" ]]; then
    echo "error: $REQ not found" >&2
    exit 1
fi
if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
    echo "error: pip (or pip3) is required" >&2
    exit 1
fi
PIP="$(command -v pip3 || command -v pip)"

mkdir -p "$WHEELS"

# Start from a clean wheel directory so we are sure what we end up with.
echo "Clearing $WHEELS"
find "$WHEELS" -maxdepth 1 -type f \( -name '*.whl' -o -name '*.tar.gz' \) -delete

# ---------------------------------------------------------------------------
# Step 1: download every non-srt package as a binary wheel from PyPI.
# We run one `pip download --no-deps` per package so the resolver cannot
# substitute a different version than we pinned.
# ---------------------------------------------------------------------------
binary_packages=(
    "vosk==0.3.45"
    "cffi==2.0.0"
    "pycparser==3.0"
    "requests==2.33.1"
    "charset-normalizer==3.4.7"
    "idna==3.11"
    "urllib3==2.6.3"
    "certifi==2026.2.25"
    "tqdm==4.67.3"
    "websockets==16.0"
)
for spec in "${binary_packages[@]}"; do
    echo "Downloading $spec"
    "$PIP" download \
        --dest "$WHEELS" \
        --no-deps \
        --only-binary=:all: \
        "$spec"
done

# ---------------------------------------------------------------------------
# Step 2: handle srt. Download the sdist, verify it against the pinned
# upstream hash, then build a wheel locally and let Step 3 verify that wheel.
# ---------------------------------------------------------------------------
echo "Downloading srt==3.5.3 (sdist)"
srt_tmp="$(mktemp -d)"
trap 'rm -rf "$srt_tmp"' EXIT

"$PIP" download \
    --dest "$srt_tmp" \
    --no-deps \
    --no-binary=:all: \
    "srt==3.5.3"

srt_sdist="$(ls "$srt_tmp"/srt-3.5.3.tar.gz)"
echo "Verifying srt sdist against upstream hash..."
got_sdist="$(sha256sum "$srt_sdist" | awk '{print $1}')"
if [[ "$got_sdist" != "$SRT_SDIST_SHA256" ]]; then
    echo "  MISMATCH on srt sdist" >&2
    echo "    expected: $SRT_SDIST_SHA256" >&2
    echo "    actual:   $got_sdist" >&2
    echo "Refusing to build from a tampered sdist." >&2
    exit 1
fi
echo "  OK: srt sdist"

# Build srt into a wheel in a disposable venv with a PINNED upstream build
# toolchain, so the resulting wheel is bit-reproducible regardless of whatever
# setuptools happens to be on the host system.
build_venv="$(mktemp -d)/venv"
python3 -m venv "$build_venv"
# shellcheck disable=SC1091
source "$build_venv/bin/activate"
pip install --quiet --no-deps \
    "pip==$BUILD_PIP_VERSION" \
    "setuptools==$BUILD_SETUPTOOLS_VERSION" \
    "wheel==$BUILD_WHEEL_VERSION"
# --no-build-isolation forces pip to use the setuptools/wheel we just pinned
# in this venv rather than grabbing whatever is latest on PyPI for the
# build-system step.
pip wheel --no-deps --no-build-isolation --wheel-dir "$WHEELS" "$srt_sdist"
deactivate

# ---------------------------------------------------------------------------
# Step 3: independent verification against requirements.txt. This catches the
# case where someone edited requirements.txt after the fact or where pip's
# own hash check was silently skipped.
# ---------------------------------------------------------------------------
echo
echo "Re-verifying every wheel on disk against $REQ"
fail=0
pkg=""
ver=""
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9._-]+)==([^[:space:]]+)[[:space:]]*\\?$ ]]; then
        pkg="${BASH_REMATCH[1]}"
        ver="${BASH_REMATCH[2]}"
        continue
    fi
    if [[ "$line" =~ --hash=sha256:([0-9a-f]{64}) ]]; then
        want="${BASH_REMATCH[1]}"
        pkg_norm="${pkg//-/_}"
        match="$(ls "$WHEELS" 2>/dev/null | grep -iE "^(${pkg}|${pkg_norm})-${ver}[.-]" || true)"
        if [[ -z "$match" ]]; then
            echo "  MISSING: $pkg==$ver (no file matches in $WHEELS)" >&2
            fail=1
            continue
        fi
        got="$(sha256sum "$WHEELS/$match" | awk '{print $1}')"
        if [[ "$got" != "$want" ]]; then
            echo "  MISMATCH: $match" >&2
            echo "    expected: $want" >&2
            echo "    actual:   $got" >&2
            fail=1
        else
            echo "  OK: $match"
        fi
    fi
done < "$REQ"

if (( fail )); then
    echo >&2
    echo "error: one or more hash checks failed. Do NOT commit the wheels in this state." >&2
    exit 1
fi

echo
echo "All wheels downloaded, built, and verified."
