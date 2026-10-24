#!/bin/bash
# Double-click entry point for macOS.
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bash "$ROOT/sejong-slide" "$@"
RESULT=$?
if [ -t 0 ]; then read -r -p 'Press Enter to close...' _; fi
exit "$RESULT"
