#!/usr/bin/env bash
# Install the iCloud Keychain bar widget for Omarchy.
#
#   ./install.sh [--icp-home /path/to/iCloud-Keychain-for-Omarchy]
#
# The widget presents an existing vault; it does not create one. Install and sign
# in with icp first - see README.md.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="icloud.keychain"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
CONF="$HOME/.config/omarchy-keychain.conf"

ICP_HOME_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --icp-home) ICP_HOME_ARG="${2:?--icp-home needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v omarchy-shell >/dev/null || { echo "This installer is for Omarchy." >&2; exit 1; }
[ -f "$SHELL_JSON" ] || { echo "No $SHELL_JSON - is the Omarchy shell installed?" >&2; exit 1; }

# --- locate icp -------------------------------------------------------------
if [ -n "$ICP_HOME_ARG" ]; then
  [ -x "$ICP_HOME_ARG/.venv/bin/icp" ] || {
    echo "No icp venv at $ICP_HOME_ARG/.venv/bin/icp" >&2; exit 1; }
  printf 'ICP_HOME=%s\n' "$ICP_HOME_ARG" > "$CONF"
  echo "==> recorded ICP_HOME in $CONF"
fi

set +e
ICP_BIN="$(bash -c "source '$REPO/bin/omarchy-keychain-env' >/dev/null 2>&1; echo \$ICP_BIN")"
set -e
if [ -z "$ICP_BIN" ]; then
  cat >&2 <<'MSG'
Could not find icp.

Install and sign in first:

  git clone https://github.com/EttienneM/iCloud-Keychain-for-Omarchy.git
  cd iCloud-Keychain-for-Omarchy
  python3 -m venv .venv && .venv/bin/pip install -e .
  .venv/bin/icp login

Then re-run:  ./install.sh --icp-home /path/to/iCloud-Keychain-for-Omarchy
MSG
  exit 1
fi
echo "==> using icp at $ICP_BIN"

if ! "$ICP_BIN" status --no-probe >/dev/null 2>&1; then
  echo "    warning: 'icp status' failed - sign in with 'icp login' before using the widget" >&2
fi

echo "==> plugin"
mkdir -p "$PLUGIN_DIR"
cp "$REPO/plugin/"* "$PLUGIN_DIR/"

echo "==> helper scripts"
mkdir -p "$BIN_DIR"
cp "$REPO/bin/"* "$BIN_DIR/"
chmod +x "$BIN_DIR"/omarchy-keychain-*
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "    note: $BIN_DIR is not on your PATH (the widget uses absolute paths, so this is only for running the helpers by hand)" ;;
esac

echo "==> systemd units"
mkdir -p "$UNIT_DIR"
cp "$REPO/systemd/"*.service "$REPO/systemd/"*.timer "$UNIT_DIR/"
systemctl --user daemon-reload
# anisette.service drives an existing container; it is only useful once icp's
# setup has created one, so a failure here is not fatal.
systemctl --user enable --now anisette.service 2>/dev/null \
  || echo "    (anisette.service not started - see the icp README if syncing fails)"
systemctl --user enable --now omarchy-keychain-sync.timer

echo "==> bar layout"
python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PY'
import json, sys
path, pid = sys.argv[1], sys.argv[2]
d = json.load(open(path))
right = d.setdefault("bar", {}).setdefault("layout", {}).setdefault("right", [])
if any(w.get("id") == pid for w in right):
    print("    already in the bar")
else:
    right.insert(max(0, len(right) - 4), {"id": pid})
    json.dump(d, open(path, "w"), indent=2)
    print("    added to the bar")
PY

echo "==> restarting the shell"
omarchy restart shell >/dev/null 2>&1 || true

cat <<'DONE'

Done. A key icon should appear in the bar.

  click            open the panel
  right-click      sync now
  type             search your logins
  click a result   expand it, then copy username / password / code

Bind it to a key with:  omarchy-shell icloud.keychain toggle
DONE
