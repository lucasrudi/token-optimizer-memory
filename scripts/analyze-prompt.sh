#!/usr/bin/env bash
# UserPromptSubmit hook — analyzes prompt for token efficiency issues.
#
# Behavior:
#   0 issues → silent pass-through
#   1+ issues → interactive menu (reads from /dev/tty):
#     [a] Accept  — copy suggested rewrite to clipboard, block for resubmit
#     [e] Edit    — open suggestion in $EDITOR, copy result, block for resubmit
#     [i] Ignore  — pass original prompt through unchanged
#     [c] Cancel  — discard the prompt entirely
#
# Bypass: prefix your prompt with "skip:" to skip all checks.

INPUT=$(cat)

# Extract prompt safely via stdin pipe — never via shell interpolation
PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('prompt', ''))
except Exception:
    pass
" 2>/dev/null)

# Skip very short prompts
[ "${#PROMPT}" -lt 25 ] && exit 0

SKILL_DIR="$HOME/.claude/skills/token-optimizer-memory"
PATTERNS_FILE="$SKILL_DIR/memory/patterns.md"

# Export prompt and config via env vars — safe from shell injection in heredoc
export HOOK_PROMPT="$PROMPT"
export HOOK_PATTERNS_FILE="$PATTERNS_FILE"

# ── Run rule-based analysis ───────────────────────────────────────────────────
# Heredoc delimiter is quoted ('PYEOF') to prevent shell expansion inside block.
# All prompt access via os.environ — never string-interpolated into source.
ANALYSIS=$(python3 - << 'PYEOF'
import sys, re, json, os

prompt = os.environ.get('HOOK_PROMPT', '')
patterns_file = os.environ.get('HOOK_PATTERNS_FILE', '')

# Bypass check
if re.match(r'^skip:\s*', prompt, re.IGNORECASE):
    print(json.dumps({"action": "pass"}))
    sys.exit(0)

issues = []
fixes  = []  # parallel list — always append to both together

# Rule 1: Vague task description
vague_patterns = [
    r'^\s*(please\s+)?(fix|look at|check|handle|deal with)\s+(the\s+)?(bug|issue|problem|error|thing)\s*[.!?]?\s*$',
    r'^\s*(make|get)\s+(it|this)\s+(work|better|faster|cleaner)\s*[.!?]?\s*$',
    r'^\s*(help me|can you help|i need help)\s+with\b',
    r'^\s*(update|improve|clean up|refactor)\s+(the\s+|my\s+)?(code|it|this)\s*[.!?]?\s*$',
]
for p in vague_patterns:
    if re.search(p, prompt, re.IGNORECASE):
        issues.append("Vague task — Claude can't infer intent without specifics")
        fixes.append("describe the exact outcome you want and what 'done' looks like")
        break

# Rule 2: Bug report missing error details
has_bug_intent = bool(re.search(r'\b(fix|debug|broken|failing|error|bug|crash|not working)\b', prompt, re.IGNORECASE))
has_error_detail = bool(re.search(r'(Error:|Exception:|line \d+|:\d+|\bat\s+\w|stack trace|@[a-zA-Z]|\.[a-z]{2,4}:\d)', prompt))
if has_bug_intent and not has_error_detail and len(prompt) < 150:
    issues.append("Bug report missing details — no error message or file:line")
    fixes.append("paste-the-exact-error-plus-fileline")  # sentinel used in hint builder below

# Rule 3: Coding task without file reference
code_verbs = r'\b(implement|add|create|write|build|refactor|change|update|fix|migrate|convert)\b'
has_code_intent = bool(re.search(code_verbs, prompt, re.IGNORECASE))
has_file_ref = bool(re.search(r'(@\w|src/|lib/|app/|\.[a-z]{2,4}\b|in the \w+ (file|module|component)|in \w+\.)', prompt, re.IGNORECASE))
if has_code_intent and not has_file_ref and 25 < len(prompt) < 200:
    issues.append("No file reference — Claude will guess where to make changes")
    fixes.append("add-file-ref")  # sentinel

# Rule 4: No verification criteria
has_impl_intent = bool(re.search(r'\b(implement|build|create|write|add|fix)\b', prompt, re.IGNORECASE))
has_verify = bool(re.search(r'\b(test|verify|check|run|confirm|assert|validate|screenshot|output|expect|should (pass|work|return))\b', prompt, re.IGNORECASE))
if has_impl_intent and not has_verify and len(prompt) > 40:
    issues.append("No verification criteria — Claude can't self-check the result")
    fixes.append("add-verification")  # sentinel

# Rule 5: Compound task
compound_markers = [' and then ', ' also ', ' additionally ', ' plus ', ' as well as ', ' and also ']
has_compound = any(m in prompt.lower() for m in compound_markers)
and_count = len(re.findall(r'\band\b', prompt, re.IGNORECASE))
if (has_compound or and_count >= 3) and len(prompt) > 80:
    issues.append("Compound task — multiple concerns dilute focus and fill context faster")
    fixes.append("add-sequential")  # sentinel

# Rule 6: Architectural task without plan mode
arch_kw = r'\b(architect|redesign|rewrite|overhaul|migrate|refactor|restructure|integrate)\b'
if re.search(arch_kw, prompt, re.IGNORECASE) and len(prompt) > 100:
    if 'plan mode' not in prompt.lower() and 'plan first' not in prompt.lower():
        issues.append("Architectural task without plan mode — risks solving the wrong problem")
        fixes.append("add-plan-mode")  # sentinel

# Learned patterns cross-check (fixed: actually appends issues when matched)
try:
    with open(patterns_file) as f:
        memory_content = f.read()
    avoid_lines   = re.findall(r'- Avoid: (.+)', memory_content)
    instead_lines = re.findall(r'- Instead: (.+)', memory_content)
    for i, avoid in enumerate(avoid_lines[:15]):
        keywords = [w.lower() for w in re.findall(r'\b\w{4,}\b', avoid)
                    if w.lower() not in ('avoid', 'that', 'this', 'with', 'from', 'into', 'your')]
        if len(keywords) >= 2:
            match_count = sum(1 for kw in keywords if kw in prompt.lower())
            if match_count >= 2 and len(issues) < 6:
                instead = instead_lines[i] if i < len(instead_lines) else "see memory/patterns.md"
                issues.append(f"Matches a pattern from your history: {avoid[:60]}")
                fixes.append(f"learned:{instead[:80]}")
                break
except Exception:
    pass

# Deduplicate (issues and fixes always stay in sync)
seen, unique_issues, unique_fixes = set(), [], []
for issue, fix in zip(issues, fixes):
    key = issue[:35]
    if key not in seen:
        seen.add(key)
        unique_issues.append(issue)
        unique_fixes.append(fix)
issues, fixes = unique_issues[:4], unique_fixes[:4]

if not issues:
    print(json.dumps({"action": "pass"}))
    sys.exit(0)

# Build suggested rewrite using sentinels (no substring collision risk)
improved = prompt.rstrip().rstrip('.')
additions = []
plan_mode_added = False

for fix in fixes:
    if fix == "add-plan-mode" and not plan_mode_added:
        improved = "Enter plan mode — " + improved
        plan_mode_added = True
    elif fix == "paste-the-exact-error-plus-fileline":
        additions.append("[paste exact error + file:line]")
    elif fix == "add-file-ref":
        additions.append("in @<file-path>")
    elif fix == "add-verification":
        additions.append("Run tests after to verify.")
    elif fix == "add-sequential":
        additions.append("(focus: first concern only)")
    elif fix.startswith("learned:"):
        additions.append(f"({fix[8:]})")
    else:
        additions.append(f"({fix})")

if additions:
    improved = improved + " " + " ".join(additions)

print(json.dumps({
    "action":   "prompt",
    "count":    len(issues),
    "issues":   issues,
    "improved": improved,
}))
PYEOF
)

# ── Parse analysis result ─────────────────────────────────────────────────────
ACTION=$(printf '%s' "$ANALYSIS" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('action', 'pass'))
except Exception:
    print('pass')
" 2>/dev/null)

[ "$ACTION" = "pass" ] && exit 0

ISSUE_COUNT=$(printf '%s' "$ANALYSIS" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('count', 0))
except Exception:
    print(0)
" 2>/dev/null)

ISSUES_TEXT=$(printf '%s' "$ANALYSIS" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    for i, issue in enumerate(d.get('issues', []), 1):
        print(f'  {i}. {issue}')
except Exception:
    pass
" 2>/dev/null)

IMPROVED=$(printf '%s' "$ANALYSIS" | python3 -c "
import sys, json
try:
    print(json.loads(sys.stdin.read()).get('improved', ''))
except Exception:
    pass
" 2>/dev/null)

# ── Display issues + menu via stderr ─────────────────────────────────────────
{
    printf '\n\033[33m[token-optimizer]\033[0m Found %s issue(s):\n' "$ISSUE_COUNT"
    printf '%s\n' "$ISSUES_TEXT"
    printf '\n\033[36mSuggested improvement:\033[0m\n'
    printf '  %s\n' "$IMPROVED"
    printf '\n\033[90m%s\033[0m\n' "────────────────────────────────────────────────────────"
    printf '  \033[1m[a]\033[0m Accept  — apply suggestion and continue immediately\n'
    printf '  \033[1m[e]\033[0m Edit    — open suggestion in $EDITOR, then interrupt for review\n'
    printf '  \033[1m[i]\033[0m Ignore  — proceed with original prompt unchanged\n'
    printf '  \033[1m[c]\033[0m Cancel  — discard the prompt\n'
    printf '\nChoice [a/e/i/c] (default: a): '
} >&2

# Read user choice from terminal (works even when stdin is redirected)
CHOICE=""
if { true </dev/tty; } 2>/dev/null; then
    read -r CHOICE </dev/tty
fi
CHOICE=$(printf '%s' "${CHOICE:-a}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

# ── Helpers: file-based JSON emission (no stdout size limits, no injection risk)
#
# Content is written to temp files on the filesystem; Python reads them and
# serializes to JSON. This handles arbitrarily large prompts and multi-file
# edits without any string-passing constraints.

# emit_replace FILE — outputs {"modifiedPrompt": <file contents>}
# Claude Code replaces the user's prompt with the file contents and executes.
emit_replace() {
    local file="$1"
    python3 - "$file" << 'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    content = f.read().rstrip('\n')
print(json.dumps({'modifiedPrompt': content}))
PYEOF
}

# emit_block FILE [PREFIX] — outputs {"decision": "block", "reason": ...}
# Interrupts execution; user reads the file contents and resubmits manually.
emit_block() {
    local file="$1"
    local prefix="${2:-}"
    python3 - "$file" "$prefix" << 'PYEOF'
import sys, json
file_path = sys.argv[1]
prefix    = sys.argv[2] if len(sys.argv) > 2 else ""
with open(file_path) as f:
    content = f.read().rstrip('\n')
reason = f"{prefix}\n\n{content}" if prefix else content
print(json.dumps({'decision': 'block', 'reason': reason}))
PYEOF
}

# ── Write improved prompt to a file on disk ───────────────────────────────────
IMPROVED_FILE=$(mktemp /tmp/token-optimizer-XXXXXX.md)
printf '%s' "$IMPROVED" > "$IMPROVED_FILE"

# ── Handle choice ─────────────────────────────────────────────────────────────
case "$CHOICE" in
    a|"")
        # Accept: write improved prompt to disk, Claude executes it directly via
        # modifiedPrompt — no stdout string size constraints, no clipboard needed.
        printf '\033[32m[token-optimizer] Applying suggestion and continuing.\033[0m\n\n' >&2
        emit_replace "$IMPROVED_FILE"
        rm -f "$IMPROVED_FILE"
        ;;
    e)
        # Edit: open the improved prompt file in $EDITOR so the user can freely
        # modify it (including across multiple files if needed). After saving,
        # execution is interrupted — user resubmits the edited prompt manually.
        "${EDITOR:-nano}" "$IMPROVED_FILE" </dev/tty >/dev/tty
        printf '\033[33m[token-optimizer] Execution interrupted — resubmit when ready.\033[0m\n\n' >&2
        emit_block "$IMPROVED_FILE" "Your edited prompt (resubmit to proceed):"
        rm -f "$IMPROVED_FILE"
        ;;
    i)
        # Ignore: pass original through unchanged
        rm -f "$IMPROVED_FILE"
        printf '\033[90m[token-optimizer] Proceeding with original prompt.\033[0m\n\n' >&2
        exit 0
        ;;
    c|*)
        # Cancel: discard the prompt
        rm -f "$IMPROVED_FILE"
        printf '\033[31mPrompt cancelled.\033[0m\n\n' >&2
        python3 -c "import json; print(json.dumps({'decision': 'block', 'reason': 'Prompt cancelled.'}))"
        ;;
esac

exit 0
