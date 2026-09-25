#!/bin/bash
# Terraform verifier chain. PostToolUse/Edit|Write hook on *.tf files.
#
# WHY THIS EXISTS — the evidence, not a hunch:
#   IaC is the measured weak spot for LLMs. GPT-4 scored 19.36% pass@1 on IaC-Eval
#   while scoring 86.6% on EvalPlus (arXiv, IaC-Eval). The verifier-first papers
#   (arXiv:2607.20478, arXiv:2608.02672) found the agent's ceiling is set by the
#   verifiers wired into its loop, not by its reasoning, and state plainly that
#   "automated multi-tool static analysis is not an optional complement to
#   LLM-assisted IaC generation, it is a prerequisite."
#
# DESIGN DECISIONS, each traceable to that evidence:
#   * validate -> tflint -> checkov -> trivy. The validate->plan->policy chain took
#     GPT-4o from 70.4% to 84.4%.
#   * Checkov AND Trivy both. They measure different things; no model passed Checkov
#     without passing Trivy, and Claude Opus 4 scored 23.1% Checkov vs 92.5% Trivy.
#     Running only one hides the gap.
#   * RAW output is fed back, never a summary. GPT-5.4 gained +43.7pp on Trivy from
#     raw output. Summarising is the mistake.
#   * Advisory only: emits additionalContext, never blocks. A formatter/linter that
#     blocks turns every edit into a fight; the model needs the findings, not a wall.
#   * `terraform plan` is deliberately NOT run: it needs credentials and network, can
#     mutate state locks, and would fire on every keystroke-level edit.
#
# Output is capped so a noisy scanner cannot flood the context window.

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in *.tf|*.tfvars.json) ;; *) exit 0 ;; esac
[ -f "$FILE" ] || exit 0

DIR=$(dirname "$FILE")
MAXLINES=40
OUT=""
add() { OUT="${OUT}
=== $1 ===
$2"; }

# 1. syntax/type correctness — cheap, no network, no state
if command -v terraform >/dev/null 2>&1; then
  v=$(cd "$DIR" && terraform validate -no-color 2>&1 | head -$MAXLINES)
  case "$v" in
    *"Success"*) : ;;
    *"No configuration files"*) : ;;
    *"Missing required provider"*|*"not been initialized"*|*"Module not installed"*) : ;;  # needs init; not a code defect
    "") : ;;
    *) add "terraform validate" "$v" ;;
  esac
fi

# 2. lint — provider-aware misconfigurations validate does not catch
if command -v tflint >/dev/null 2>&1; then
  t=$(cd "$DIR" && tflint --no-color --force 2>&1 | head -$MAXLINES)
  [ -n "$t" ] && add "tflint" "$t"
fi

# 3+4. BOTH scanners — they disagree, and that disagreement is the signal
if command -v checkov >/dev/null 2>&1; then
  c=$(checkov -f "$FILE" --compact --quiet --output cli 2>/dev/null | head -$MAXLINES)
  [ -n "$c" ] && add "checkov (raw)" "$c"
fi
if command -v trivy >/dev/null 2>&1; then
  # --no-progress is NOT a valid `trivy config` flag (0.74.0 prints usage and exits 0),
  # and a FILE target yields an empty report -- trivy config takes a DIR. Both verified.
  r=$(trivy config --quiet --severity HIGH,CRITICAL "$DIR" 2>/dev/null | head -$MAXLINES)
  [ -n "$r" ] && add "trivy config (raw)" "$r"
fi

[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && exit 0

jq -n --arg ctx "Terraform verifier chain on $FILE — RAW tool output, unsummarised.
Budget 1-2 fix attempts then stop and report: the IaC literature finds binary
convergence (tasks resolve in 1-2 retries or exhaust the budget; further retries
are pure cost). Findings may be pre-existing or intentional — confirm before changing.
$OUT" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
