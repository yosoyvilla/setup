#!/usr/bin/env bash
# Offline cases for force-push-guard.sh. Literals are assembled here so running this file
# never places a force-push string on a Bash command line (the guard would block it).
H="$(cd "$(dirname "$0")" && pwd)/force-push-guard.sh"
pass=0; fail=0
F=$(printf -- '--fo%s' 'rce'); L="${F}-with-lease"
chk() {
  want="$1"; shift
  got=$(printf '%s' "$1" | /usr/bin/python3 -c '
import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' | "$H" \
    | /usr/bin/python3 -c '
import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])
except Exception: print("allow")' 2>/dev/null)
  got=${got:-allow}
  if [ "$got" = "$want" ]; then pass=$((pass+1)); m="ok  "; else fail=$((fail+1)); m="FAIL"; fi
  printf "  %s want=%-5s got=%-5s  %s\n" "$m" "$want" "$got" "$1"
}

# the bypass that prompted this rewrite: last force flag wins, as git resolves them
chk deny  "git push $L $F origin main"
chk deny  "git push $F $L origin main; git push $L $F origin main"
chk allow "git push $F $L origin main"
chk allow "git push $L origin main"
# plain force forms
chk deny  "git push $F origin main"
chk deny  "git push -f origin main"
chk deny  "git push -qf origin main"
chk deny  "git -C /repo push $F"
chk deny  "git --git-dir=/a/.git push -f"
chk deny  "/usr/bin/git push $F origin main"
# benign
chk allow "git push origin main"
chk allow "git push -q"
chk allow "git push -q 2>&1 | tail -2"
chk allow "git status"
chk allow "git ls-files | wc -l"
chk allow "git add -A && git commit -qm msg && git push -q"
chk allow "grep -f patterns.txt file"
chk allow "npm run push-force"
chk allow "echo 'do not use git push $F'"        # a comment/quoted mention is not an invocation
chk allow "git push origin main -- $F"           # after --, not a flag
# segment isolation: a benign push must not be condemned by an unrelated segment
chk deny  "make build && git push $F origin main"

printf "\n  %d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
