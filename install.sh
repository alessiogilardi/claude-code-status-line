#!/usr/bin/env bash
# Installs the Claude Code status line for Linux/macOS.
# Copies statusline-command.sh to ~/.claude/ and sets statusLine in settings.json.

set -euo pipefail

SCRIPT_NAME="statusline-command.sh"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SRC_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$SCRIPT_NAME"

# ── 1. Prerequisites ──────────────────────────────────────────────────────────

if [ ! -f "$SRC_SCRIPT" ]; then
    echo "Error: $SRC_SCRIPT not found." >&2
    echo "Run this installer from the repository root." >&2
    exit 1
fi

if [ ! -d "$CLAUDE_DIR" ]; then
    echo "Error: $CLAUDE_DIR not found." >&2
    echo "Make sure Claude Code is installed." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required to update settings.json." >&2
    exit 1
fi

# ── 2. Copy script ────────────────────────────────────────────────────────────

DEST="$CLAUDE_DIR/$SCRIPT_NAME"
cp -f "$SRC_SCRIPT" "$DEST"
chmod +x "$DEST"
echo "Copied: $DEST"

# ── 3. Update settings.json (non-destructive merge) ──────────────────────────

python3 - "$DEST" <<'PYEOF'
import json, sys, os
dest = sys.argv[1]
path = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
try:
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}
settings["statusLine"] = {"type": "command", "command": f'bash "{dest}"'}
with open(path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
echo "Updated: $SETTINGS_FILE"

# ── 4. Done ───────────────────────────────────────────────────────────────────

echo ""
echo "statusLine.command set to:"
echo "  bash \"$DEST\""
echo ""
echo "Restart Claude Code to activate the status line."
echo "On first launch Claude Code may prompt you to trust the status line command."
