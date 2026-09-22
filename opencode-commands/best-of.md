---
description: >-
  Test-time scaling for hard problems: generate N independent candidate
  solutions in parallel, have the adversarial critic rank them, apply only the
  winner, then verify. Opt-in because it multiplies token/rate-limit cost —
  use for genuinely hard tasks, not routine edits. Usage: /best-of <task>
  (3 candidates) or /best-of N=2 <task>.
agent: sisyphus
---

Solve the following task with best-of-N test-time scaling:

$ARGUMENTS

(Default N=3. If the arguments start with "N=<number>", use that N — at these
rate limits N above 3 is rarely worth it.)

## Why this exists

Inference-time compute measurably improves hard-task success for open models
(best-of-N with a verifier). It is expensive — N full attempts plus review —
so it is opt-in. Do not use this flow for tasks a single attempt handles.

## Procedure

1. **Do not solve the task yourself first.** Spawn N independent subagent
   attempts in parallel with the task tool. Each gets the same task plus a
   distinct angle to reduce correlated failures — e.g. (1) simplest correct
   solution, (2) edge-case-first, (3) performance/robustness-first. Each
   attempt must return: its approach in two sentences, the COMPLETE proposed
   change as a unified diff (or full file contents for new files), and its own
   test plan. Attempts must NOT modify the working tree — output only.
2. **Rank adversarially.** Pass all candidates to the @critic subagent in one
   review (`run_in_background: false`; a background seat is abandoned when your
   turn ends): which is correct, simplest, and safest? The critic must pick a
   winner and say why the others lost, and must add a `winner` field to its
   JSON block naming exactly one supplied candidate id. A reply whose `winner`
   is missing, names no candidate, or names more than one is FAILED (see the
   guard below); never guess the winner yourself.

**Failed-review guard.** A reviewer reply counts as FAILED, never as "no objections", if ANY of these holds: it is empty; its finish reason is `length` (when you can see it); it does not END with the reviewer's required closing block (@critic: the JSON verdict block, which must parse and contain `verdict`, `top_fix` and `issues`; @plan-critic: the line `Review complete.`; @thermo-nuclear-review: a final line that is exactly `SHIP`, `REVISE` or `BLOCK`); or that closing block is malformed; or the reply lacks the reviewer's required findings structure (a closing block alone, with no findings or lenses, is FAILED). A verdict appearing earlier in the text does not rescue a reply that fails these tests. Re-spawn that member once, sequentially, on the SAME full target (never reduce scope: a verdict on part of the target must not be applied to all of it) with an explicit instruction to cut verbosity — prose under 300 words, one short evidence line per issue, no duplicated issues — while keeping every issue that affects the verdict, so the closing block fits; if it fails again apply NOTHING: report the candidates, say the critic seat was unavailable, and stop. Never fill the gap with your own review. (Model fallbacks fire only on HTTP errors, never on bad content.)
3. **Apply the winner only.** Implement the winning candidate on the working
   tree exactly as proposed (adjust only for mechanical conflicts).
4. **Verify.** Run the project's real tests/lint/build on the applied change
   (the /verify pipeline). If verification fails, report honestly — do not
   silently fall back to another candidate; say which candidate won, what
   failed, and recommend the next step.
5. **Report.** One short section per candidate (approach + why it won/lost),
   the critic's verdict, and the verification results.
