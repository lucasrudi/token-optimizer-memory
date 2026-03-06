#!/usr/bin/env bash
# Installs both token-optimizer-memory hooks into ~/.claude/settings.json:
#   1. UserPromptSubmit → analyze-prompt.sh (rule-based, instant)
#   2. Stop            → learn-from-session.sh (AI-powered, background)

SETTINGS="$HOME/.claude/settings.json"
SKILL_DIR="$HOME/.claude/skills/token-optimizer-memory"
ANALYZE_CMD="bash \"$SKILL_DIR/scripts/analyze-prompt.sh\""
LEARN_CMD="bash \"$SKILL_DIR/scripts/learn-from-session.sh\""

if [ ! -f "$SETTINGS" ]; then
  echo "Error: $SETTINGS not found. Open Claude Code at least once first." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq" >&2
  exit 1
fi

chmod +x "$SKILL_DIR/scripts/analyze-prompt.sh"
chmod +x "$SKILL_DIR/scripts/learn-from-session.sh"

# Backup
cp "$SETTINGS" "${SETTINGS}.bak"

# Check which hooks are already installed
ANALYZE_INSTALLED=$(jq --arg cmd "$ANALYZE_CMD" '
  [.hooks.UserPromptSubmit // [] | .[] | .hooks // [] | .[] | .command] |
  map(select(. == $cmd)) | length
' "$SETTINGS" 2>/dev/null || echo 0)

LEARN_INSTALLED=$(jq --arg cmd "$LEARN_CMD" '
  [.hooks.Stop // [] | .[] | .hooks // [] | .[] | .command] |
  map(select(. == $cmd)) | length
' "$SETTINGS" 2>/dev/null || echo 0)

UPDATED="$SETTINGS"

# Install UserPromptSubmit hook if missing
if [ "$ANALYZE_INSTALLED" -eq 0 ]; then
  jq --arg cmd "$ANALYZE_CMD" '
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": $cmd }]
    }])
  ' "$UPDATED" > "${UPDATED}.tmp" && mv "${UPDATED}.tmp" "$UPDATED"
  echo "✓ Installed UserPromptSubmit hook (real-time prompt analysis)"
else
  echo "  UserPromptSubmit hook already installed"
fi

# Install Stop hook if missing
if [ "$LEARN_INSTALLED" -eq 0 ]; then
  jq --arg cmd "$LEARN_CMD" '
    .hooks.Stop = ((.hooks.Stop // []) + [{
      "hooks": [{ "type": "command", "command": $cmd }]
    }])
  ' "$UPDATED" > "${UPDATED}.tmp" && mv "${UPDATED}.tmp" "$UPDATED"
  echo "✓ Installed Stop hook (AI-powered session learning)"
else
  echo "  Stop hook already installed"
fi

echo ""
echo "token-optimizer-memory is active."
echo "  • Real-time tips appear in yellow before each prompt is processed."
echo "  • Memory grows at: $SKILL_DIR/memory/patterns.md"
echo "  • Backup saved at: ${SETTINGS}.bak"
