---
description: >-
  Harness self-test. Stage 1 statically validates harness invariants
  (NaN-only, AGENTS.md parity, denylist, Engram); Stage 2 confirms liveness on
  a NaN model; Stage 3 scans the recent log for errors. Run after any config or
  plugin change.
---

Run a harness smoke test and report the result concisely.

1. **Static invariants (offline, no model call).** Run the harness checker and
   capture its JSON result:

   ```bash
   node ~/.config/opencode/scripts/check-harness.mjs --json 2>&1
   ```

   `ok:true` means all config invariants hold. If `ok:false`, list each entry
   in `errors` — these are config regressions (non-NaN model, AGENTS.md drift,
   missing denylist guard, broken JSON, Engram unwired) and mean Stage-1 FAIL
   regardless of liveness.
2. State the model and agent you are currently running as. Confirm the provider
   is `nan` (the only allowed provider). If it is not `nan/*`, flag it loudly.
3. Run this shell command to scan the most recent log for real errors and
   fallbacks (benign INFO lines containing "undefined" do not count):

   ```bash
   grep -iE "level=(ERROR|WARN)|prefill|cannot find module|Missing Authentication|fallback" \
     ~/.local/share/opencode/log/opencode.log 2>/dev/null | tail -15 || echo "no log/no matches"
   ```

4. Report:
   - **Invariants (Stage 1)**: `ok:true`, or the list of failing checks.
   - **Liveness**: responding yes/no, on which `nan/*` model.
   - **Log**: count of genuine ERROR-level lines and any prefill/auth/fallback
     hits. The recurring `WARN duplicate skill name webapp-testing` is benign:
     `~/.agents/skills/webapp-testing/SKILL.md` is a symlink to the
     `~/.claude/skills` copy, so both discovery paths resolve to identical
     content — note it but do not count it as a failure.
   - **DCP**: confirm no `prefill`/"not supported for this model" hits. The
     bundled omo DCP appends rather than injecting a second system message, so
     it is safe on the NaN openai-compatible provider; any prefill hit is a
     regression to flag.
   - **Verdict**: PASS (invariants ok, responding on NaN, no real errors) or
     FAIL (name the stage: Stage 1 = config invariant, Stage 2 = liveness,
     Stage 3 = log error — so the failure kind is unambiguous).

Keep the whole report under 10 lines.
