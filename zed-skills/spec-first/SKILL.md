---
name: spec-first
description: Write a spec before implementing any non-trivial change. Use when planning code features, infrastructure updates, deployments, or migrations to define acceptance criteria and rollback plan before writing a line of code.
---

# Spec-First Development

Write the spec in the conversation before touching any code or infrastructure. Implementation starts only after the spec is written and reviewed.

**When to use:** Any change touching more than one file, any infra/config change, any deployment to production. Skip for single-line fixes and typo corrections.

---

## Spec Template — Code / Feature

```markdown
## What
[One sentence: what are we building or changing?]

## Why
[Why now? What problem does this solve? What happens if we don't do it?]

## Approach
[Chosen approach in 2-3 sentences]

### Alternatives considered
- [Alt 1] — rejected because: [reason]
- [Alt 2] — rejected because: [reason]

## Files affected
- `path/to/file.ts` — [what changes]
- `path/to/other.py` — [what changes]

## Acceptance criteria
- [ ] [Specific, testable criterion]
- [ ] [e.g., "POST /api/endpoint returns 201 with valid body"]
- [ ] [e.g., "existing tests still pass"]
- [ ] [e.g., "no new lint errors"]

## Out of scope
[What we are explicitly NOT doing, to prevent scope creep]
```

---

## Spec Template — Infrastructure / Terraform

```markdown
## What
[One sentence: resource or config being changed]

## Current state
[What exists today — resource name, config values, counts]

## Target state
[What it should look like after — specific values, not "better"]

## Resources affected
- [aws_rds_instance.name] — [what changes]
- [aws_security_group.name] — [what changes]

## Acceptance criteria
- [ ] `terraform plan` shows only expected changes (no unexpected destroys)
- [ ] OPA/tflint passes
- [ ] [Service-specific check, e.g., "RDS endpoint resolves from app pod"]
- [ ] [Monitoring check, e.g., "no alerts fire 5 min post-apply"]

## Rollback plan
[Exact steps to revert: git revert + push, or specific terraform state commands]

## Risk
[What could go wrong: downtime window, data risk, dependency chain]
```

---

## Spec Template — Deployment / Migration

```markdown
## What
[Service, version, or data being deployed/migrated]

## Deploy sequence
1. [Step 1]
2. [Step 2]
3. [Smoke test]

## Rollback trigger
[What condition triggers a rollback — error rate, latency, specific log pattern]

## Rollback steps
1. [Exact command or action]
2. [Verification step]

## Acceptance criteria
- [ ] [Health check URL returns 200]
- [ ] [Error rate < X% for Y minutes post-deploy]
- [ ] [No new ALARM state in CloudWatch/New Relic]
```

---

## Rules

- The spec is written **in the conversation**, not in a file
- Implementation starts only after spec is confirmed
- Acceptance criteria must be **testable** — "works correctly" is not a criterion
- Rollback plan must be **specific** — "revert the change" is not a plan
- Out-of-scope section prevents scope creep mid-implementation
