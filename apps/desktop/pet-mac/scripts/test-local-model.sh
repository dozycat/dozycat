#!/bin/bash
set -euo pipefail
APP="${1:?Usage: test-local-model.sh /path/to/dozycat-debug.app /tmp/report.json}"
REPORT="${2:?Pass an absolute report path}"
case "$REPORT" in /*) ;; *) echo 'Report path must be absolute' >&2; exit 2 ;; esac
[ ! -e "$REPORT" ] || { echo 'Report already exists; choose a new path' >&2; exit 2; }
export DOZYCAT_HOME="${DOZYCAT_HOME:-$HOME/.dozycat-debug}"
export DOZYCAT_MLX_SMOKE_REPORT="$REPORT"
"$APP/Contents/MacOS/dozycat-debug"
python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    report = json.load(source)
print(json.dumps(report, indent=2, ensure_ascii=False))
sys.exit(0 if report.get('passed') else 1)
PY
