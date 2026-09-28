#!/usr/bin/env bash
# Stop hook: if the session edited files but never ran a command afterwards, send it back to verify.
# Rationale: "Run tests after every change" measured 4/6-6/6 across every config; prose alone
# does not hold it. Blocks at most once per session to avoid a loop.
input=$(cat)
tp=$(printf '%s' "$input" | /usr/bin/jq -r '.transcript_path // empty' 2>/dev/null)
sa=$(printf '%s' "$input" | /usr/bin/jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$sa" = "true" ] && exit 0            # already sent back once; do not loop
[ -z "$tp" ] || [ ! -f "$tp" ] && exit 0
# ordered tool-use names from the transcript
seq=$(/usr/bin/jq -r 'select(.message.content) | .message.content[]? | select(.type=="tool_use") | .name' "$tp" 2>/dev/null)
printf '%s' "$seq" | /usr/bin/grep -qE '^(Edit|Write|MultiEdit)$' || exit 0   # nothing was edited
last_edit=$(printf '%s\n' "$seq" | /usr/bin/grep -nE '^(Edit|Write|MultiEdit)$' | tail -1 | cut -d: -f1)
last_bash=$(printf '%s\n' "$seq" | /usr/bin/grep -nE '^Bash$' | tail -1 | cut -d: -f1)
[ -n "$last_bash" ] && [ "$last_bash" -gt "$last_edit" ] && exit 0            # verified after editing
/usr/bin/jq -n '{decision:"block", reason:"You changed files but ran no command afterwards. CLAUDE.md requires running tests after every change, and verification-before-completion requires evidence before asserting success. Run the relevant test or check now, then report its actual output."}'
