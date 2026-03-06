---
name: token-optimizer-memory
description: This skill should be used when the user asks to "optimize my prompts", "reduce token usage", "improve prompt efficiency", "teach me to write better prompts", "monitor prompt quality", "install token optimizer", "set up prompt coaching", or wants ongoing feedback on how to write more efficient Claude Code prompts. Installs two hooks: a real-time rule-based analyzer on prompt submit that blocks low-quality prompts with a suggested rewrite, and an AI-powered learning hook on session end that grows a memory of patterns from the user's own sessions.
version: 0.2.0
---

# Token Optimizer Memory

Monitors every user prompt for token efficiency issues and continuously learns from session patterns to give better advice over time.

## Architecture

```
UserPromptSubmit hook → analyze-prompt.sh  (rule-based, instant, zero cost)
        ↓
        0 issues  → silent pass-through
        1+ issues → interactive menu (reads from /dev/tty):
                    [a] Accept  — copy suggestion to clipboard, block for resubmit
                    [e] Edit    — open in $EDITOR, copy result, block for resubmit
                    [i] Ignore  — pass original through unchanged
                    [c] Cancel  — discard the prompt

Stop hook → learn-from-session.sh  (AI-powered, runs after session ends)
        ↓ updates memory/patterns.md with new patterns
        ↓
analyze-prompt.sh reads memory/patterns.md to improve future rule checks
```

The feedback loop: every completed session teaches the analyzer what patterns you personally tend to use, making future suggestions more relevant over time.

## Installation

```bash
bash ~/.claude/skills/token-optimizer-memory/scripts/install-hooks.sh
```

Requires `jq` (`brew install jq`) and `python3`. Idempotent — safe to run multiple times.

## What the Real-Time Analyzer Checks

On every prompt (skips prompts under 25 characters):

1. **Vague task description** — "fix the bug", "make it work", "clean up the code"
2. **Bug report missing details** — bug intent without error message or file:line
3. **Missing file reference** — coding task with no `@file`, directory, or filename
4. **No verification criteria** — implementation without "run tests", expected output, or screenshot
5. **Compound task** — multiple concerns in one prompt that should be sequential
6. **Architectural task without plan mode** — refactor/migrate/redesign without "plan mode" mention
7. **Learned patterns** — cross-checks against `memory/patterns.md` patterns from past sessions

### Response tiers

| Issues found | Behavior |
|---|---|
| 0 | Silent — prompt proceeds immediately |
| 1+ | Interactive menu shown, user chooses how to proceed |

### Interactive menu

When 1 or more issues are found, the hook displays a menu and waits for input:

```
[token-optimizer] Found 2 issue(s):
  1. No file reference — Claude will guess where to make changes
  2. No verification criteria — Claude can't self-check the result

Suggested improvement:
  fix the login bug in @<file-path>. Run tests after to verify.

────────────────────────────────────────────────────────
  [a] Accept  — copy suggestion to clipboard, resubmit it
  [e] Edit    — open suggestion in $EDITOR, then resubmit
  [i] Ignore  — proceed with original prompt unchanged
  [c] Cancel  — discard the prompt

Choice [a/e/i/c] (default: a):
```

| Choice | Result |
|---|---|
| `a` (default) | Improved prompt **replaces the original and executes immediately** — no resubmit needed |
| `e` | Opens `$EDITOR` with suggestion — edit, save, then **execution is interrupted** so you can review before resubmitting manually |
| `i` | Original prompt passes through unchanged |
| `c` | Prompt is discarded |

### Bypass

Prefix any prompt with `skip:` to skip all checks with no menu:
```
skip: fix the bug
```

## What the Learning Hook Does

After every session with 3+ prompts:
- Extracts the last 15 user prompts from the session transcript
- Calls `claude -p` non-interactively with a focused analysis prompt
- Identifies up to 2 new patterns not already in memory
- Appends them to `memory/patterns.md` with date stamp

The learning hook runs in the background after the session ends — it does not block or slow the session.

## Memory File

`memory/patterns.md` starts with seed patterns from best practices and grows with every session. Each entry follows the format:

```
**Pattern name**
- Avoid: bad example
- Instead: concrete improvement
- Frequency: common|occasional
```

To view current memory:
```bash
cat ~/.claude/skills/token-optimizer-memory/memory/patterns.md
```

To reset learned patterns (keeps seed patterns):
```bash
# Edit memory/patterns.md and delete sections below "Seed Patterns"
```

## Uninstalling

Remove from `~/.claude/settings.json`:
- The `UserPromptSubmit` hook entry whose `command` references `analyze-prompt.sh`
- The `Stop` hook entry whose `command` references `learn-from-session.sh`

A backup is saved at `~/.claude/settings.json.bak` on install.

## Additional Resources

- **`references/best-practices.md`** — Distilled token efficiency rules from Claude Code docs and Boris Cherny's guidelines. Used by the learning hook as context for AI analysis.
- **`memory/patterns.md`** — Growing log of patterns learned from your sessions.
- **`scripts/analyze-prompt.sh`** — Full rule set with comments.
- **`scripts/learn-from-session.sh`** — AI analysis and memory update logic.
