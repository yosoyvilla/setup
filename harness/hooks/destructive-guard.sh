#!/bin/bash
# Hard gate for destructive shell commands.
# PreToolUse/Bash hook: emits permissionDecision deny|ask, or stays silent to allow.
#
# deny = hard block, model cannot proceed.
# ask  = forces a human permission prompt; the model CANNOT self-approve.
#
# Rationale: prose rules in CLAUDE.md are advisory and were demonstrably ignored
# (2026-08-06: rsync --delete removed 334 vault files ~20 min after the rule was
# written). Enforcement has to live in the harness, not in the model's memory.

INPUT=$(cat)
CMD_RAW=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD_RAW" ] && exit 0

# Normalise shell quoting BEFORE any matching (added 2026-08-21 after a live bypass).
# The shell strips quotes, so `rm -"r" -"f" X`, `rm -"rf" X` and `rm -r"f" X` all execute
# as `rm -rf X` — but as TEXT none of them contain `-rf` or a bare `-r`/`-f` token, so
# every flag pattern here missed them and both tiers returned silent allow. Verified
# against the installed hook: 4 of 4 variants passed. This is not an exotic attack; flag
# characters get quoted routinely by templated commands and pasted snippets.
#
# Deleting quote and backslash characters collapses that entire evasion class in one
# place, instead of trying to enumerate quoting permutations in every regex below.
# Matching is done on CMD; CMD_RAW is kept only for the message shown to the human.
CMD=$(printf '%s' "$CMD_RAW" | tr -d "\"'\\\\")

emit() { # $1=decision $2=reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# ---------- TIER 1: DENY (never legitimate) ----------

# rsync --delete into config/memory/vault trees
if printf '%s' "$CMD" | grep -qE '\brsync\b' \
   && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])--(del|delete)([-=][a-z]+)?([[:space:]]|$)' \
   && printf '%s' "$CMD" | grep -qE '(\.claude|obsidian-vault|/memory|\.config)'; then
  emit deny "BLOCKED: rsync --delete targeting a config/memory/vault tree. The destination is a superset of the source, so --delete removes files the source never had. This exact command destroyed 334 vault files on 2026-08-06. Use cp of specific files, or rsync WITHOUT --delete."
fi

# rm -rf on home root, filesystem root, or a bare glob
if printf '%s' "$CMD" | grep -qE '\brm\b[^|;&]*(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR]|(-[rR]\b|--recursive\b)[^|;&]*(-f\b|--force\b)|(-f\b|--force\b)[^|;&]*(-[rR]\b|--recursive\b))'; then
  if printf '%s' "$CMD" | grep -qE '[[:space:]](/|~|\$HOME|/\*|~/\*|\$HOME/\*)([[:space:]]|$)'; then
    emit deny "BLOCKED: rm -rf targeting filesystem or home root."
  fi
fi

# History rewriting / force push to shared refs
if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+push\b[^|;&]*(--force([[:space:]]|$)|-f([[:space:]]|$))' \
   && ! printf '%s' "$CMD" | grep -q -- '--force-with-lease'; then
  emit deny "BLOCKED: git push --force. Use --force-with-lease, or push a new branch."
fi

# ---------- TIER 2: ASK (destructive, sometimes valid — human decides) ----------

REASON=""
if printf '%s' "$CMD" | grep -qE '\brm\b[^|;&]*(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR]|(-[rR]\b|--recursive\b)[^|;&]*(-f\b|--force\b)|(-f\b|--force\b)[^|;&]*(-[rR]\b|--recursive\b))'; then
  REASON="recursive force delete (rm -rf)"
elif printf '%s' "$CMD" | grep -qE '\brsync\b' \
     && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])--(del|delete)([-=][a-z]+)?([[:space:]]|$)'; then
  REASON="rsync --delete (removes files absent from source)"
elif printf '%s' "$CMD" | grep -qE '\bfind\b[^|;&]*-delete\b'; then
  REASON="find -delete"
elif printf '%s' "$CMD" | grep -qE '\bfind\b[^|;&]*-exec[[:space:]]+rm\b'; then
  REASON="find -exec rm"
elif printf '%s' "$CMD" | grep -qE '\|[[:space:]]*xargs[^|;&]*\brm\b'; then
  REASON="xargs rm"
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+clean\b[^|;&]*-[a-zA-Z]*f'; then
  REASON="git clean -f (deletes untracked files, unrecoverable)"
elif printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+(reset[[:space:]]+--hard|checkout[[:space:]]+--[[:space:]]*\.|restore[[:space:]]+\.)'; then
  REASON="discards uncommitted work"
elif printf '%s' "$CMD" | grep -qE '\b(terraform|tofu)[[:space:]]+(destroy|apply)\b'; then
  REASON="terraform state-changing operation"
elif printf '%s' "$CMD" | grep -qE '\bkubectl[[:space:]]+delete\b'; then
  REASON="kubectl delete"
elif printf '%s' "$CMD" | grep -qE '\bdrop[[:space:]]+(table|database|schema)\b'; then
  REASON="SQL DROP"
# Interpreters (added 2026-08-21). Every rule above keys off a COMMAND NAME, so an
# inline interpreter one-liner reached none of them. These two rules require an
# interpreter AND an actual deletion API / destructive shell-out, so read-only
# one-liners stay silent.
#
# SCOPE — INLINE ONLY. Read this before trusting it:
#   * Covers `-c` / `-e` one-liners and heredocs, because their code is present in the
#     command string this hook receives.
#   * Does NOT cover `python3 script.py`. The destructive code lives in a FILE the hook
#     never sees. That is an architectural limit of text-matching a command line, not a
#     missing regex — no pattern here can close it.
#   * Does NOT cover REPL shell-escapes (`psql -c '\! ...'`, `vim -c '!...'`, less's `!`),
#     `awk system()`, php, or lua.
#   * `osascript -e 'do shell script "rm -rf X"'` IS caught, but incidentally: the inner
#     text contains `rm -rf`, so the rm rule above fires. Not by an osascript rule.
# Treat this as narrowing one path, not as "interpreters: handled".
#
# Self-test caveat: a fixture that merely QUOTES a deletion API alongside an interpreter
# name is indistinguishable from the real thing to a text matcher, so this guard's own
# test suite trips its own ask tier. Run guard fixtures by piping JSON to the hook and
# reading permissionDecision (see scratchpad guardtest*.sh), not by executing them.
elif printf '%s' "$CMD" | grep -qE '\b(python3?|perl|ruby|node|deno|bun)\b' \
     && printf '%s' "$CMD" | grep -qE '(shutil\.rmtree|os\.remove|os\.unlink|os\.rmdir|\.unlink\(|fs\.rm[sS]ync|fs\.rmdir|fs\.unlink|rmdirSync|FileUtils\.rm_r|File\.delete|remove_tree|rimraf|os\.truncate|\.truncate\([[:space:]]*0[[:space:]]*\)|\.write_text\([[:space:]]*\)|shutil\.move\([^)]*/dev/null)'; then
  # Truncate/overwrite forms destroy content as irreversibly as unlink and were missed by
  # the original API list. Deliberately NOT matching bare `open(f,"w")` — writing a file
  # that way is ordinary work, and flagging it would fire on nearly every script.
  REASON="interpreter performing filesystem deletion (invisible to the command-name rules)"
elif printf '%s' "$CMD" | grep -qE '\b(python3?|perl|ruby|node|deno|bun)\b' \
     && printf '%s' "$CMD" | grep -qE '(subprocess|os\.system|popen|execSync|spawnSync|child_process|Kernel\.system)' \
     && printf '%s' "$CMD" | grep -qE '(rm[^a-zA-Z]{1,8}-[rRf]|\brsync\b|git[^a-zA-Z]{1,8}push|kubectl[^a-zA-Z]{1,8}delete|(terraform|tofu)[^a-zA-Z]{1,8}(destroy|apply))'; then
  # `rm` must carry a recursive/force flag to count. A bare \brm\b matched the "rm" in
  # subprocess.run(["docker","rm",...]) and (["git","rm",...]) — flagging container and
  # index removal that the plain-text `docker rm` / `git rm` forms are not flagged for,
  # an inconsistency that would interrupt routine cleanup for no safety gain.
  REASON="interpreter shelling out to a destructive command"
fi

if [ -n "$REASON" ]; then
  emit ask "CONFIRM: $REASON. Per CLAUDE.md, before an irreversible bulk deletion: list what will go, grep for inbound references to those paths, and state per-target whether it is recoverable (git-tracked? backed up? neither?). Approve only if that was done."
fi

exit 0
