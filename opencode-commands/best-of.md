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
   review: which is correct, simplest, and safest? The critic must pick a
   winner and say why the others lost.
3. **Apply the winner only.** Implement the winning candidate on the working
   tree exactly as proposed (adjust only for mechanical conflicts).
4. **Verify.** Run the project's real tests/lint/build on the applied change
   (the /verify pipeline). If verification fails, report honestly — do not
   silently fall back to another candidate; say which candidate won, what
   failed, and recommend the next step.
5. **Report.** One short section per candidate (approach + why it won/lost),
   the critic's verdict, and the verification results.
