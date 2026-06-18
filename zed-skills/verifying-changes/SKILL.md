---
name: verifying-changes
description: >-
  Use when about to claim a code change works, is fixed, or is complete, before
  committing, or before opening a PR. Runs the evidence-ranked verification
  pipeline so an open model cannot mark unproven work as done. Triggers on
  phrases like "done", "fixed", "this works", "ready to commit", or finishing a
  feature or bugfix.
---

# Verifying changes

Open models are overconfident and have flat confidence calibration, so "I'm
confident this works" is not evidence. Verification must rest on external
signals — tests, types, the registry, the docs — never on the model's feeling.
This skill is the gate between "I wrote code" and "the change is done."

## The pipeline (cheap first, escalate only as needed)

Run these in order. Stop early only when an upstream step gives a hard failure
that must be fixed first.

1. **Plan check.** Restate what the change is supposed to do and the observable
   signal that proves it. If there is no observable signal, you are not ready to
   verify — define one.
2. **Ground the facts.** Any library/API/config claim the change relies on must
   be confirmed against official docs (context7, then web), not memory. Cite
   `file:line` or a doc URL. See `validating-packages` before adding any
   dependency.
3. **Run the real checks.** Determine and run the project's actual test, lint,
   and build/type-check commands (from its config — package.json scripts,
   Makefile, go.mod, pyproject, etc.). Capture the real output. Do not
   paraphrase or assume.
4. **Adversarial review.** Pass the diff plus the check output to an adversarial
   critic (opencode: `@critic`; Zed: the critic skill). Treat its BLOCK/REVISE
   verdict as binding until addressed.
5. **Decide on evidence.** Proceed only if tests/build/lint pass and the critic
   does not BLOCK. If any check fails, the change is not done — fix and re-run.

## Hard rules

- Never report success on a step you did not actually run. If you could not run
  it, say so explicitly and mark the change unverified.
- "Tests pass" is the terminal proof. Green is the only "done."
- For anything with a real runtime surface (HTTP endpoint, CLI, UI), prefer one
  concrete real-surface check (curl/run/screenshot) over trusting unit tests
  alone.
- Report failures verbatim. Honest "3 tests failing" beats a false "done."

## When NOT to use

Single-line typo fixes, comment/doc edits, or pure renames with no behavior
change — state that verification was skipped and why.
