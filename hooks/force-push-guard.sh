#!/usr/bin/env bash
# PreToolUse(Bash): deny a git force-push unless the ONLY force flag in effect is --force-with-lease.
#
# Earlier versions exempted the whole command whenever --force-with-lease appeared anywhere, so
# `git push --force-with-lease --force` was allowed — git applies the LAST flag, making that an
# unconditional force push. Flags are now parsed in order and the last one wins, matching git.
input=$(cat)
cmd=$(printf '%s' "$input" | /usr/bin/jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

decision=$(printf '%s' "$cmd" | /usr/bin/python3 -c '
import re, shlex, sys

cmd = sys.stdin.read()
# Evaluate each shell segment separately so an unrelated command cannot mask or trigger a match.
segments = re.split(r"(?:\|\||&&|;|\||\n)", cmd)

def verdict(seg):
    try:
        toks = shlex.split(seg, comments=True)
    except ValueError:
        toks = seg.split()
    if not toks:
        return None
    # find a git invocation followed (anywhere after it) by the push subcommand
    names = [t.rsplit("/", 1)[-1] for t in toks]
    if "git" not in names:
        return None
    gi = names.index("git")
    rest = toks[gi + 1:]
    if "push" not in [r.rsplit("/", 1)[-1] for r in rest]:
        return None
    # last force-ish flag wins, exactly as git resolves them
    state = None
    for t in rest:
        if t == "--":
            break
        if t == "--force-with-lease" or t.startswith("--force-with-lease="):
            state = "lease"
        elif t == "--force" or t == "--force-if-includes":
            state = "force" if t == "--force" else state
        elif re.fullmatch(r"-[A-Za-z]+", t) and "f" in t[1:]:
            state = "force"
        elif t == "--no-force-with-lease":
            state = None
    return "deny" if state == "force" else None

print("deny" if any(verdict(s) == "deny" for s in segments) else "allow")
' 2>/dev/null)

[ "$decision" = "deny" ] || exit 0
/usr/bin/jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "This resolves to an unconditional git force-push (the last force flag wins). Use --force-with-lease alone, with no later --force/-f."
  }}'
