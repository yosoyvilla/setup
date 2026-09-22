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

**Synchronous spawns only.** Spawn every review seat with `run_in_background: false` and wait for the tool result inside the same turn. Background spawns are forbidden for review seats: when your turn ends before they report, the session ends and the seats are abandoned mid-review (observed 2026-09-21: three seats spawned in background, zero findings returned, one wasted Claude call).

1. Spawn the **@critic** subagent ONCE, giving it the full target and ALL the
   lenses below in one prompt (ask for findings grouped per lens). The critic
   runs on Claude Sonnet 5: each spawn is a separate pay-as-you-go call carrying
   ~90k system tokens, and native task spawns are NOT serialized by
   oh-my-openagent's providerConcurrency, so never spawn more than one Anthropic
   subagent at a time, and never spawn a second @critic for a second opinion
   (the single retry required by the failed-review guard is the only permitted
   second @critic spawn). For
   production, auth, data or multi-account targets add an independent second
   seat on NaN instead: spawn **@thermo-nuclear-review** on the same target
   with the same lenses, pasting the full target text into its prompt (it has
   no bash; different model family, no Claude cost). Lenses:
   - **correctness** — logic, edge cases, does it actually work
   - **security** — auth, secrets, data exposure, injection, blast radius
   - **simplicity** — is there a simpler design; what can be removed
   - **operability** — failure modes, rollback, observability, irreversibility
   - **cost** — token/compute/infra cost, cheaper paths
2. If the target contains factual or technical claims (library behavior, version
   numbers, API/config details), also spawn the **@fact-checker** subagent on
   it.
3. Collect every subagent's findings.

**Failed-review guard.** A reviewer reply counts as FAILED, never as "no objections", if ANY of these holds: it is empty; its finish reason is `length` (when you can see it); it does not END with the reviewer's required closing block (@critic: the JSON verdict block, which must parse and contain `verdict`, `top_fix` and `issues`; @plan-critic: the line `Review complete.`; @thermo-nuclear-review: a final line that is exactly `SHIP`, `REVISE` or `BLOCK`); or that closing block is malformed; or the reply lacks the reviewer's required findings structure (a closing block alone, with no findings or lenses, is FAILED). A verdict appearing earlier in the text does not rescue a reply that fails these tests. Re-spawn that member once, sequentially, on the SAME full target (never reduce scope: a verdict on part of the target must not be applied to all of it) with an explicit instruction to cut verbosity — prose under 300 words, one short evidence line per issue, no duplicated issues — while keeping every issue that affects the verdict, so the closing block fits; if it fails again the council verdict is **INCONCLUSIVE**: report the seat as unavailable and synthesize only the members that completed. The @fact-checker is not a review seat, but its reply must END with its JSON block (parsing, with `overall_confidence` and a `claims` array); a reply without it is FAILED. Retry once; if it fails twice, mark its claims UNVERIFIED in the synthesis and continue. Never fill the gap with your own review. (Model fallbacks fire only on HTTP errors, never on bad content.)

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
