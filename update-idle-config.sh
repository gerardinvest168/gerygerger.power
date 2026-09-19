#!/bin/bash
# update-idle-config.sh — write a single idle key to shell.json
# Usage: update-idle-config.sh <key> <seconds|off>
#   key: screensaver | lock
#   value: number of seconds, or "off" (writes 0)

KEY="${1:-screensaver}"
VALUE="${2:-150}"

SHELL_JSON="$HOME/.config/omarchy/shell.json"

[[ -f "$SHELL_JSON" ]] || { echo '{"idle":{}}' > "$SHELL_JSON"; }

if [[ "$VALUE" == "off" || "$VALUE" == "0" ]]; then
  VAL=0
else
  VAL="$VALUE"
fi

python3 - <<PYEOF
import json, sys
path = "$SHELL_JSON"
with open(path) as f:
    data = json.load(f)
data.setdefault("idle", {})
data["idle"]["$KEY"] = int($VAL)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
