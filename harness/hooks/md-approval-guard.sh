#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit): creating a NEW markdown file requires explicit user approval.
# Rationale: CLAUDE.md states "Never create markdown files without explicit user approval" and
# the prose rule measured 0/6 compliance. Enforcement must be a hook, not a sentence.
input=$(cat)
path=$(printf '%s' "$input" | /usr/bin/jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$path" ] && exit 0
case "$path" in
  *.md|*.markdown) ;;
  *) exit 0 ;;
esac
# Editing an EXISTING markdown file is fine; only creation needs approval.
[ -e "$path" ] && exit 0
/usr/bin/jq -n --arg p "$path" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("Creating a new markdown file (\($p)). CLAUDE.md requires explicit user approval before creating markdown files.")
  }}'
