#!/usr/bin/env bash
# UserPromptSubmit hook — analyzes prompt for token efficiency issues.
# Outputs real-time suggestions to stderr (shown as notifications in Claude Code).
# Rule-based: fast, zero cost, zero latency.

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null)

# Skip short prompts (greetings, one-word commands, clarifications)
LENGTH=${#PROMPT}
[ "$LENGTH" -lt 25 ] && exit 0

SKILL_DIR="$HOME/.claude/skills/token-optimizer-memory"
PATTERNS_FILE="$SKILL_DIR/memory/patterns.md"

python3 - << PYEOF
import sys, re

prompt = """$PROMPT"""
patterns_file = "$PATTERNS_FILE"
issues = []

# --- Rule 1: Vague task description ---
vague_patterns = [
    r'^\s*(please\s+)?(fix|look at|check|handle|deal with)\s+(the\s+)?(bug|issue|problem|error|thing)\s*$',
    r'^\s*(make|get)\s+(it|this)\s+(work|better|faster|cleaner)\s*$',
    r'^\s*(help me|can you help|i need help)\s+with\b',
    r'^\s*(update|improve|clean up|refactor)\s+(the\s+|my\s+)?(code|it|this)\s*$',
]
for pattern in vague_patterns:
    if re.search(pattern, prompt, re.IGNORECASE):
        issues.append("Vague task → specify exact file path + error message + what 'done' looks like")
        break

# --- Rule 2: Bug/error report missing details ---
has_bug_intent = bool(re.search(r'\b(fix|debug|broken|failing|error|bug|crash|not working)\b', prompt, re.IGNORECASE))
has_error_detail = bool(re.search(r'(Error:|Exception:|line \d+|:\d+|stack trace|at src|@[a-zA-Z]|\.ts:|\.py:|\.js:)', prompt))
if has_bug_intent and not has_error_detail and len(prompt) < 150:
    issues.append("Bug report missing details → paste the exact error + file:line + reproduce steps")

# --- Rule 3: Coding task without file reference ---
code_verbs = r'\b(implement|add|create|write|build|refactor|change|update|fix|migrate|convert)\b'
has_code_intent = bool(re.search(code_verbs, prompt, re.IGNORECASE))
has_file_ref = bool(re.search(r'(@\w|src/|lib/|app/|\.[a-z]{2,4}\b|in the \w+ file|in \w+\.)', prompt, re.IGNORECASE))
if has_code_intent and not has_file_ref and 25 < len(prompt) < 200:
    issues.append("No file reference → use @ to point to files (e.g. '@src/auth.ts') or name the directory")

# --- Rule 4: No verification criteria on implementation task ---
has_impl_intent = bool(re.search(r'\b(implement|build|create|write|add|fix)\b', prompt, re.IGNORECASE))
has_verify = bool(re.search(r'\b(test|verify|check|run|confirm|assert|validate|screenshot|output|expect|should (pass|work|return))\b', prompt, re.IGNORECASE))
if has_impl_intent and not has_verify and len(prompt) > 40:
    issues.append("No verification → append: 'run tests after' or describe expected output")

# --- Rule 5: Compound task (multiple concerns) ---
compound_markers = [' and then ', ' also ', ' additionally ', ' plus ', ' as well as ', ' and also ']
has_compound = any(m in prompt.lower() for m in compound_markers)
and_count = len(re.findall(r'\band\b', prompt, re.IGNORECASE))
if (has_compound or and_count >= 3) and len(prompt) > 80:
    issues.append("Compound task → split into sequential prompts, one concern per prompt")

# --- Rule 6: Large architectural task without plan mode ---
arch_keywords = r'\b(architect|redesign|rewrite|overhaul|migrate|refactor|restructure|integrate)\b'
if re.search(arch_keywords, prompt, re.IGNORECASE) and len(prompt) > 100:
    if 'plan mode' not in prompt.lower() and 'plan first' not in prompt.lower():
        issues.append("Architectural task → prefix with 'enter plan mode — ' to avoid solving the wrong problem")

# --- Cross-check against learned patterns in memory ---
try:
    with open(patterns_file) as f:
        memory_content = f.read()
    # Look for "Avoid:" lines in memory and check if prompt matches
    avoid_lines = re.findall(r'- Avoid: (.+)', memory_content)
    for avoid in avoid_lines[:15]:  # cap to avoid slowdown
        # Simple keyword match from the avoid example
        keywords = [w.lower() for w in re.findall(r'\b\w{4,}\b', avoid) if w.lower() not in ('avoid', 'that', 'this', 'with', 'from', 'into')]
        if len(keywords) >= 2:
            match_count = sum(1 for kw in keywords if kw in prompt.lower())
            if match_count >= 2:
                # Don't duplicate already-found issues
                break
except:
    pass

# --- Output ---
if issues:
    # Deduplicate
    seen = set()
    unique_issues = []
    for issue in issues:
        key = issue[:30]
        if key not in seen:
            seen.add(key)
            unique_issues.append(issue)

    print("\033[33m[token-optimizer]\033[0m Prompt efficiency tips:", file=sys.stderr)
    for issue in unique_issues[:3]:
        print(f"  • {issue}", file=sys.stderr)
    print("", file=sys.stderr)

sys.exit(0)
PYEOF

exit 0
