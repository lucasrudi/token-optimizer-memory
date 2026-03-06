# Contributing to token-optimizer-memory

Contributions are welcome — especially new rule checks, improvements to the learning hook, and corrections to the best-practices reference.

## Ways to Contribute

- **New rule checks** — spotted a common token-wasting pattern not yet covered? Add a rule to `analyze-prompt.sh`
- **Improved learning** — better transcript parsing or smarter AI prompts in `learn-from-session.sh`
- **Best practices** — additions or corrections to `references/best-practices.md`
- **Bug fixes** — the scripts run in every session, correctness matters
- **Documentation** — clearer examples, better README sections

---

## Getting Started

### 1. Fork and clone

```bash
git clone https://github.com/<your-username>/token-optimizer-memory
cd token-optimizer-memory
```

### 2. Link to your local Claude Code skills (for live testing)

```bash
# Symlink into your Claude Code skills directory
ln -sf "$(pwd)" ~/.claude/skills/token-optimizer-memory
bash scripts/install-hooks.sh
```

### 3. Test your changes

The easiest way to test rule changes in `analyze-prompt.sh` is to pipe a mock payload directly:

```bash
echo '{"prompt": "fix the bug", "cwd": "/tmp", "session_id": "test"}' \
  | bash scripts/analyze-prompt.sh
```

For `learn-from-session.sh`, use a real session transcript:

```bash
# Find a recent transcript
ls ~/.claude/projects/*/
# Pipe it
echo "{\"transcript_path\": \"/path/to/transcript.jsonl\", \"session_id\": \"test\"}" \
  | bash scripts/learn-from-session.sh
```

---

## Adding a New Rule to analyze-prompt.sh

Rules live in the Python block inside `analyze-prompt.sh`. Each rule follows the same pattern:

```python
# --- Rule N: Short descriptive name ---
condition = bool(re.search(r'your-regex', prompt, re.IGNORECASE))
if condition and len(prompt) > MIN_LENGTH:
    issues.append("Short tip → concrete suggestion in one line")
```

Guidelines for new rules:

- **False positive rate matters more than recall** — it's better to miss an issue than to nag on a correct prompt
- Keep the tip text under 80 characters, actionable, and specific
- Add a length guard (`len(prompt) > N`) to avoid firing on short prompts
- Test against both a bad example and a good example before submitting

---

## Improving the Learning Hook

`learn-from-session.sh` calls `claude -p` non-interactively. The analysis prompt is the main lever — keep it:

- **Tight** — the prompt sent to Claude should stay under ~500 tokens including context
- **Structured** — JSON output only, no prose, for reliable parsing
- **Duplicate-aware** — the script already checks for existing pattern names; don't remove that check

If you change the output schema, update the Python parser in the same script.

---

## Commit Style

Use the imperative mood in commit messages:

```
Add rule: detect missing plan mode on architectural tasks
Fix: handle empty transcript gracefully in learn-from-session.sh
Improve: tighten compound-task regex to reduce false positives
Docs: add example output to README
```

One concern per commit when possible.

---

## Pull Request Checklist

- [ ] `analyze-prompt.sh` changes tested with at least one bad and one good example prompt
- [ ] `learn-from-session.sh` changes tested with a real or mock transcript
- [ ] No new dependencies added (bash, python3, and jq are the only allowed deps)
- [ ] `install-hooks.sh` still passes if you changed any file paths
- [ ] README updated if behavior visible to users changed

---

## Reporting Issues

Open a [GitHub issue](https://github.com/lucasrudi/token-optimizer-memory/issues) with:

- The prompt that triggered a false positive (or failed to trigger a true positive)
- Your OS and shell (`uname -a`, `echo $SHELL`)
- Output of `python3 --version` and `jq --version`
