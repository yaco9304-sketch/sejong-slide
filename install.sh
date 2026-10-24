#!/usr/bin/env bash
# sejong-slide local runtime installer. Compatible with macOS Bash 3.2.
set -Eeuo pipefail

usage() {
    cat <<'HELP'
Usage: bash install.sh [--check | --help]

Prepare the repository-local Python environment and requirements.
Existing Python 3.10+ is reused; otherwise Python 3.12 is downloaded.
--check verifies an existing installation without downloading anything.
HELP
}
CHECK_ONLY=0
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --check) CHECK_ONLY=1; shift ;;
    '') ;;
    *) usage >&2; exit 2 ;;
esac
if [ "$#" -gt 0 ]; then usage >&2; exit 2; fi

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$ROOT"
TOOLS="$ROOT/.sejong-tools"
PYTHON="$ROOT/.venv/bin/python"
READY="$TOOLS/ready"
VERIFY='import sys; assert sys.version_info >= (3, 10), "Python 3.10+ required"; import pptx, flask, PIL, fitz, requests, numpy; print("Python and core packages: OK")'
STEP="checking the installation"
report_failure() {
    code=$?
    if [ "$CHECK_ONLY" -eq 1 ]; then
        printf '\nCheck failed while %s. Fix the reported errors above and run ./sejong-slide --check again.\n' "$STEP" >&2
    else
        printf '\nSetup failed while %s. Fix the error above and run bash install.sh again.\n' "$STEP" >&2
    fi
    exit "$code"
}
trap report_failure ERR

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ ! -x "$PYTHON" ] || [ ! -f "$READY" ] || \
            [ "$ROOT/requirements.txt" -nt "$READY" ] || \
            [ "$ROOT/.claude/skills/ppt-master/requirements.txt" -nt "$READY" ]; then
        printf 'Runtime setup is missing or outdated. Run ./sejong-slide --setup.\n' >&2
        exit 1
    fi
    PYTHONDONTWRITEBYTECODE=1 "$PYTHON" -I -c "$VERIFY"
    PYTHONDONTWRITEBYTECODE=1 "$PYTHON" -m pip check
    STEP="checking skill connections"
    "$PYTHON" .claude/skills/ppt-master/scripts/sync_codex_stubs.py --check
    "$PYTHON" .claude/skills/ppt-master/scripts/check_runtime_contracts.py
    exit 0
fi

[ -f "$ROOT/requirements.txt" ] || { printf 'requirements.txt is missing; download the complete repository.\n' >&2; exit 1; }
printf 'sejong-slide: preparing a local runtime (no administrator access needed).\n'
printf 'Downloads use Astral uv and PyPI; system Python and shell profiles stay unchanged.\n'
mkdir -p "$TOOLS/bin"
export UV_UNMANAGED_INSTALL="$TOOLS/bin"
export UV_PYTHON_INSTALL_DIR="$TOOLS/python"
export UV_PYTHON_BIN_DIR="$TOOLS/bin"
export UV_CACHE_DIR="$TOOLS/cache"
export UV_NO_CONFIG=1

STEP="installing uv"
if [ -x "$TOOLS/bin/uv" ]; then
    UV="$TOOLS/bin/uv"
else
    printf '[1/4] Downloading the Python bootstrap tool...\n'
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
            --connect-timeout 20 --max-time 180 \
            https://astral.sh/uv/0.13.5/install.sh -o "$TOOLS/uv-install.sh"
    elif command -v wget >/dev/null 2>&1; then
        wget --https-only --timeout=180 https://astral.sh/uv/0.13.5/install.sh -O "$TOOLS/uv-install.sh"
    else
        printf 'Install curl or wget with your OS package manager, then retry.\n' >&2
        exit 1
    fi
    sh "$TOOLS/uv-install.sh"
    UV="$TOOLS/bin/uv"
fi
"$UV" --version

STEP="preparing Python"
printf '[2/4] Checking Python and the local environment...\n'
if [ -e "$ROOT/.venv" ]; then
    if [ ! -x "$PYTHON" ] || ! "$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
        printf 'The existing .venv is unusable. Rename .venv, then run ./sejong-slide again.\n' >&2
        exit 1
    fi
else
    if "$UV" python find --system --no-python-downloads '>=3.10' > "$TOOLS/python-path.txt" 2>/dev/null; then
        IFS= read -r BASE_PYTHON < "$TOOLS/python-path.txt"
        printf 'Using installed Python: %s\n' "$BASE_PYTHON"
    else
        printf 'Python 3.10+ not found. Downloading local Python 3.12...\n'
        "$UV" python install --no-bin 3.12
        UV_PYTHON_PREFERENCE=only-managed "$UV" python find --no-python-downloads 3.12 > "$TOOLS/python-path.txt"
        IFS= read -r BASE_PYTHON < "$TOOLS/python-path.txt"
    fi
    "$UV" venv --quiet --no-project --python "$BASE_PYTHON" "$ROOT/.venv"
fi
"$PYTHON" --version
rm -f "$TOOLS/ready"

STEP="installing Python packages"
printf '[3/4] Installing project requirements...\n'
"$UV" pip install --quiet --python "$PYTHON" pip -r "$ROOT/requirements.txt"

STEP="verifying the runtime"
printf '[4/4] Verifying Python packages...\n'
"$PYTHON" -I -c "$VERIFY"
"$UV" pip check --python "$PYTHON"
touch "$TOOLS/ready"
printf '\nReady. Open this folder in your AI editor and ask it to create a PPT.\n'
printf 'Python tools can be run with: ./sejong-slide <script.py> [arguments]\n'
printf 'For the bundled slide fonts, see the Pretendard section in README.md.\n'
