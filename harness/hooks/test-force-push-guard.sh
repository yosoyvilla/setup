#!/usr/bin/env bash
# Offline cases for force-push-guard.sh. Cases live in this file so testing them never
# puts the dangerous literal onto a Bash command line (which the guard itself would block).
H="$(cd "$(dirname "$0")" && pwd)/force-push-guard.sh"
pass=0; fail=0
chk() { # chk <expected: deny|allow> <command>
  want="$1"; shift
  got=$(printf '%s' "$1" | /usr/bin/python3 -c '
import json,sys
print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' | "$H" \
    | /usr/bin/python3 -c '
import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])
except Exception: print("allow")' 2>/dev/null)
  got=${got:-allow}
  if [ "$got" = "$want" ]; then pass=$((pass+1)); mark="ok  "; else fail=$((fail+1)); mark="FAIL"; fi
  printf "  %s want=%-5s got=%-5s  %s\n" "$mark" "$want" "$got" "$1"
}

F='--fo''rce'          # split so this file's own text cannot trip a text matcher
L='--fo''rce-with-lease'

chk deny  "git push $F origin main"
chk deny  "git push -f origin main"
chk deny  "git -C /repo push $F"
chk deny  "git --git-dir=/a/.git push -f"
chk allow "git push $L origin main"
chk allow "git push origin main"
chk allow "git push -q"
chk allow "git push -q 2>&1 | tail -2"
chk allow "git status"
chk allow "git ls-files | wc -l"
chk allow "git add -A && git commit -qm msg && git push -q"
chk allow "grep -f patterns.txt file"
chk allow "npm run push-force"
chk allow "git log --oneline -1"
chk deny  "git push origin main $F"

printf "\n  %d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
