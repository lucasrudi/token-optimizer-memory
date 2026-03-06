# token-optimizer-memory

A [Claude Code](https://claude.ai/code) skill that monitors your prompts for token efficiency issues in real time and continuously learns from your sessions to give better advice over time.

## How It Works

Two hooks run automatically in every Claude Code session:

```
You submit a prompt
    ↓
UserPromptSubmit hook → analyze-prompt.sh (instant, zero cost)
    ↓
    0 issues  → silent pass-through
    1+ issues → interactive menu shown (reads from /dev/tty):
                [a] Accept  — copy suggestion to clipboard, resubmit
                [e] Edit    — open $EDITOR with suggestion, copy result
                [i] Ignore  — pass original prompt through
                [c] Cancel  — discard the prompt

Claude finishes the session
    ↓
Stop hook → learn-from-session.sh
    ↓ reads session transcript
    ↓ calls claude -p to extract your personal prompt patterns
    ↓ appends new patterns to memory/patterns.md

Next session
    ↓ analyzer is smarter — cross-checks your own habits from memory
```

The feedback loop compounds: the more you use Claude Code, the more tailored the suggestions become.

---

## What Gets Checked

The real-time analyzer catches 6 categories of token waste on every prompt (skips prompts under 25 characters):

| Check | Anti-pattern | Fix |
|---|---|---|
| Vague task | "fix the bug" / "make it work" | Specify file path + error + what done looks like |
| Missing error details | Bug intent with no error message or file:line | Paste exact error + reproduce steps |
| No file reference | Coding task with no `@file` or directory | Use `@src/auth.ts` or name the file |
| No verification | Implement without success criteria | Append "run tests after" or expected output |
| Compound task | Multiple concerns in one prompt | Split into sequential focused prompts |
| Architectural task | Refactor/migrate without plan mode | Prefix with "enter plan mode — " |

### Response tiers

| Issues found | Behavior |
|---|---|
| 0 | Silent — prompt proceeds immediately |
| 1+ | Interactive menu — user chooses what to do |

### Interactive menu

When any issue is found, the hook pauses and shows a menu:

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

| Choice | What happens |
|---|---|
| `a` (default, Enter) | Improved prompt **replaces the original and executes immediately** via `modifiedPrompt` — no resubmit needed |
| `e` | Opens `$EDITOR` (falls back to `nano`) — edit and save, then **execution is interrupted** so you can review your edit before resubmitting manually |
| `i` | Original prompt passes through to Claude unchanged |
| `c` | Prompt is discarded |

### Bypass

Prefix any prompt with `skip:` to skip all checks with no menu:
```
skip: fix the bug
```

---

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/code) installed
- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `python3` — standard on macOS and most Linux distros

### Option A — Install via skills CLI (recommended)

```bash
npx skills add https://github.com/lucasrudi/token-optimizer-memory -g -y
bash ~/.claude/skills/token-optimizer-memory/scripts/install-hooks.sh
```

### Option B — Clone manually

```bash
git clone https://github.com/lucasrudi/token-optimizer-memory \
  ~/.claude/skills/token-optimizer-memory
bash ~/.claude/skills/token-optimizer-memory/scripts/install-hooks.sh
```

The install script is idempotent — safe to run multiple times. It adds two entries to `~/.claude/settings.json` and backs up the original.

### Verify installation

```bash
# Check hooks are registered
jq '.hooks' ~/.claude/settings.json

# Check memory file exists
cat ~/.claude/skills/token-optimizer-memory/memory/patterns.md
```

Start a new Claude Code session — the analyzer is active immediately.

---

## File Structure

```
token-optimizer-memory/
├── SKILL.md                      ← Claude Code skill manifest
├── README.md                     ← this file
├── CONTRIBUTING.md
├── LICENSE
├── memory/
│   └── patterns.md               ← grows automatically each session
├── references/
│   └── best-practices.md         ← distilled from Claude Code docs + Boris Cherny's guidelines
└── scripts/
    ├── analyze-prompt.sh          ← UserPromptSubmit hook (rule-based, instant)
    ├── learn-from-session.sh      ← Stop hook (AI-powered, background)
    └── install-hooks.sh           ← registers both hooks in settings.json
```

---

## Memory File

`memory/patterns.md` starts with 7 seed patterns from best practices and grows with every session. Each entry:

```markdown
**Pattern name**
- Avoid: bad example in a few words
- Instead: concrete improvement
- Frequency: common|occasional
```

### View your patterns

```bash
cat ~/.claude/skills/token-optimizer-memory/memory/patterns.md
```

### Reset learned patterns (keeps seed patterns)

Open `memory/patterns.md` and delete all sections dated below `## Seed Patterns`.

---

## Uninstalling

### Remove hooks

Open `~/.claude/settings.json` and delete:
- The `UserPromptSubmit` hook entry whose `command` contains `analyze-prompt.sh`
- The `Stop` hook entry whose `command` contains `learn-from-session.sh`

A backup of your pre-install settings is at `~/.claude/settings.json.bak`.

### Remove skill files

```bash
rm -rf ~/.claude/skills/token-optimizer-memory
```

---

## Best Practices Reference

The skill is grounded in two sources:

- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — official Anthropic guide on context management, verification criteria, plan mode, and subagents
- [Boris Cherny's Claude Code guidelines](https://github.com/ThaddaeusSandidge/BorisChernyClaudeMarkdown/blob/main/CLAUDE.md) — battle-tested rules from Anthropic engineering

Key principles distilled into the analyzer:

- **Context window is the scarcest resource** — every vague prompt wastes tokens on corrections
- **Verification criteria is the single highest-leverage addition** to any implementation prompt
- **Plan mode before architectural tasks** prevents solving the wrong problem at scale
- **Subagents for investigation** keep main context clean for implementation
- **One concern per prompt** — compound prompts degrade output quality

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
