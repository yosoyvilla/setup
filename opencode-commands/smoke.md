---
description: >-
  Harness self-test. Confirms the agent is responding on a NaN model and scans
  the recent opencode log for errors. Run after any config or plugin change.
---

Run a harness smoke test and report the result concisely.

1. State the model and agent you are currently running as. Confirm the provider
   is `nan` (the only allowed provider). If it is not `nan/*`, flag it loudly.
2. Run this shell command to scan the most recent log for real errors and
   fallbacks (benign INFO lines containing "undefined" do not count):

   ```bash
   grep -iE "level=(ERROR|WARN)|prefill|cannot find module|Missing Authentication|fallback" \
     ~/.local/share/opencode/log/opencode.log 2>/dev/null | tail -15 || echo "no log/no matches"
   ```

3. Report:
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
   - **Verdict**: PASS (responding on NaN, no real errors) or FAIL (with the
     specific reason).

Keep the whole report under 10 lines.
