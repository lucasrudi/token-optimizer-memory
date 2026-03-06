#!/usr/bin/env bash
# UserPromptSubmit hook — analyzes prompt for token efficiency issues.
#
# Behavior:
#   0 issues  → allow through silently
#   1 issue   → warn to stderr, allow through
#   2+ issues → BLOCK with suggested improved prompt + bypass instructions
#
# Bypass: prefix your prompt with "skip:" to skip all checks.

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null)

# Skip very short prompts
LENGTH=${#PROMPT}
[ "$LENGTH" -lt 25 ] && exit 0

SKILL_DIR="$HOME/.claude/skills/token-optimizer-memory"
PATTERNS_FILE="$SKILL_DIR/memory/patterns.md"

python3 - << PYEOF
import sys, re, json

prompt = """$PROMPT"""
patterns_file = "$PATTERNS_FILE"

# ── Bypass ────────────────────────────────────────────────────────────────────
if re.match(r'^skip:\s*', prompt, re.IGNORECASE):
    sys.exit(0)

issues = []      # short tip strings
fixes  = []      # parallel concrete fix hints for prompt rewrite

# ── Rule 1: Vague task description ───────────────────────────────────────────
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

# ── Rule 2: Bug report missing details ───────────────────────────────────────
has_bug_intent = bool(re.search(r'\b(fix|debug|broken|failing|error|bug|crash|not working)\b', prompt, re.IGNORECASE))
has_error_detail = bool(re.search(r'(Error:|Exception:|line \d+|:\d+|\bat\s+\w|stack trace|@[a-zA-Z]|\.[a-z]{2,4}:\d)', prompt))
if has_bug_intent and not has_error_detail and len(prompt) < 150:
    issues.append("Bug report missing details — no error message or file:line")
    fixes.append("paste the exact error + file:line + steps to reproduce")

# ── Rule 3: Coding task without file reference ────────────────────────────────
code_verbs = r'\b(implement|add|create|write|build|refactor|change|update|fix|migrate|convert)\b'
has_code_intent = bool(re.search(code_verbs, prompt, re.IGNORECASE))
has_file_ref = bool(re.search(r'(@\w|src/|lib/|app/|\.[a-z]{2,4}\b|in the \w+ (file|module|component)|in \w+\.)', prompt, re.IGNORECASE))
if has_code_intent and not has_file_ref and 25 < len(prompt) < 200:
    issues.append("No file reference — Claude will guess where to make changes")
    fixes.append("add @<file-path> or name the exact file/directory")

# ── Rule 4: No verification criteria ─────────────────────────────────────────
has_impl_intent = bool(re.search(r'\b(implement|build|create|write|add|fix)\b', prompt, re.IGNORECASE))
has_verify = bool(re.search(r'\b(test|verify|check|run|confirm|assert|validate|screenshot|output|expect|should (pass|work|return))\b', prompt, re.IGNORECASE))
if has_impl_intent and not has_verify and len(prompt) > 40:
    issues.append("No verification criteria — Claude can't self-check the result")
    fixes.append('append "run tests after" or describe the expected output')

# ── Rule 5: Compound task ────────────────────────────────────────────────────
compound_markers = [' and then ', ' also ', ' additionally ', ' plus ', ' as well as ', ' and also ']
has_compound = any(m in prompt.lower() for m in compound_markers)
and_count = len(re.findall(r'\band\b', prompt, re.IGNORECASE))
if (has_compound or and_count >= 3) and len(prompt) > 80:
    issues.append("Compound task — multiple concerns dilute focus and fill context faster")
    fixes.append("split into sequential prompts, one concern at a time")

# ── Rule 6: Architectural task without plan mode ─────────────────────────────
arch_kw = r'\b(architect|redesign|rewrite|overhaul|migrate|refactor|restructure|integrate)\b'
if re.search(arch_kw, prompt, re.IGNORECASE) and len(prompt) > 100:
    if 'plan mode' not in prompt.lower() and 'plan first' not in prompt.lower():
        issues.append("Architectural task without plan mode — risks solving the wrong problem")
        fixes.append('prefix with "enter plan mode — " before describing the task')

# ── Cross-check learned memory patterns ──────────────────────────────────────
try:
    with open(patterns_file) as f:
        memory_content = f.read()
    avoid_lines = re.findall(r'- Avoid: (.+)', memory_content)
    for avoid in avoid_lines[:15]:
        keywords = [w.lower() for w in re.findall(r'\b\w{4,}\b', avoid)
                    if w.lower() not in ('avoid', 'that', 'this', 'with', 'from', 'into', 'your')]
        if len(keywords) >= 2:
            match_count = sum(1 for kw in keywords if kw in prompt.lower())
            if match_count >= 2 and len(issues) < 6:
                break
except Exception:
    pass

# ── Deduplicate ───────────────────────────────────────────────────────────────
seen, unique_issues, unique_fixes = set(), [], []
for issue, fix in zip(issues, fixes):
    key = issue[:35]
    if key not in seen:
        seen.add(key)
        unique_issues.append(issue)
        unique_fixes.append(fix)

issues, fixes = unique_issues[:4], unique_fixes[:4]

# ── No issues → silent pass ───────────────────────────────────────────────────
if not issues:
    sys.exit(0)

# ── 1 issue → warn to stderr, allow through ──────────────────────────────────
if len(issues) == 1:
    print(f"\033[33m[token-optimizer]\033[0m Tip: {issues[0]}", file=sys.stderr)
    print(f"  → {fixes[0]}", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(0)

# ── 2+ issues → BLOCK with suggested rewrite ─────────────────────────────────

# Build a concrete suggested prompt by annotating the original
improved = prompt.rstrip().rstrip('.')
additions = []
for fix in fixes:
    # Extract the actionable part as a parenthetical hint
    if 'file' in fix.lower() or '@' in fix:
        additions.append("in @<file-path>")
    elif 'run tests' in fix.lower():
        additions.append("Run tests after to verify.")
    elif 'error' in fix.lower() or 'reproduce' in fix.lower():
        additions.append("[paste exact error + file:line]")
    elif 'plan mode' in fix.lower():
        improved = "Enter plan mode — " + improved
    elif 'expected output' in fix.lower():
        additions.append("Expected output: <describe>.")
    elif 'sequential' in fix.lower() or 'split' in fix.lower():
        additions.append("(focus: first concern only)")

if additions:
    improved = improved + " " + " ".join(additions)

# Format block message
lines = []
lines.append(f"Issues detected ({len(issues)}):")
for issue in issues:
    lines.append(f"  • {issue}")
lines.append("")
lines.append("Suggested improvement:")
lines.append(f"  {improved}")
lines.append("")
lines.append("─" * 55)
lines.append("Resubmit the improved prompt above, or prefix your")
lines.append("original with  skip:  to proceed without changes.")

reason = "\n".join(lines)
print(json.dumps({"decision": "block", "reason": reason}))
sys.exit(0)
PYEOF

exit 0
