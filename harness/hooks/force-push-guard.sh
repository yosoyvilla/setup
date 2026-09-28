#!/usr/bin/env bash
# PreToolUse(Bash): deny git push --force / -f unless --force-with-lease is present.
input=$(cat)
cmd=$(printf '%s' "$input" | /usr/bin/jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | /usr/bin/grep -qE '(^|[^[:alnum:]_.-])git([^[:alnum:]_.-]|$)' || exit 0
printf '%s' "$cmd" | /usr/bin/grep -qE '(^|[^[:alnum:]_.-])push([^[:alnum:]_.-]|$)' || exit 0
printf '%s' "$cmd" | /usr/bin/grep -qE 'force-with-lease' && exit 0
# The force flag must belong to the push itself: look only at the text AFTER `push`, and stop at a
# command separator. A loose match anywhere in a compound command produced false positives that
# blocked ordinary `git push -q`.
printf '%s' "$cmd" \
  | /usr/bin/sed -n 's/.*[^[:alnum:]_.-]push\([^;|&]*\).*/\1/p' \
  | /usr/bin/grep -qE '(^|[[:space:]])(--force([[:space:]]|=|$)|-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$))' || exit 0
/usr/bin/jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "git push --force without --force-with-lease is denied. Use --force-with-lease."
  }}'
