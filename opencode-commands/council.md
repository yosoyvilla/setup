---
description: >-
  Convene an adversarial council to review a decision, claim, plan, code, or
  answer. Fans out the critic across multiple lenses plus the fact-checker for
  factual claims, then synthesizes a verdict with recorded dissents.
agent: sisyphus
subtask: true
---

Convene a review council on the following target:

$ARGUMENTS

(If no target is given above, review the most recent substantive output in this
session.)

## How to run the council

Use the task tool to spawn independent subagents in parallel. Do not review the
material yourself first — let the council members reach their own conclusions.

**Critical:** Do not stop to announce that the council is running, that you are
"awaiting findings," or that you "will synthesize later." Spawn all members,
wait for every result, then produce the complete synthesis in the SAME final
response. The synthesis below is the only output the user should see.

1. Spawn the **@critic** subagent 3-5 times, each with a distinct lens. Pass the
   full target to each. Use whichever lenses fit the material:
   - **correctness** — logic, edge cases, does it actually work
   - **security** — auth, secrets, data exposure, injection, blast radius
   - **simplicity** — is there a simpler design; what can be removed
   - **operability** — failure modes, rollback, observability, irreversibility
   - **cost** — token/compute/infra cost, cheaper paths
2. If the target contains factual or technical claims (library behavior, version
   numbers, API/config details), also spawn the **@fact-checker** subagent on
   it.
3. Collect every subagent's findings.

## How to synthesize

Do not invent a numeric "vote." Read all findings and produce:

- **Consensus** — issues raised independently by two or more members (highest
  signal).
- **Per-lens summary** — the strongest point from each lens.
- **Dissents** — disagreements between members, stated explicitly, not papered
  over.
- **Fact-check results** — supported / refuted / unverifiable claims with
  citations, if the fact-checker ran.
- **Verdict** — SHIP / REVISE / BLOCK, with the top 1-3 things to fix first.

Note: for pre-execution critique of an oh-my-openagent *plan*, the built-in
`hyperplan` skill and Momus already cover that path. Use /council for ad-hoc
review of arbitrary content, or when you want doc-backed fact-checking folded
into the review.
