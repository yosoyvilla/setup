---
name: fix-issue
description: Use when resolving a GitHub issue end-to-end — reads the issue, implements the fix, tests, and creates a PR. Works across all projects.
user-invocable: true
disable-model-invocation: true
---

Fix GitHub issue: $ARGUMENTS

## 1. Understand
```bash
gh issue view $ARGUMENTS
gh issue list --search "related terms"   # check for related issues
```
Identify affected components, root cause, and whether a test already covers this area.

## 2. Branch
```bash
git checkout -b fix/$ARGUMENTS
# For larger or riskier fixes, use a worktree for isolation:
# claude --worktree fix-$ARGUMENTS
```

## 3. Investigate
Search the codebase for affected files. Understand root cause before writing any code. Check project CLAUDE.md for conventions specific to this repo.

## 4. Spec (required before any code)
Use the `spec-driven-development` skill. For a bug fix, the spec is brief but must include:
- **Root cause**: one sentence
- **Fix approach**: what changes and why not the alternative
- **Acceptance criteria**: specific, testable — e.g. "endpoint returns 200 with X field" not "bug is fixed"
- **Regression risk**: what existing behavior could break

## 5. Implement
Minimal fix that addresses the issue. No unrelated cleanup.

## 6. Test

**CedarPlanters (pnpm monorepo):** `pnpm test` or `pnpm -F <package> test`

**Varsity (Go):** `go test ./...` in affected package(s)

**360latam (PHP):** check project Makefile or CI script for test command

**360latam (Python/FincaRaiz):** `pytest`

**Personal/Crewgent:** `pytest` (backend) / `pnpm test` (frontend)

Add tests for the fix if coverage is missing.

## 7. Verify
```bash
git diff --stat   # only relevant files changed — no unrelated noise
```

Lint + type check per project:

**CedarPlanters:** `pnpm lint && pnpm typecheck`

**Varsity (Go):** `golangci-lint run ./...`

**360latam (Python/FincaRaiz):** `ruff check .` or `flake8`

**360latam (PHP):** check CI config for lint command (phpstan, phpcs)

**Personal/Crewgent:** `ruff check .` (backend) / `pnpm typecheck` (frontend)

## 8. Commit + PR
```bash
git push -u origin fix/$ARGUMENTS
gh pr create \
  --title "Fix #$ARGUMENTS: <description>" \
  --body "Closes #$ARGUMENTS

## Changes
<summary>

## Test Plan
<how to verify>"
```
