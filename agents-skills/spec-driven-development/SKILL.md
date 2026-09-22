---
name: spec-driven-development
description: Use when about to implement any feature, fix, or infrastructure change — before writing code, creating a Terraform plan, or deploying to any environment. Write the spec first; implementation starts only after acceptance criteria are defined.
user-invocable: true
---

Write the spec before touching any code or infrastructure. Implementation starts only after the spec is agreed upon.

## When a Spec Is Required
- Any code change touching more than one file
- Any infrastructure change (Terraform, K8s manifests, Helm values, ArgoCD config)
- Any new deployment or service configuration
- Any bug fix where root cause analysis required investigation
- Any change to an API, CLI interface, or public contract

Not required for: single-line typo fixes, documentation edits, variable renaming with no behavior change.

---

## Templates

### Code / Feature Spec
```markdown
## Spec: <what we're building>

**Problem:** <what problem this solves — one sentence>
**Approach:** <chosen solution and why over the next-best alternative>

**Interface:**
- Input: <parameters, types, constraints>
- Output: <return value, events emitted, side effects>
- Error cases: <failure modes and how they surface>

**Acceptance Criteria:**
- [ ] <specific, testable assertion — not "works correctly">
- [ ] <specific, testable assertion>

**Non-goals:** <what this explicitly will NOT do — prevents scope creep>
```

### Infrastructure / Terraform Spec
```markdown
## Infra Spec: <what we're changing> [project: project-a|project-b|project-c|project-d]

**Current state:** <what exists today>
**Target state:** <expected state after apply>

**Resources:**
- Created: <list>
- Modified: <list — include which attributes change>
- Destroyed: <list — investigate if unintentional>

**Acceptance Criteria:**
- [ ] <verifiable CLI check, e.g. "aws eks describe-cluster returns ACTIVE">
- [ ] OPA policies pass / tflint clean

**Rollback plan:** <how to revert and estimated time>
```

### Deployment Spec
```markdown
## Deployment Spec: <service> → <version> [project: project-a|project-c|project-b]

**Change:** <what's different from the current running version>

**Acceptance Criteria:**
- [ ] All pods Running within 5 minutes of apply
- [ ] No error spike in logs / New Relic / Loki for 10 minutes post-deploy
- [ ] <service-specific check — endpoint, queue depth, health route>

**Rollback trigger:** <observable condition that means roll back immediately>
```

---

## Definition of Done for a Spec
A spec is complete when:
1. Acceptance criteria are **specific and verifiable** — someone else could run the check without asking you
2. Non-goals are stated
3. Interface is defined (for code) or resources listed (for infra)
4. Rollback plan exists for infra/deployment specs

---

## Workflow Position
```
brainstorming → spec (this skill) → writing-plans → plan-critic → TDD → implement → verification-before-completion
```
The spec feeds the plan. Tests prove the acceptance criteria. `verification-before-completion` checks the spec before claiming done.

---

## Common Mistakes
- **Untestable criteria**: "should work correctly" → invalid. "GET /health returns 200 within 500ms under normal load" → valid.
- **Spec written after code**: you're describing what you did, not what you meant to do — the entire point is lost.
- **No non-goals**: leads to scope creep during implementation ("while I'm in here…").
- **Missing rollback plan for infra**: you'll be improvising under pressure when something goes wrong.
- **Mixing projects in one spec**: each spec covers one project. project-a infra and project-c app changes get separate specs even if related.
