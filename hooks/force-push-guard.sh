#!/usr/bin/env bash
# PreToolUse(Bash): deny git push --force / -f unless --force-with-lease is present.
input=$(cat)
cmd=$(printf '%s' "$input" | /usr/bin/jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | /usr/bin/grep -qE '(^|[^[:alnum:]_.-])git([^[:alnum:]_.-]|$)' || exit 0
printf '%s' "$cmd" | /usr/bin/grep -qE '(^|[^[:alnum:]_.-])push([^[:alnum:]_.-]|$)' || exit 0
printf '%s' "$cmd" | /usr/bin/grep -qE '(--force-with-lease)' && exit 0
printf '%s' "$cmd" | /usr/bin/grep -qE '(--force\b|[[:space:]]-[a-zA-Z]*f[a-zA-Z]*\b)' || exit 0
/usr/bin/jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "git push --force without --force-with-lease is denied. Use --force-with-lease."
  }}'
