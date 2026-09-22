---
description: >-
  Verify the current change before claiming it is done. Determines and runs the
  project's real test, lint, and build/type-check commands, then routes the diff
  and results through the adversarial critic for a binding SHIP/REVISE/BLOCK
  verdict. Use before committing or claiming a fix works.
---

Verify the current working change. Do not trust your own confidence — rest the
verdict on what the checks actually output.

Target (optional): $ARGUMENTS
(If empty, verify the current uncommitted working-tree change.)

## Steps

1. **Find the change.** Show the working-tree diff (`git diff` / `git diff
   --staged`). If there is nothing to verify, say so and stop.
2. **Determine the real commands** from the project itself — package.json
   scripts, Makefile, go.mod, pyproject.toml/tox, etc. Do not assume; read the
   config. State which commands you will run.
3. **Run them and capture real output**, in this order, continuing past
   failures so you see all results:
   - tests
   - lint
   - build / type-check
   Quote the actual pass/fail counts and any error lines. Never paraphrase a
   result you did not run.
4. **Adversarial review.** Spawn `@critic` on the diff plus the check output
   with `run_in_background: false` (never background: an unfinished turn ends the
   session and abandons the seat).
   Wait for its structured verdict. Give reviewers the diff and check output
   only — never your reasoning or justification for the change.
   **High-risk changes** (prod infra, auth, data migrations): also spawn
   `@thermo-nuclear-review` on the same diff — paste the full diff text and the
   check output into its prompt (it has no bash) — in parallel and
   independently; neither reviewer sees the other's output. BLOCK if either
   blocks.

**Failed-review guard.** A reviewer reply counts as FAILED, never as "no objections", if ANY of these holds: it is empty; its finish reason is `length` (when you can see it); it does not END with the reviewer's required closing block (@critic: the JSON verdict block, which must parse and contain `verdict`, `top_fix` and `issues`; @plan-critic: the line `Review complete.`; @thermo-nuclear-review: a final line that is exactly `SHIP`, `REVISE` or `BLOCK`); or that closing block is malformed; or the reply lacks the reviewer's required findings structure (a closing block alone, with no findings or lenses, is FAILED). A verdict appearing earlier in the text does not rescue a reply that fails these tests. Re-spawn that member once, sequentially, on the SAME full target (never reduce scope: a verdict on part of the target must not be applied to all of it) with an explicit instruction to cut verbosity — prose under 300 words, one short evidence line per issue, no duplicated issues — while keeping every issue that affects the verdict, so the closing block fits; if it fails again the Overall result is **INCONCLUSIVE** (never SHIP): report that reviewer seat as unavailable and stop. Never fill the gap with your own review. (Model fallbacks fire only on HTTP errors, never on bad content.)
5. **Report** concisely:
   - Each check: command run and PASS/FAIL with evidence.
   - Critic verdict: SHIP / REVISE / BLOCK and its top fix.
   - **Overall: BLOCK if any check failed or any reviewer returned BLOCK;
     REVISE if any reviewer returned REVISE; INCONCLUSIVE if any spawned
     reviewer seat failed twice; SHIP only when every check passed and every
     spawned reviewer returned SHIP.**

A change is done only when every check passes and every spawned reviewer returned SHIP.
Report failures honestly.
