#!/bin/bash
# read-idle-config.sh — output JSON with current idle settings from shell.json
python3 - <<'PYEOF'
import json, os
path = os.path.expanduser("~/.config/omarchy/shell.json")
try:
    with open(path) as f:
        data = json.load(f)
    idle = data.get("idle", {})
    print(json.dumps({
        "screensaver": idle.get("screensaver", 150),
        "lock": idle.get("lock", 300)
    }))
except Exception:
    print(json.dumps({"screensaver": 150, "lock": 300}))
PYEOF
