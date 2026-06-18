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
4. **Adversarial review.** Spawn `@critic` on the diff plus the check output.
   Wait for its structured verdict.
5. **Report** concisely:
   - Each check: command run and PASS/FAIL with evidence.
   - Critic verdict: SHIP / REVISE / BLOCK and its top fix.
   - **Overall: BLOCK if any check failed or the critic returned BLOCK;
     REVISE if the critic returned REVISE; otherwise SHIP.**

A change is done only when every check passes and the critic does not BLOCK.
Report failures honestly.
