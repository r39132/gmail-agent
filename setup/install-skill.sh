#!/usr/bin/env bash
#
# install-skill.sh — Symlink the gmail-skill into the OpenClaw workspace
#
set -euo pipefail

SKILL_SOURCE="$(cd "$(dirname "$0")/../skills/gmail-skill" && pwd)"
SKILL_TARGET="$HOME/.openclaw/workspace/skills/gmail-skill"

# Ensure the target directory exists
mkdir -p "$HOME/.openclaw/workspace/skills"

# Create or update the symlink
if [[ -L "$SKILL_TARGET" ]]; then
    echo "Updating existing symlink..."
    ln -sfn "$SKILL_SOURCE" "$SKILL_TARGET"
elif [[ -e "$SKILL_TARGET" ]]; then
    echo "Error: $SKILL_TARGET already exists and is not a symlink." >&2
    echo "Please remove it manually and re-run this script." >&2
    exit 1
else
    echo "Creating symlink..."
    ln -sfn "$SKILL_SOURCE" "$SKILL_TARGET"
fi

echo "Skill installed: $SKILL_TARGET -> $SKILL_SOURCE"
echo ""
echo "Next steps:"
echo "  1. Restart the OpenClaw gateway or run 'openclaw skills refresh'"
echo "  2. Verify with: openclaw skills list | grep gmail"
