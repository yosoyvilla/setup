#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit): refuse emoji in documentation files.
# "No emojis in documentation" measured 3/6 as prose and 5/6 with a curated prompt; every
# hook-backed rule in the same suite scored 6/6. This closes it deterministically.
input=$(cat)
path=$(printf '%s' "$input" | /usr/bin/jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$path" ] && exit 0
case "$path" in
  *.md|*.markdown|*.mdx|*.rst|*.txt|*.adoc) ;;
  *) exit 0 ;;
esac
# Inspect whatever text this call would write.
payload=$(printf '%s' "$input" | /usr/bin/jq -r '
  [ .tool_input.content?,
    .tool_input.new_string?,
    ( .tool_input.edits? // [] | .[]? | .new_string? )
  ] | map(select(. != null)) | join("\n")' 2>/dev/null)
[ -z "$payload" ] && exit 0
found=$(printf '%s' "$payload" | /usr/bin/python3 -c '
import re,sys
# Pictographs, emoticons, transport, symbols, dingbats, flags, and VS16 - deliberately NOT
# matching arrows/box-drawing/typographic marks, which are legitimate in technical docs.
rx = re.compile("[\U0001F000-\U0001FAFF\U0001F1E6-\U0001F1FF☀-⛿✀-➿️⬀-⯿]")
# Typographic marks this codebase uses deliberately are not emoji: the star that opens an
# Insight block, and the box-drawing rules that close it.
ALLOWED = set("★☆─━│┃═║")
hits = [h for h in rx.findall(sys.stdin.read()) if h not in ALLOWED]
print("".join(dict.fromkeys(hits))[:20])
' 2>/dev/null)
[ -z "$found" ] && exit 0
/usr/bin/jq -n --arg f "$found" --arg p "$path" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Emoji found in documentation (\($p)): \($f). CLAUDE.md states: No emojis in documentation. Rewrite without them.")
  }}'
