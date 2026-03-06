#!/usr/bin/env bash
# Stop hook — AI-powered learning from completed session.
# Reads transcript, extracts prompt patterns, updates memory/patterns.md.
# Runs non-interactively after every session end.

INPUT=$(cat)

TRANSCRIPT=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('transcript_path', ''))
" 2>/dev/null)

[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

SKILL_DIR="$HOME/.claude/skills/token-optimizer-memory"
PATTERNS_FILE="$SKILL_DIR/memory/patterns.md"
BEST_PRACTICES="$SKILL_DIR/references/best-practices.md"

# Extract user prompts from JSONL transcript (last 15 user turns only)
USER_PROMPTS=$(python3 - "$TRANSCRIPT" << 'PYEOF'
import sys, json

transcript_path = sys.argv[1]
prompts = []

try:
    with open(transcript_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                msg_type = entry.get('type', '')
                # Handle both formats
                if msg_type == 'user':
                    msg = entry.get('message', entry)
                    content = msg.get('content', '')
                    if isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get('type') == 'text':
                                text = block.get('text', '').strip()
                                if text and len(text) > 15:
                                    prompts.append(text)
                    elif isinstance(content, str) and len(content.strip()) > 15:
                        prompts.append(content.strip())
            except:
                pass
except:
    pass

# Keep last 15 meaningful prompts, cap each at 300 chars to save tokens
result = []
for p in prompts[-15:]:
    result.append(p[:300] + ('...' if len(p) > 300 else ''))

print('\n---\n'.join(result))
PYEOF
)

[ -z "$USER_PROMPTS" ] && exit 0

# Count prompts to skip very short sessions (< 3 prompts)
PROMPT_COUNT=$(echo "$USER_PROMPTS" | grep -c '---' 2>/dev/null || echo "0")
[ "$PROMPT_COUNT" -lt 2 ] && exit 0

# Load existing pattern names to avoid duplicates
EXISTING_PATTERNS=$(grep '^\*\*' "$PATTERNS_FILE" 2>/dev/null | sed 's/\*\*//g' | tr '\n' '|')

# Build analysis prompt (keep it tight to minimize tokens)
ANALYSIS_PROMPT="You are a prompt efficiency coach. Analyze these Claude Code prompts for token waste patterns.

Best practices summary:
$(head -40 "$BEST_PRACTICES" 2>/dev/null)

Already known patterns (don't duplicate): $EXISTING_PATTERNS

User prompts from this session:
$USER_PROMPTS

Return ONLY a JSON array. Maximum 2 new patterns. Return [] if nothing new or significant found.
Format:
[{\"pattern\": \"short name\", \"example\": \"bad example (max 8 words)\", \"suggestion\": \"improvement (max 12 words)\", \"frequency\": \"common|occasional\"}]"

# Run non-interactive claude analysis (background, no blocking)
ANALYSIS=$(claude -p "$ANALYSIS_PROMPT" --output-format text 2>/dev/null)

[ -z "$ANALYSIS" ] && exit 0

# Parse and append learned patterns to memory file
python3 - "$ANALYSIS" "$PATTERNS_FILE" << 'PYEOF'
import sys, json, re
from datetime import datetime

raw = sys.argv[1].strip()
patterns_file = sys.argv[2]

# Extract JSON array even if there's surrounding text
match = re.search(r'\[.*?\]', raw, re.DOTALL)
if not match:
    sys.exit(0)

try:
    patterns = json.loads(match.group())
    if not patterns or not isinstance(patterns, list):
        sys.exit(0)

    # Read existing content to check for duplicates
    try:
        with open(patterns_file) as f:
            existing = f.read().lower()
    except:
        existing = ""

    new_patterns = []
    for p in patterns[:2]:
        name = p.get('pattern', '').strip()
        if not name or name.lower() in existing:
            continue
        new_patterns.append(p)

    if not new_patterns:
        sys.exit(0)

    with open(patterns_file, 'a') as f:
        f.write(f"\n## Learned {datetime.now().strftime('%Y-%m-%d')}\n\n")
        for p in new_patterns:
            f.write(f"**{p.get('pattern', 'Pattern')}**\n")
            f.write(f"- Avoid: {p.get('example', '')}\n")
            f.write(f"- Instead: {p.get('suggestion', '')}\n")
            f.write(f"- Frequency: {p.get('frequency', 'occasional')}\n\n")

except Exception:
    sys.exit(0)
PYEOF

exit 0
