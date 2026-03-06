# Token Efficiency Best Practices for Claude Code

## Core Principle
Context window is the most constrained resource. Every wasted token degrades performance.

## Prompt Specificity Rules

| Anti-pattern | Better |
|---|---|
| "fix the bug" | "login fails with TokenExpiredError at src/auth/refresh.ts:42 — fix root cause, run tests" |
| "add tests for foo.py" | "write tests for foo.py covering the logged-out edge case, no mocks" |
| "make the dashboard better" | "[paste screenshot] implement this design, screenshot result, list differences, fix them" |
| "the build is failing" | "build fails with: [paste error]. fix root cause, don't suppress the error, verify build passes" |
| "add a calendar widget" | "follow HotDogWidget.php pattern, implement a calendar widget for month selection with prev/next year nav" |

## Verification Criteria (highest leverage)
Always include how Claude should verify the result:
- "run the tests after"
- "verify the build passes"
- "compare screenshot to original"
- "assert output matches: [expected]"
Without verification, Claude ships plausible-looking but broken code.

## Scoping
- Reference specific files: `@src/auth.ts`, `in src/middleware/`
- Mention constraints: "no new dependencies", "follow existing patterns", "avoid mocks"
- State what done looks like: "all 3 existing tests should still pass"

## Context Management
- `/clear` between unrelated tasks — accumulated irrelevant context degrades output
- After 2+ failed corrections: `/clear` and rewrite prompt with what you learned
- For exploration: use subagents ("use a subagent to investigate X") — keeps main context clean
- For complex features: use plan mode first to avoid solving the wrong problem

## Compound Tasks
Split compound prompts into sequential ones:
- Bad: "add auth, also add tests, and update the docs"
- Good: Prompt 1: "add JWT auth to /login endpoint" → Prompt 2: "write tests for the new /login endpoint" → Prompt 3: "update docs/api.md with the new endpoint"

## CLAUDE.md Discipline
- Keep CLAUDE.md < 50 lines of actual rules
- Each rule must pass: "would removing this cause Claude to make mistakes?"
- Move detailed domain knowledge to skills, not CLAUDE.md
- Bloated CLAUDE.md causes Claude to ignore all of it

## Plan Mode Triggers
Use plan mode when:
- Task touches 3+ files
- Architectural decision involved
- You're unfamiliar with the code being modified
- The diff can't be described in one sentence

Skip plan mode when:
- Fixing a typo, adding a log line, renaming a variable
- Scope is completely clear

## Interview Pattern (for large features)
Instead of a long spec prompt:
"I want to build [brief description]. Interview me using AskUserQuestion tool. Cover technical implementation, UI/UX, edge cases, tradeoffs. Don't ask obvious questions. Then write a complete spec to SPEC.md."
Then start a fresh session with the spec.

## Subagents for Investigation
Instead of: "investigate how our auth system handles token refresh"
Use: "use a subagent to investigate how auth handles token refresh and report back"
This keeps main context clean for implementation.
