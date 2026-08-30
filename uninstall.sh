#!/usr/bin/env bash
# Remove the widget. Leaves icp, your vault, and your Apple account untouched.
set -uo pipefail
PLUGIN_ID="icloud.keychain"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

systemctl --user disable --now omarchy-keychain-sync.timer 2>/dev/null
rm -f "$HOME/.config/systemd/user/omarchy-keychain-sync."{service,timer}
systemctl --user daemon-reload

rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
rm -f "$HOME/.local/bin/omarchy-keychain-"{env,sync,status,auth,copy}

if [ -f "$SHELL_JSON" ]; then
  python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PY'
import json, sys
path, pid = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for section in d.get("bar", {}).get("layout", {}).values():
    if isinstance(section, list):
        section[:] = [w for w in section if w.get("id") != pid]
json.dump(d, open(path, "w"), indent=2)
print("removed from the bar")
PY
fi

echo "anisette.service and ~/.config/omarchy-keychain.conf were left in place;"
echo "remove them by hand if nothing else uses them."
omarchy restart shell >/dev/null 2>&1 || true
echo "Done."
