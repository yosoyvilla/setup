#!/usr/bin/env bash
#
# install-claude.sh — set up Claude Code ONLY, on a fresh machine.
#
# Installs the Claude Code CLI and places every vendored Claude asset:
# CLAUDE.md, settings.json + settings.local.json, agents, skills (folders with
# support scripts), rules, and the auto-sync hook. Nothing else: this script
# never touches ~/.config/opencode, ~/.opencode, ~/.config/zed, ~/.agents or
# ~/.engram, and installs no other tooling. Teammates who use Claude Code
# without the rest of the stack run THIS script instead of install.sh
# (install.sh delegates its Claude section here, so the logic lives once).
#
# Supports: macOS and Debian/Ubuntu. Idempotent: safe to re-run (existing
# settings files are backed up once per change). Unattended: never prompts.
# Exits non-zero if any hard step failed.
#
# Usage:  cd <this repo>  &&  ./install-claude.sh
#
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODO=()
FAILED=()

# ── output helpers (kept in sync with install.sh) ─────────────────
c_blue='\033[0;34m'; c_green='\033[0;32m'; c_yellow='\033[0;33m'; c_red='\033[0;31m'; c_off='\033[0m'
section(){ printf "\n${c_blue}==> %s${c_off}\n" "$1"; }
ok(){ printf "  ${c_green}✓${c_off} %s\n" "$1"; }
warn(){ printf "  ${c_yellow}!${c_off} %s\n" "$1"; }
err(){ printf "  ${c_red}✗${c_off} %s\n" "$1"; FAILED+=("$1"); }
have(){ command -v "$1" >/dev/null 2>&1; }
todo(){ TODO+=("$1"); }
as_root(){ if [ "$(id -u)" -eq 0 ]; then "$@"; elif command -v sudo >/dev/null 2>&1; then sudo "$@"; else warn "root needed for: $*"; return 1; fi; }
backup(){
  local f="$1"
  if [ -f "$f" ] && ! cmp -s "$f" "$2" 2>/dev/null; then
    cp "$f" "$f.bak-$(date +%Y%m%dT%H%M%S)" 2>/dev/null && warn "backed up existing $(basename "$f")"
  fi
}

# ── OS detection ──────────────────────────────────────────────────
OS=""
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)
    if have apt-get; then OS="debian"; else
      printf '%b\n' "${c_red}Unsupported Linux (no apt). This script supports macOS and Debian/Ubuntu.${c_off}"; exit 1
    fi ;;
  *) printf '%b\n' "${c_red}Unsupported OS: $(uname -s)${c_off}"; exit 1 ;;
esac
section "Claude Code setup  |  OS: $OS  |  repo: $REPO_DIR"

# ── minimal bootstrap: curl only (macOS ships it; bare Debian may not) ──
if ! have curl && [ "$OS" = "debian" ]; then
  as_root apt-get update -y >/dev/null 2>&1
  as_root apt-get install -y curl ca-certificates >/dev/null 2>&1 && ok "curl (bootstrap)" || err "curl bootstrap"
fi

# ── Claude Code CLI — native installer, npm fallback ──────────────
section "Claude Code CLI"
export PATH="$HOME/.local/bin:$PATH"
if ! have claude; then
  if curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1; then
    ok "Claude Code (native installer)"
  elif have npm && npm install -g @anthropic-ai/claude-code >/dev/null 2>&1; then
    ok "Claude Code (npm)"
  else
    err "Claude Code install"
    todo "Install Claude Code manually: curl -fsSL https://claude.ai/install.sh | bash  (or: npm install -g @anthropic-ai/claude-code)"
  fi
fi
have claude && ok "claude $(claude --version 2>/dev/null | head -1)" || warn "claude not on PATH yet (ensure ~/.local/bin in PATH)"
# persist PATH for future shells (native installer target)
grep -q 'HOME/.local/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# ── place vendored Claude assets ──────────────────────────────────
section "Placing Claude Code configs and assets"
mkdir -p "$HOME/.claude/agents" "$HOME/.claude/skills" "$HOME/.claude/rules" "$HOME/.claude/hooks"

backup "$HOME/.claude/CLAUDE.md" "$REPO_DIR/config/CLAUDE.md"
cp "$REPO_DIR/config/CLAUDE.md" "$HOME/.claude/CLAUDE.md" && ok "CLAUDE.md" || err "CLAUDE.md"

backup "$HOME/.claude/settings.json" "$REPO_DIR/config/claude-settings.json"
sed "s#__HOME__#$HOME#g" "$REPO_DIR/config/claude-settings.json" > "$HOME/.claude/settings.json" \
  && ok "settings.json (paths templatized)" || err "settings.json"

if [ -f "$REPO_DIR/config/claude-settings.local.json" ]; then
  backup "$HOME/.claude/settings.local.json" "$REPO_DIR/config/claude-settings.local.json"
  sed "s#__HOME__#$HOME#g" "$REPO_DIR/config/claude-settings.local.json" > "$HOME/.claude/settings.local.json" \
    && ok "settings.local.json (permission allowlist)" || err "settings.local.json"
fi

cp "$REPO_DIR"/agents/*.md "$HOME/.claude/agents/" \
  && ok "$(ls "$REPO_DIR"/agents/*.md | wc -l | tr -d ' ') agents" || err "agents"
cp -R "$REPO_DIR"/skills/* "$HOME/.claude/skills/" \
  && ok "skills (folders incl. support scripts)" || err "skills"
cp "$REPO_DIR"/rules/*.md "$HOME/.claude/rules/" && ok "rules" || err "rules"
cp "$REPO_DIR"/hooks/*.sh "$HOME/.claude/hooks/" && chmod +x "$HOME/.claude/hooks/"*.sh \
  && ok "hooks (chmod +x)" || err "hooks"

# ── manual TODO ───────────────────────────────────────────────────
todo "Log in on first launch: run 'claude' and authenticate"
todo "Claude Code plugins: enabledPlugins is preconfigured in settings.json; first 'claude' launch prompts once per plugin to trust/install"
todo "Optional (personal machines): clone the Obsidian vault so the auto-sync hook backs up memory — without it the hook is a safe no-op"

section "Done"
if [ ${#FAILED[@]} -eq 0 ]; then
  ok "Claude Code setup completed with no hard failures"
else
  printf '%b\n' "${c_red}Failures:${c_off}"
  for x in "${FAILED[@]}"; do echo "  - $x"; done
fi
printf '\n%b\n' "${c_yellow}Manual steps remaining:${c_off}"
for x in "${TODO[@]}"; do echo "  • $x"; done
printf '\nReopen your shell (or source ~/.zshrc) to pick up PATH changes.\n'
[ ${#FAILED[@]} -eq 0 ]
