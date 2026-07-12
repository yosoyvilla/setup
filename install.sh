#!/usr/bin/env bash
#
# install.sh — reproduce this developer workstation on a fresh machine.
#
# Supports: macOS (Homebrew) and Debian/Ubuntu (apt).
# Idempotent: safe to re-run. Unattended: never prompts, never writes secrets.
# Installs the full stack (tools + Claude Code + opencode + Zed + Engram +
# Playwright) and places every vendored config/agent/skill/rule/hook.
# Manual steps it cannot automate (API keys, auths, GUI) are printed as a TODO
# list at the end.
#
# Usage:  cd <this repo>  &&  ./install.sh
#
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODO=()
FAILED=()

# ── output helpers ────────────────────────────────────────────────
c_blue='\033[0;34m'; c_green='\033[0;32m'; c_yellow='\033[0;33m'; c_red='\033[0;31m'; c_off='\033[0m'
section(){ printf "\n${c_blue}==> %s${c_off}\n" "$1"; }
ok(){ printf "  ${c_green}✓${c_off} %s\n" "$1"; }
warn(){ printf "  ${c_yellow}!${c_off} %s\n" "$1"; }
err(){ printf "  ${c_red}✗${c_off} %s\n" "$1"; FAILED+=("$1"); }
have(){ command -v "$1" >/dev/null 2>&1; }
todo(){ TODO+=("$1"); }
# Run a command with root privileges: direct if already root (e.g. containers),
# via sudo otherwise. Avoids requiring sudo when none is installed.
as_root(){ if [ "$(id -u)" -eq 0 ]; then "$@"; elif command -v sudo >/dev/null 2>&1; then sudo "$@"; else warn "root needed for: $*"; return 1; fi; }

# ── OS detection ──────────────────────────────────────────────────
OS=""
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)
    if have apt-get; then OS="debian"; else
      printf "${c_red}Unsupported Linux (no apt). This script supports macOS and Debian/Ubuntu.${c_off}\n"; exit 1
    fi ;;
  *) printf "${c_red}Unsupported OS: $(uname -s)${c_off}\n"; exit 1 ;;
esac
section "Detected OS: $OS  |  repo: $REPO_DIR"

# back up a file once before overwriting (timestamped, only if it differs)
backup(){
  local f="$1"
  if [ -f "$f" ] && ! cmp -s "$f" "$2" 2>/dev/null; then
    cp "$f" "$f.bak-$(date +%Y%m%dT%H%M%S)" 2>/dev/null && warn "backed up existing $(basename "$f")"
  fi
}

# ════════════════════════════════════════════════════════════════════
# 1. Package manager + core packages
# ════════════════════════════════════════════════════════════════════
section "Package manager and core packages"
if [ "$OS" = "macos" ]; then
  if ! have brew; then
    warn "Homebrew not found — installing"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null || err "Homebrew install failed"
    # add brew to PATH for the rest of this run (Apple Silicon default)
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  have brew && ok "Homebrew present"
  for pkg in gh ripgrep fzf terraform terraform-docs kubectl helm jq; do
    brew list "$pkg" >/dev/null 2>&1 && ok "$pkg" || { brew install "$pkg" >/dev/null 2>&1 && ok "installed $pkg" || warn "skip $pkg"; }
  done
else
  as_root apt-get update -y >/dev/null 2>&1 && ok "apt updated"
  as_root apt-get install -y curl wget git build-essential unzip ripgrep fzf jq zsh >/dev/null 2>&1 && ok "base packages" || err "apt base packages"
  # gh
  if ! have gh; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | as_root dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null 2>&1
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | as_root tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    as_root apt-get update -y >/dev/null 2>&1 && as_root apt-get install -y gh >/dev/null 2>&1 && ok "gh" || warn "gh install"
  else ok "gh"; fi
  # terraform
  if ! have terraform; then
    wget -qO- https://apt.releases.hashicorp.com/gpg | as_root gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
    CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $CODENAME main" | as_root tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    as_root apt-get update -y >/dev/null 2>&1 && as_root apt-get install -y terraform >/dev/null 2>&1 && ok "terraform" || warn "terraform install"
  else ok "terraform"; fi
fi

# ════════════════════════════════════════════════════════════════════
# 2. Node.js 20
# ════════════════════════════════════════════════════════════════════
section "Node.js 20"
if [ "$OS" = "macos" ]; then
  brew list node@20 >/dev/null 2>&1 || brew install node@20 >/dev/null 2>&1
  export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
  grep -q 'node@20/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="/opt/homebrew/opt/node@20/bin:$PATH"' >> ~/.zshrc
else
  if [ ! -d "$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1
  fi
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 20 >/dev/null 2>&1 && nvm alias default 20 >/dev/null 2>&1
fi
have node && ok "node $(node --version)" || err "node not on PATH"

# ════════════════════════════════════════════════════════════════════
# 3. Bun (opencode plugin manager uses it)
# ════════════════════════════════════════════════════════════════════
section "Bun"
if ! have bun && [ ! -x "$HOME/.bun/bin/bun" ]; then
  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1
fi
export PATH="$HOME/.bun/bin:$PATH"
have bun && ok "bun $(bun --version 2>/dev/null)" || warn "bun not on PATH (restart shell)"

# ════════════════════════════════════════════════════════════════════
# 4. Cloud / infra CLIs (best-effort)
# ════════════════════════════════════════════════════════════════════
section "Cloud and infra CLIs"
# AWS CLI v2
if ! have aws; then
  if [ "$OS" = "macos" ]; then
    curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg && as_root installer -pkg /tmp/AWSCLIV2.pkg -target / >/dev/null 2>&1 && ok "aws cli" || warn "aws cli"
  else
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip && unzip -oq /tmp/awscliv2.zip -d /tmp && as_root /tmp/aws/install --update >/dev/null 2>&1 && ok "aws cli" || warn "aws cli"
  fi
else ok "aws cli"; fi
# kubectl (mac via brew above; linux direct)
if ! have kubectl && [ "$OS" = "debian" ]; then
  curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && as_root install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl && ok "kubectl" || warn "kubectl"
fi
have kubectl && ok "kubectl present" || warn "kubectl missing"
# helm (linux)
if ! have helm && [ "$OS" = "debian" ]; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 && ok "helm" || warn "helm"
fi
have gcloud || todo "Install gcloud SDK: https://cloud.google.com/sdk/docs/install  (then: gcloud auth login)"

# ════════════════════════════════════════════════════════════════════
# 5. zsh / oh-my-zsh
# ════════════════════════════════════════════════════════════════════
section "zsh / oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >/dev/null 2>&1 && ok "oh-my-zsh" || warn "oh-my-zsh"
else ok "oh-my-zsh present"; fi
[ "$SHELL" = "$(command -v zsh)" ] || todo "Set zsh as default shell: chsh -s \"\$(command -v zsh)\"  (log out/in after)"

# ════════════════════════════════════════════════════════════════════
# 6. AI tools: Claude Code, opencode, Zed, Engram
# ════════════════════════════════════════════════════════════════════
section "AI tools"
# Claude Code — native installer (recommended, auto-updating); fall back to npm
export PATH="$HOME/.local/bin:$PATH"
if ! have claude; then
  curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 && ok "Claude Code (native)" \
    || { npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 && ok "Claude Code (npm)" || err "Claude Code install"; }
fi
have claude && ok "claude $(claude --version 2>/dev/null | head -1)" || warn "claude not on PATH (ensure ~/.local/bin in PATH)"
# opencode
if ! have opencode; then
  if [ "$OS" = "macos" ]; then brew install anomalyco/tap/opencode >/dev/null 2>&1 && ok "opencode" || err "opencode";
  else curl -fsSL https://opencode.ai/install | bash >/dev/null 2>&1 && ok "opencode" || err "opencode"; fi
else ok "opencode present"; fi
# Zed
if ! have zed; then
  if [ "$OS" = "macos" ]; then brew install --cask zed >/dev/null 2>&1 && ok "Zed" || warn "Zed (cask)";
  else curl -f https://zed.dev/install.sh | sh >/dev/null 2>&1 && ok "Zed" || warn "Zed"; fi
else ok "Zed present"; fi
# Engram
if ! have engram; then
  if [ "$OS" = "macos" ]; then brew install gentleman-programming/tap/engram >/dev/null 2>&1 && ok "Engram" || warn "Engram";
  elif have brew; then brew install gentleman-programming/tap/engram >/dev/null 2>&1 && ok "Engram" || warn "Engram";
  else todo "Install Engram on Linux: https://github.com/Gentleman-Programming/engram (Homebrew tap or 'go install')"; fi
else ok "Engram present"; fi

# ════════════════════════════════════════════════════════════════════
# 7. Place vendored config / agents / skills / rules / hooks
# ════════════════════════════════════════════════════════════════════
section "Placing configs and assets"
mkdir -p "$HOME/.claude/agents" "$HOME/.claude/skills" "$HOME/.claude/rules" "$HOME/.claude/hooks" \
         "$HOME/.config/opencode/agents" "$HOME/.config/opencode/commands" "$HOME/.config/opencode/scripts" \
         "$HOME/.config/opencode/plugins" "$HOME/.config/zed" "$HOME/.agents/skills"

# Claude Code
backup "$HOME/.claude/CLAUDE.md" "$REPO_DIR/config/CLAUDE.md"
cp "$REPO_DIR/config/CLAUDE.md" "$HOME/.claude/CLAUDE.md" && ok "CLAUDE.md"
ENGRAM_BIN="$(command -v engram || echo engram)"
backup "$HOME/.claude/settings.json" "$REPO_DIR/config/claude-settings.json"
sed "s#__HOME__#$HOME#g" "$REPO_DIR/config/claude-settings.json" > "$HOME/.claude/settings.json" && ok "claude settings.json (paths templatized)"
if [ -f "$REPO_DIR/config/claude-settings.local.json" ]; then
  backup "$HOME/.claude/settings.local.json" "$REPO_DIR/config/claude-settings.local.json"
  sed "s#__HOME__#$HOME#g" "$REPO_DIR/config/claude-settings.local.json" > "$HOME/.claude/settings.local.json" && ok "claude settings.local.json (permissions)"
fi
cp "$REPO_DIR"/agents/*.md "$HOME/.claude/agents/" && ok "$(ls "$REPO_DIR"/agents/*.md | wc -l | tr -d ' ') CC agents"
cp -R "$REPO_DIR"/skills/* "$HOME/.claude/skills/" && ok "CC skills (folders incl. support scripts)"
cp "$REPO_DIR"/rules/*.md "$HOME/.claude/rules/" && ok "rules"
cp "$REPO_DIR"/hooks/* "$HOME/.claude/hooks/" && chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null && ok "hooks (chmod +x)"

# opencode
backup "$HOME/.config/opencode/opencode.jsonc" "$REPO_DIR/config/opencode.jsonc"
sed "s#__HOME__#$HOME#g" "$REPO_DIR/config/opencode.jsonc" > "$HOME/.config/opencode/opencode.jsonc" && ok "opencode.jsonc (paths templatized)"
cp "$REPO_DIR/config/tui.json" "$HOME/.config/opencode/tui.json" && ok "opencode tui.json"
mkdir -p "$HOME/.opencode"
cp "$REPO_DIR/config/opencode-secondary.json" "$HOME/.opencode/opencode.json" && ok "opencode secondary config (.opencode/opencode.json, prevents drift)"
cp "$REPO_DIR/oh-my-openagent.json" "$HOME/.config/opencode/oh-my-openagent.json" && ok "oh-my-openagent.json"
cp "$REPO_DIR/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" && ok "opencode AGENTS.md"
cp "$REPO_DIR"/opencode-agents/*.md "$HOME/.config/opencode/agents/" && ok "opencode agents"
cp "$REPO_DIR"/opencode-commands/*.md "$HOME/.config/opencode/commands/" && ok "opencode commands"
cp "$REPO_DIR"/opencode-scripts/*.mjs "$HOME/.config/opencode/scripts/" && ok "opencode scripts (check-harness + harness-guards lib/tests)"
if ls "$REPO_DIR"/opencode-plugins/*.js >/dev/null 2>&1; then
  cp "$REPO_DIR"/opencode-plugins/*.js "$HOME/.config/opencode/plugins/" && ok "opencode plugins (harness-guards)"
fi

# Zed (AGENTS.md byte-identical to opencode; engram path resolved for this machine)
cp "$REPO_DIR/AGENTS.md" "$HOME/.config/zed/AGENTS.md" && ok "Zed AGENTS.md (byte-identical)"
backup "$HOME/.config/zed/settings.json" "$REPO_DIR/config/zed-settings.json"
sed "s#__ENGRAM__#$ENGRAM_BIN#g" "$REPO_DIR/config/zed-settings.json" > "$HOME/.config/zed/settings.json" && ok "Zed settings.json (engram → $ENGRAM_BIN)"
cp -R "$REPO_DIR"/zed-skills/* "$HOME/.agents/skills/" && ok "zed-skills → ~/.agents/skills (incl. webapp-testing/scripts)"
# webapp-testing must be a SYMLINK to the Claude Code copy (single source of
# truth; the harness checker enforces this topology)
if [ -f "$HOME/.claude/skills/webapp-testing/SKILL.md" ]; then
  ln -sf "$HOME/.claude/skills/webapp-testing/SKILL.md" "$HOME/.agents/skills/webapp-testing/SKILL.md"
  rm -rf "$HOME/.agents/skills/webapp-testing/scripts"
  ln -s "$HOME/.claude/skills/webapp-testing/scripts" "$HOME/.agents/skills/webapp-testing/scripts" 2>/dev/null
  ok "webapp-testing symlinked → ~/.claude/skills copy"
fi

# ════════════════════════════════════════════════════════════════════
# 8. Playwright (browser/E2E + vision)
# ════════════════════════════════════════════════════════════════════
section "Playwright (browser/E2E)"
if have pip3 || have pip; then
  PIP="$(command -v pip3 || command -v pip)"
  "$PIP" install --user --quiet playwright >/dev/null 2>&1 && python3 -m playwright install chromium >/dev/null 2>&1 && ok "python playwright + chromium" || warn "playwright (install manually: pip install playwright && python -m playwright install chromium)"
else
  todo "Install Playwright for E2E: pip install playwright && python -m playwright install chromium"
fi
ok "Playwright MCP auto-installs via opencode on first launch (npx @playwright/mcp)"

# ════════════════════════════════════════════════════════════════════
# 9. Validate the opencode harness
# ════════════════════════════════════════════════════════════════════
section "Validating harness"
if have node; then
  node "$HOME/.config/opencode/scripts/check-harness.mjs" >/dev/null 2>&1 && ok "harness checker passed" || warn "harness checker reported issues — run: node ~/.config/opencode/scripts/check-harness.mjs"
fi

# ── shell env reminders ───────────────────────────────────────────
grep -q 'HOME/.local/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
grep -q 'HOME/.bun/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.zshrc
grep -q 'KREW_ROOT' ~/.zshrc 2>/dev/null || echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.zshrc

# ════════════════════════════════════════════════════════════════════
# Manual TODO (cannot be automated)
# ════════════════════════════════════════════════════════════════════
todo "Export API keys in ~/.zshrc:  export NAN_API_KEY=\"sk-...\"   export NEW_RELIC_API_KEY=\"NRAK-...\""
todo "Zed edit-prediction key (GUI-launched Zed): launchctl setenv ZED_OPEN_AI_COMPATIBLE_EDIT_PREDICTION_API_KEY \"\$NAN_API_KEY\"  (macOS) — see README §7"
todo "Set the NaN API key in Zed: Cmd/Ctrl+, → AI / Language Models → nan provider → API key"
todo "Authenticate: gh auth login ;  aws configure (or awsume) ;  gcloud auth login"
todo "Launch opencode once so it auto-installs the oh-my-openagent plugin (needs NAN_API_KEY set)"
todo "Claude Code plugins: enabledPlugins is preconfigured in settings.json; first 'claude' launch prompts once per plugin to trust/install"
todo "Auto-sync hook pushes to the Obsidian vault — clone it or the hook will no-op: ~/Documents/obsidian-vault"

section "Done"
[ ${#FAILED[@]} -eq 0 ] && ok "core install completed with no hard failures" || { printf "${c_red}Failures:${c_off}\n"; for x in "${FAILED[@]}"; do echo "  - $x"; done; }
printf "\n${c_yellow}Manual steps remaining:${c_off}\n"
for x in "${TODO[@]}"; do echo "  • $x"; done
printf "\nReopen your shell (or 'source ~/.zshrc') to pick up PATH changes.\n"
