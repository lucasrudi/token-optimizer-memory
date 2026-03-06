# Learned Prompt Patterns

This file grows automatically as the token-optimizer-memory skill learns from your sessions.
The analyze-prompt hook uses these patterns to give real-time suggestions.

---

## Seed Patterns (from best practices)

**Vague bug reports**
- Avoid: "fix the bug" / "it's not working"
- Instead: paste the exact error + file path + what "fixed" looks like
- Frequency: common

**Missing verification**
- Avoid: asking Claude to implement without saying how to verify
- Instead: always append "run tests after" or "verify X passes" or paste expected output
- Frequency: common

**No file scope for coding tasks**
- Avoid: "add validation to the form"
- Instead: "add validation to @src/components/SignupForm.tsx, follow the pattern in LoginForm.tsx"
- Frequency: common

**Compound prompt overload**
- Avoid: "add auth + tests + update docs + fix the linter"
- Instead: split into sequential focused prompts, one concern at a time
- Frequency: occasional

**Skipping plan mode on architectural tasks**
- Avoid: asking Claude to implement a multi-file refactor directly
- Instead: "enter plan mode — [describe task]" before implementation
- Frequency: occasional

**Investigation polluting main context**
- Avoid: "investigate how our auth system works and then implement OAuth"
- Instead: "use a subagent to investigate auth, then I'll ask you to implement OAuth"
- Frequency: occasional

**Bloated context from corrections**
- Avoid: correcting Claude 3+ times in one session on the same issue
- Instead: `/clear` after 2 failed corrections, restart with a better prompt
- Frequency: occasional

---
