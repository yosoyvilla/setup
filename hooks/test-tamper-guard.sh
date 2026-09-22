#!/bin/bash
# Detect the highest-frequency agentic failure in the literature: making a test pass
# by editing the test instead of the code.
#
# EVIDENCE: a 10-line conftest.py defeats all of SWE-bench Verified. GPT-5 exploits
# tests 54-76% of the time when they conflict with the spec. METR measured 30%+
# reward-hacking rates. ImpossibleBench showed a PROMPT fix only moved 66% -> 54% at
# repo scale — which is exactly why this is a hook and not a line in CLAUDE.md, per
# the user's own feedback-hard-rules-need-hooks directive.
#
# TRIGGER: editing a test/CI file *after* having edited source in the same session.
# Editing tests alone is normal work (TDD writes the test first) and stays silent.
# Only the source-then-test sequence is the tampering signature.
#
# PreToolUse/Edit|Write. Emits `ask` — a human decides. Note: a session running in
# auto mode auto-approves `ask`, so this gate only truly bites in a normal session.

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
[ -z "$FILE" ] && exit 0

STATE_DIR="$HOME/.claude/.test-tamper-state"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE="$STATE_DIR/$SID"

is_test_or_ci() {
  case "$1" in
    */conftest.py|conftest.py) return 0 ;;
    */pytest.ini|*/tox.ini|*/setup.cfg|*/pyproject.toml) return 0 ;;
    # NOTE: a `case` glob must match the WHOLE path, so bare `test_*.py` never fires
    # on `/repo/tests/test_thing.py`. Every basename pattern needs a `*/` prefix.
    *_test.go|*_test.py|*/test_*.py|test_*.py) return 0 ;;
    */tests/*|*/test/*|*/spec/*|*/__tests__/*) return 0 ;;
    *.spec.ts|*.spec.tsx|*.spec.js|*.test.ts|*.test.tsx|*.test.js) return 0 ;;
    */spec_helper.rb|*/rails_helper.rb|*_spec.rb|*/Rakefile) return 0 ;;
    */.github/workflows/*|*/bitbucket-pipelines.yml|*/.gitlab-ci.yml) return 0 ;;
    */jest.config.*|*/vitest.config.*|*/playwright.config.*) return 0 ;;
    *) return 1 ;;
  esac
}

is_source() {
  # Source code, explicitly excluding the test/CI shapes above.
  case "$1" in
    *.py|*.go|*.ts|*.tsx|*.js|*.jsx|*.rb|*.php|*.java|*.rs|*.tf) return 0 ;;
    *) return 1 ;;
  esac
}

if is_test_or_ci "$FILE"; then
  if [ -s "$STATE" ]; then
    RECENT=$(tail -5 "$STATE" | sed 's|^|      |')
    jq -n --arg f "$FILE" --arg r "$RECENT" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",
        permissionDecisionReason:("TEST-TAMPER CHECK: about to edit the test/CI file \($f) after already editing source in this session:\n\($r)\n\nMaking a failing test pass by changing the test is the most common agentic failure mode in the literature (GPT-5 does it 54-76% of the time when test and spec conflict). Approve only if this test edit is genuinely warranted — the spec changed, the test was wrong, or you are adding coverage. If the goal is to make a red test green, fix the source instead.")}}'
    exit 0
  fi
elif is_source "$FILE"; then
  # Record source edits so a later test edit can be recognised as the second half
  # of the pattern. Bounded so the file cannot grow without limit.
  echo "$FILE" >> "$STATE" 2>/dev/null
  if [ "$(wc -l < "$STATE" 2>/dev/null || echo 0)" -gt 200 ]; then
    tail -50 "$STATE" > "$STATE.tmp" 2>/dev/null && mv "$STATE.tmp" "$STATE" 2>/dev/null
  fi
fi
exit 0
