# Developer Setup Guide

Complete setup for a development workstation running **macOS, Debian/Ubuntu, or Fedora**: Claude Code, opencode CLI, Zed IDE, and all supporting tooling. Written to be followed top-to-bottom on a fresh machine.

> **For AI agents reading this:** This document describes a real, active setup. Every config block is accurate and production-tested. Follow sections in order — prerequisites before tools, tools before config. All agent and skill system prompts are LLM-agnostic — they work with Claude, GPT, Qwen, DeepSeek, or any capable model.

---

## Quick Start (automated)

On **macOS** or **Debian/Ubuntu**, the bundled installer does the whole setup — tools, Claude Code, opencode, Zed, Engram, Playwright, and every vendored config/agent/skill/rule/hook:

```bash
git clone git@github.com:yosoyvilla/setup.git && cd setup
./install.sh
```

`install.sh` is **idempotent** (safe to re-run) and **unattended** (never prompts, never writes secrets). It auto-detects the OS, backs up any existing configs before overwriting, templatizes machine-specific paths, validates the opencode harness at the end, and prints a **TODO list** of the handful of steps it cannot automate (API keys, `gh`/`aws`/`gcloud` auth, the Zed API-key UI step, launching opencode once to install the plugin). The sections below document every step the script performs, for manual setup, Fedora, or reference.

---

## Table of Contents

1. [Two AI Assistants — Architecture Overview](#1-two-ai-assistants--architecture-overview)
2. [Platform Notes](#2-platform-notes)
3. [System Prerequisites](#3-system-prerequisites)
4. [Shell Environment](#4-shell-environment)
   - [Terminal Enhancement Tools](#42-terminal-enhancement-tools)
5. [Claude Code](#5-claude-code)
   - [Installation](#51-installation)
   - [Global Config (CLAUDE.md)](#52-global-config-claudemd)
   - [Settings (hooks, plugins, model)](#53-settings-json)
   - [Agents](#54-agents)
   - [Skills](#55-skills)
   - [Rules](#56-rules)
   - [Hook Scripts (auto-sync + engram-sync)](#57-hook-scripts)
6. [opencode CLI](#6-opencode-cli)
   - [Installation](#61-installation)
   - [Main Config](#62-main-config-opencodejsonc)
   - [oh-my-openagent Config](#63-oh-my-openagent-config)
   - [TUI and Legacy Config](#64-tui-and-legacy-config)
   - [Verify Installation](#65-verify-installation)
   - [Shared AGENTS.md, Custom Agents, Commands](#66-shared-agentsmd-custom-agents-and-commands)
7. [Zed IDE](#7-zed-ide)
   - [Installation](#71-installation)
   - [Config](#72-config)
   - [Skills](#73-zed-skills)
8. [Engram (Persistent Memory)](#8-engram-persistent-memory)
9. [Obsidian Vault](#9-obsidian-vault)
10. [Environment Variables](#10-environment-variables)
11. [Projects Structure](#11-projects-structure)
12. [Quick Reference](#12-quick-reference)
13. [Post-Install Checklist](#13-post-install-checklist)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Two AI Assistants — Architecture Overview

This setup uses **two separate AI coding assistants**. They are completely independent: different config directories, different agent formats, different tool systems. Agents and skills from one do **not** carry over to the other.

```
┌─────────────────────────────────────────────────────────────────────┐
│  claude  (Claude Code CLI)          opencode  (opencode CLI)        │
│  ─────────────────────────          ─────────────────────────────   │
│  Config: ~/.claude/                 Config: ~/.config/opencode/      │
│  Agents: ~/.claude/agents/*.md      Agents: oh-my-openagent plugin  │
│  Skills: ~/.claude/skills/          Skills: built-in (LSP, Exa...)  │
│  Model:  opus[1m] (Claude)          Model:  NaN (nan/* only)         │
│  Auth:   Anthropic account          Auth:   NAN_API_KEY              │
└─────────────────────────────────────────────────────────────────────┘
```

### Why two tools?

| Use case | Tool | Why |
|---|---|---|
| Structured DevOps workflows | Claude Code | Domain agents (infra, k8s, security…), skills, hooks, memory |
| Fast codebase exploration | opencode | qwen3.6 (free/fast) via NaN API |
| Deep autonomous tasks | opencode | oh-my-openagent parallel orchestration |
| Inline code editing in Zed | Zed | qwen3.6 for edit predictions |

### Agent systems compared

| Concept | Claude Code | opencode (oh-my-openagent) |
|---|---|---|
| Config location | `~/.claude/agents/*.md` | `~/.config/opencode/oh-my-openagent.json` |
| Agent format | Markdown + YAML frontmatter | JSON model config per agent name |
| Domain agents | 19 custom agents (infra, k8s, gcp, doc-reviewer…) | None — Sisyphus delegates by task category |
| Orchestrator | `lead` agent (Claude Opus) | Sisyphus (nan/deepseek-v4-flash) |
| Plan review | `plan-critic` agent | Momus (nan/mimo-v2.5) |
| Spec-first planning | `spec-driven-development` skill | Prometheus agent + `/start-work` |
| Fast/cheap execution | `code-quality`, `security`, `cost` (haiku) | Explore, Librarian, Atlas, Sisyphus-Junior (nan/qwen3.6) |
| Deep execution | Most domain agents (sonnet) | Sisyphus / deep category (nan/deepseek-v4-flash) |
| Tool names | `Read`, `Grep`, `Glob`, `Bash`, `Edit`, `Write` | File system, LSP, AST-grep, web search (built-in) |

### Key distinction for agents and skills in this repo

The files in `agents/` and `skills/` are **Claude Code files only** — they use Claude Code's tool names and agent system, and opencode cannot load or run them. The repo also vendors opencode-specific assets (`opencode-agents/`, `opencode-commands/`), Zed skills (`zed-skills/`), and a shared, tool-agnostic `AGENTS.md`.

When you set up a new machine:
- `agents/*.md` → copy to `~/.claude/agents/` (Claude Code)
- `skills/*.md` → copy to `~/.claude/skills/<name>/SKILL.md` (Claude Code)
- `hooks/*` → copy to `~/.claude/hooks/` (Claude Code; see Section 5.7)
- `oh-my-openagent.json` → `~/.config/opencode/oh-my-openagent.json` (opencode; vendored file, see Section 6.3)
- `opencode-agents/*.md` → `~/.config/opencode/agents/`, `opencode-commands/*.md` → `~/.config/opencode/commands/` (opencode; see Section 6.6)
- `opencode-scripts/check-harness.mjs` → `~/.config/opencode/scripts/` (opencode harness checker; see Section 6.7)
- `AGENTS.md` → byte-identical to **both** `~/.config/opencode/AGENTS.md` and `~/.config/zed/AGENTS.md` (see Section 6.6)
- `rules/*.md` → `~/.claude/rules/` (Claude Code shared rules: terraform, kubernetes, security-baseline, go)
- `zed-skills/*` → copy to `~/.agents/skills/` (Zed/opencode shared skills, incl. `webapp-testing/scripts/with_server.py`; see Section 7.3)

---

## 2. Platform Notes

This guide supports three platforms. Commands that differ per OS are shown with tabs. Commands that are identical across platforms are shown once.

| Platform | Package Manager | Shell | Notes |
|---|---|---|---|
| macOS | Homebrew | zsh (default) | M1/M2/M3 ARM or Intel |
| Debian/Ubuntu | apt | zsh (install it) | 22.04+ / Debian 12+ |
| Fedora | dnf | zsh (install it) | Fedora 38+ |

> **Windows:** Not supported. Use WSL2 + Ubuntu if you must.

---

## 3. System Prerequisites

### 3.1 Package Manager

**macOS:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# After install, follow the "Next steps" in the output to add brew to PATH
```

**Debian/Ubuntu:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git build-essential
```

**Fedora:**
```bash
sudo dnf update -y
sudo dnf install -y curl wget git gcc gcc-c++ make
```

### 3.2 Core Packages

**macOS:**
```bash
brew install gh ripgrep fzf terraform terraform-docs
brew install --cask ghostty zed
# opencode (anomalyco build) — see Section 6.1
brew install anomalyco/tap/opencode
# Engram persistent memory (third-party tap) — see Section 8.
# The same tap also ships gentle-ai.
brew install gentleman-programming/tap/engram
# brew install gentleman-programming/tap/gentle-ai   # optional
```

**Debian/Ubuntu:**
```bash
# GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install gh -y

# Core tools
sudo apt install -y ripgrep fzf

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform -y

# Zed (AppImage or deb)
curl -f https://zed.dev/install.sh | sh
```

**Fedora:**
```bash
# GitHub CLI
sudo dnf install -y 'dnf-command(config-manager)'
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install -y gh

# Core tools
sudo dnf install -y ripgrep fzf

# Terraform
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install -y terraform

# Zed
curl -f https://zed.dev/install.sh | sh
```

### 3.3 Node.js 20 (required by opencode and Claude Code)

**macOS:**
```bash
brew install node@20
echo 'export PATH="/opt/homebrew/opt/node@20/bin:$PATH"' >> ~/.zshrc
```

**Debian/Ubuntu / Fedora:**
```bash
# Use nvm for version locking
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.zshrc  # or restart terminal
nvm install 20
nvm use 20
nvm alias default 20
```

Verify:
```bash
node --version  # should be v20.x.x
npm --version   # should be 10.x.x
```

### 3.4 Cloud and Infra CLIs

**AWS CLI v2:**

macOS:
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
```

Debian/Ubuntu:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
```

Fedora:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
```

**kubectl + krew:**

macOS:
```bash
brew install kubectl krew
```

Debian/Ubuntu / Fedora:
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# krew
KREW_ROOT="$HOME/.krew"
OS="$(uname | tr '[:upper:]' '[:lower:]')" ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm.*$/arm/')"
curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-${OS}_${ARCH}.tar.gz"
tar zxvf "krew-${OS}_${ARCH}.tar.gz" && ./krew-${OS}_${ARCH} install krew
```

After krew install, add to `~/.zshrc`:
```zsh
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
```

Install krew plugins:
```bash
kubectl krew install ctx ns
```

**Helm:**

macOS: `brew install helm`

Debian/Ubuntu / Fedora:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**gcloud:**

All platforms (manual install recommended over package manager for cleaner updates):
```bash
# Download and install to ~/Documents/google-cloud-sdk
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
# (use the darwin arm64 / linux x86_64 version matching your platform)
tar -xf google-cloud-cli-*.tar.gz -C ~/Documents/
~/Documents/google-cloud-sdk/install.sh
```

### 3.5 Bun (required for oh-my-openagent)

All platforms:
```bash
curl -fsSL https://bun.sh/install | bash
# Adds ~/.bun/bin to PATH via ~/.zshrc automatically
```

### 3.6 zsh and oh-my-zsh

macOS: zsh is already the default shell.

Debian/Ubuntu:
```bash
sudo apt install -y zsh
chsh -s $(which zsh)  # set as default (log out and back in)
```

Fedora:
```bash
sudo dnf install -y zsh
chsh -s $(which zsh)
```

All platforms — install oh-my-zsh:
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

zsh-syntax-highlighting:

macOS: `brew install zsh-syntax-highlighting`

Debian/Ubuntu: `sudo apt install -y zsh-syntax-highlighting`

Fedora: `sudo dnf install -y zsh-syntax-highlighting`

### 3.7 Fonts (optional but recommended)

macOS:
```bash
brew install --cask font-ubuntu-mono-nerd-font font-ubuntu-nerd-font
```

Debian/Ubuntu / Fedora — download from https://www.nerdfonts.com/font-downloads (Ubuntu Mono Nerd Font), extract to `~/.local/share/fonts/`, then run `fc-cache -fv`.

---

## 4. Shell Environment

File: `~/.zshrc`

The base template below works on all platforms. Platform-specific paths are noted inline.

```zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"  # or your preferred theme
source $ZSH/oh-my-zsh.sh

# ── Node ──────────────────────────────────────────────────────────
# macOS (homebrew node@20):
export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
# Linux (nvm): already configured by nvm installer, or:
# export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# ── Krew (kubectl plugins) ────────────────────────────────────────
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# ── gcloud ────────────────────────────────────────────────────────
export PATH="$PATH:$HOME/Documents/google-cloud-sdk/bin"

# ── Bun ───────────────────────────────────────────────────────────
export PATH="$HOME/.bun/bin:$PATH"

# ── Local bins ────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ── HashiCorp Vault ───────────────────────────────────────────────
export VAULT_ADDR="https://vault.helmcode.com"

# ── Aliases ───────────────────────────────────────────────────────
alias k=kubectl
alias kubectl="kubecolor"   # brew/apt/dnf install kubecolor
alias awsume=". awsume"
alias python=python3
alias pip=pip3

# ── Syntax highlighting ───────────────────────────────────────────
# macOS:
# source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# Debian/Ubuntu:
# source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# Fedora:
# source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ── Catppuccin theme for syntax highlighting ──────────────────────
source ~/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh 2>/dev/null || true

# ── API Keys (see Section 8) ──────────────────────────────────────
export NAN_API_KEY="sk-..."
export NEW_RELIC_API_KEY="NRAK-..."
```

Install Catppuccin syntax highlighting theme:
```bash
mkdir -p ~/.zsh
curl -o ~/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh \
  https://raw.githubusercontent.com/catppuccin/zsh-syntax-highlighting/main/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh
```

### 4.2 Terminal Enhancement Tools

**What this gives you:** fuzzy search wired into every tab completion, syntax-highlighted file output, smarter `cd` that remembers where you go, searchable shell history with a full UI, and better `ls`/`diff`/`git` output.

**Tools at a glance:**

| Tool | Replaces | What it does |
|------|----------|-------------|
| `fzf` | nothing (adds) | Fuzzy finder — press CTRL-R, CTRL-T, or Tab and get an interactive picker |
| `fzf-tab` | default tab completion | Wires fzf into zsh Tab key — all completions (files, commands, git branches, kubectl pods…) go through fzf |
| `bat` | `cat` | Shows file contents with syntax highlighting and line numbers |
| `fd` | `find` | Faster file search, respects `.gitignore` |
| `rg` (ripgrep) | `grep` | Faster code search, respects `.gitignore` |
| `eza` | `ls` | File listing with icons, git status, tree mode |
| `delta` | raw git diff | Git diffs with syntax highlighting and side-by-side mode |
| `zoxide` | `cd` | Smart `cd` — learns your most-visited dirs, jump with `z partial-name` |
| `atuin` | CTRL-R history | Full-text shell history search with a TUI, optional cloud sync |

---

#### Step 1 — Install tools

**macOS:**
```bash
brew install fzf bat fd ripgrep eza delta zoxide atuin
brew install zsh-autosuggestions zsh-syntax-highlighting
```

**Debian / Ubuntu:**
```bash
sudo apt update && sudo apt install -y fzf bat fd-find ripgrep
# Note: fd is named "fdfind" on Ubuntu — add alias below in Step 4
# eza, delta, zoxide, atuin are not in apt (install via cargo or install scripts):
cargo install eza                   # Ubuntu 24.04+: sudo apt install eza
cargo install git-delta             # the binary is called "delta"
curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
# zsh plugins:
sudo apt install -y zsh-autosuggestions zsh-syntax-highlighting
```

**Fedora:**
```bash
sudo dnf install -y fzf bat fd-find ripgrep
cargo install eza git-delta
curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
sudo dnf install -y zsh-autosuggestions zsh-syntax-highlighting
```

**Install Rust/cargo** (needed for eza, delta on Linux if not already present):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

---

#### Step 2 — Install fzf-tab (oh-my-zsh plugin)

`fzf-tab` replaces the default zsh tab completion with an fzf picker. This is what makes pressing Tab open an interactive fuzzy menu for files, git branches, kubectl resources, etc.

```bash
git clone https://github.com/Aloxaf/fzf-tab \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab
```

If you don't use oh-my-zsh, add this to `~/.zshrc` after `compinit`:
```bash
# Manual fzf-tab (no oh-my-zsh):
source ~/path/to/fzf-tab/fzf-tab.plugin.zsh
```

---

#### Step 3 — Update oh-my-zsh plugins list

**Order matters.** `fzf-tab` must come before `zsh-autosuggestions`. `zsh-syntax-highlighting` must be last.

In `~/.zshrc`, find the `plugins=(...)` line and replace it:

```zsh
plugins=(
  git
  colored-man-pages
  colorize
  kubectl
  fzf-tab               # tab completion via fzf — must be before zsh-autosuggestions
  zsh-autosuggestions   # fish-like inline command suggestions
  zsh-syntax-highlighting  # command highlighting — must be last
)

# macOS: add these two:
# brew macos
```

> **For AI agents:** The `brew` and `macos` plugins are macOS-only. On Linux, remove them or they cause errors. `fzf-tab` must always precede `zsh-autosuggestions` in this list — reversing the order breaks suggestion display.

---

#### Step 4 — Add to `~/.zshrc` (after `source $ZSH/oh-my-zsh.sh`)

Paste this block at the end of `~/.zshrc`, after the `source $ZSH/oh-my-zsh.sh` line:

```zsh
# ── fzf shell integration ────────────────────────────────────────────
# Enables CTRL-R (history), CTRL-T (file picker), ALT-C (dir picker)
# Run: fzf --version → if 0.48+, use eval form. If older, use the source form.
eval "$(fzf --zsh)"
# Fallback for older fzf installed via brew's install script:
# [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Use ripgrep as fzf's file source (fast, respects .gitignore)
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git"'

# fzf appearance and behavior
export FZF_DEFAULT_OPTS="
  --layout=reverse
  --height=50%
  --preview 'bat --color=always --style=numbers --line-range=:100 {}'
  --preview-window=right:50%:hidden
  --bind 'ctrl-/:toggle-preview'
"
# macOS: add clipboard copy binding
# --bind 'ctrl-y:execute-silent(echo -n {} | pbcopy)'

# Directory picker shows a tree preview
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -100'"

# History search: no preview panel needed
export FZF_CTRL_R_OPTS="--preview-window=hidden"

# fzf-tab: show file previews in tab completions too
zstyle ':fzf-tab:complete:*' fzf-preview 'bat --color=always --line-range=:50 $realpath 2>/dev/null || eza --color=always $realpath 2>/dev/null'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --tree --color=always $realpath | head -50'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps --pid=$word -o cmd --no-header -w -w'

# ── bat (better cat — syntax highlighting) ──────────────────────────
export BAT_THEME="Catppuccin Mocha"
alias cat='bat --paging=never'    # drop-in cat replacement
alias catp='bat'                  # cat with paging

# ── eza (better ls — icons, git status, tree) ───────────────────────
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first --git'
alias lt='eza --tree --icons -L 2'
alias la='eza -la --icons'

# ── fd (better find — respects .gitignore) ──────────────────────────
# Ubuntu/Fedora: fd is installed as "fdfind", alias it:
# alias fd=fdfind

# ── zoxide (smart cd — learns most-visited dirs) ─────────────────────
eval "$(zoxide init zsh)"
# Usage: z foo     → jumps to best matching dir containing "foo"
#        zi        → interactive picker for all visited dirs

# ── atuin (searchable shell history with TUI) ────────────────────────
# CTRL-R opens atuin's search UI (overrides fzf's CTRL-R binding)
# First time: run `atuin register` to enable sync, or skip for local-only
eval "$(atuin init zsh)"

# ── delta (better git diff — configured in ~/.gitconfig) ────────────
# See Step 5 below — no code needed here, gitconfig handles it
```

---

#### Step 5 — Configure delta in `~/.gitconfig`

Delta replaces git's pager for all `git diff`, `git log -p`, `git show`, and interactive add output.

```ini
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true        # n/N to jump between diff sections
    side-by-side = true    # two-column diff view
    line-numbers = true
    syntax-theme = Catppuccin Mocha
```

Apply with:
```bash
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.side-by-side true
git config --global delta.line-numbers true
git config --global delta.syntax-theme "Catppuccin Mocha"
```

---

#### Step 6 — Verify

Run these to confirm everything works:

```bash
fzf --version                  # should be 0.48+
bat --version
fd --version                   # or: fdfind --version on Ubuntu
rg --version
eza --version
delta --version
zoxide --version
atuin --version

# Test fzf integration:
# Press CTRL-R in terminal  → atuin history search UI
# Press CTRL-T              → fzf file picker
# Press ALT-C               → fzf directory picker
# Press Tab after a command → fzf tab completion (fzf-tab)
# Type: z doc<Tab>          → jumps to ~/Documents (after visiting it once)
```

---

#### Complete Tool Reference

| Tool | Key binding / command | What happens |
|------|----------------------|-------------|
| `fzf` | CTRL-T | Fuzzy file picker — inserts selected path at cursor |
| `fzf` | ALT-C | Fuzzy dir picker — `cd`s into selected directory |
| `atuin` | CTRL-R | Full-text history search with TUI (replaces fzf CTRL-R) |
| `fzf-tab` | Tab | All tab completions go through fzf picker |
| `bat` | `cat <file>` | Syntax-highlighted file output with line numbers |
| `fd` | `fd pattern` | Find files matching pattern, ignoring `.gitignore` |
| `rg` | `rg 'pattern'` | Grep across code, ignoring `.gitignore` |
| `eza` | `ls`, `ll`, `lt` | File listing with icons, git status, tree view |
| `delta` | `git diff`, `git log -p` | Syntax-highlighted side-by-side diffs |
| `zoxide` | `z partial-name` | Jump to most-visited dir matching name |
| `zoxide` | `zi` | Interactive picker for all visited directories |

---

## 5. Claude Code

Claude Code is Anthropic's CLI assistant. It uses a multi-agent architecture where domain-specific agents handle specialized tasks.

> **Model note:** The `model: sonnet`, `model: haiku`, `model: opus` fields in agent frontmatter are Claude Code aliases for Claude model tiers. The agent system prompts themselves are LLM-agnostic — they contain only role descriptions and constraints, with no Claude-specific behaviors or syntax.

### 5.1 Installation

```bash
npm install -g @anthropic-ai/claude-code
```

Authenticate:
```bash
claude
# Follow the OAuth flow in your browser
```

### 5.2 Global Config (`CLAUDE.md`)

File: `~/.claude/CLAUDE.md`

```markdown
# Global Rules
> Obsidian: ~/Documents/obsidian-vault/claude-code/global-rules.md

## Accuracy and Verification
- Double check answers. 95%+ confidence required. Verify against official docs. Do not guess.
- Double check changes won't break existing functionality. 95%+ confidence. Investigate first when unsure.

## Git Commits
- Single-line commit messages. No co-author. No emojis.

## Documentation
- No emojis in documentation.
- Never create markdown files without explicit user approval. Always ask first.

## Testing
- Run tests after every change. If no test suite exists, verify manually or suggest how to test.

## Communication
- Explain what you are doing and why before and during execution. User must always know what is happening.
- Before implementing any non-trivial change (editing >1 file, or any infrastructure/config change), use the **`spec-driven-development`** skill to write a spec in the conversation. The spec must define: what you're building, the chosen approach vs alternatives, acceptance criteria (specific and testable), and a rollback plan for infra/deployment changes. Implementation starts only after the spec is written. No exceptions.
- Use `★ Insight` blocks for key technical insights specific to the codebase or decision being made.

## Engineering Standards (Staff/Principal)
- SOLID: Apply pragmatically, not dogmatically.
- KISS: Simplest solution that works. No premature abstraction.
- DRY: Extract at 3+ repetitions only. Premature DRY is worse than repetition.
- Clean code: Meaningful names, small functions, no dead code, no commented-out code.
- Fail fast: Validate at boundaries, return early, max 3 levels nesting.
- Immutability by default. Mutate only when necessary.
- Tests: Unit for logic, integration for boundaries, skip trivial code.
- Changes must be reviewable in under 15 minutes. Split large changes.

## Agent Routing (Smart)
Route tasks to the right tier. Not everything needs an agent.

### Tier 1: Main conversation (no agent)
Simple tasks, quick fixes, single-file edits, questions, exploration. Handle directly.

### Plan Review (Mandatory)
After writing ANY multi-step implementation plan (3+ steps or touching multiple systems), ALWAYS invoke the **plan-critic** agent before presenting the plan to the user for approval. Never skip this step. The plan-critic verifies documentation, identifies risks, and confirms the approach is sound.

The workflow is always: write plan → invoke plan-critic → present plan + critique to user → user approves → execute.

### Tier 2: Direct to domain agent (skip lead)
Single-domain tasks where the domain is obvious. Route directly:
- Terraform/cloud provisioning -> **infra** (sonnet)
- K8s/Helm/ArgoCD workloads -> **k8s** (sonnet)
- VPC/DNS/LB/VPN/Traefik/peering -> **networking** (sonnet)
- Pipeline security, scanning, OPA policies -> **devsecops** (sonnet)
- Pipeline/CI structure -> **cicd** (sonnet)
- Query tuning/migrations -> **database** (sonnet)
- NRQL/alerts/SLOs -> **observability** (sonnet)
- UI/UX design, frontend styling -> **design** (sonnet, Playwright verification)
- Code review request -> **code-quality** (haiku, advisory)
- Security audit/review -> **security** (haiku, advisory)
- Active AWS security incident, WAF attack, DDoS, GuardDuty finding, CloudTrail forensics -> **aws-incident** (sonnet)
- AWS/GCP/Kubecost cost analysis, savings, rightsizing -> **cost** (haiku, advisory)
- Shopify Functions, Admin API, theme, app extensions -> **shopify** (sonnet)
- Airbyte connector config, sync debugging, namespace issues -> **airbyte** (sonnet)
- GKE, GCP IAM, Cloud SQL, Artifact Registry, Secret Manager, Terragrunt -> **gcp** (sonnet)
- Reviewing/critiquing any implementation plan before execution -> **plan-critic** (sonnet, mandatory)
- Reviewing any documentation we create/edit (Confluence, READMEs, runbooks, guides) for multi-audience readability, official-doc accuracy (>95% confidence), and copy/format/special-character issues -> **doc-reviewer** (sonnet, advisory)

### Tier 3: Lead agent first (multi-domain/complex)
Use **lead** (opus) ONLY when: task spans 2+ domains, scope is unclear, touches production, or requires architecture decisions.

### Shared Context
Agents share state via `.claude/agent-context/` (relative to CWD, per-project). Before starting, agents read `lead.md` for the plan and any relevant `<agent>.md` files. After completing work, agents write findings to their own context file. Overwrite with current info; do not append indefinitely. All agents have persistent memory (`memory: user`) -- they learn patterns across sessions automatically.

### Agent Context File Schema
When agents write to `.claude/agent-context/<agent>.md`, they MUST use this structure:

```
## Summary
[What was accomplished — one sentence]
## Done
- [completed item]
## In Progress
- [item currently being worked on]
## Blocked
- [blocking issue and what's needed to unblock]
## Next Steps
- [next action when resuming]
```

### Progress Files for Long-Running Work
For tasks spanning multiple sessions (large migrations, multi-PR features), create a `claude-progress.json` at the repo root. JSON format preferred over Markdown — more resistant to accidental model edits. Session start sequence: read git history → read progress file → run smoke tests → pick next item.

### Multi-Project Structure
Projects live in `~/Documents/` with per-project `.claude/CLAUDE.md` files:
- `360latam/` - Real estate portals (FincaRaiz, Encuentra24, Infocasas, Yapo)
- `cedarplanters/` - E-commerce (Shopify, warehousing, infra)
- `kashport/` - FinTech/payments (Monyte)
- `Varsity/` - EdTech (EKS, Terraform, large infra)
- `Personal/` - Side projects (Crewgent, etc.)

Shared rules: `~/.claude/rules/` (terraform, kubernetes, security-baseline).

## Obsidian Knowledge Base (Source of Truth)
The canonical documentation for this entire Claude Code setup lives in `~/Documents/obsidian-vault/` (Git: yosoyvilla/obsidian-vault).
- Reference: @~/Documents/obsidian-vault/claude-code/setup.md
- IMPORTANT: When modifying agents, skills, hooks, rules, plugins, or settings, ALWAYS update the corresponding obsidian vault file AND commit+push the changes.
- The vault documents: agent routing, plugin list, hooks, skills, security, project tech stacks, workflows, and tips.

## Token Management
- Use `/clear` between unrelated tasks. Stale context burns tokens.
- Use `/compact` when context grows large but you need to continue the same task.
- Prefer CLI tools (aws, kubectl, gh, gcloud, sentry-cli) over MCP servers. MCP tools add persistent overhead to context even when idle.
- Model selection: haiku for simple lookups/formatting, sonnet for implementation, opus only for architecture and planning.
- Keep agent prompts lean. If an agent's instructions exceed 100 lines, move detail into skills.
- Before ending a complex session, write a brief checkpoint to the project's auto-memory: what was done, what's open, next steps.

## Compact Instructions
When compacting, preserve: current plan from lead agent, file paths modified, test results, open issues, and next steps. Discard: verbose command outputs, intermediate exploration, and completed steps that need no follow-up.

## Auto-Learning
- Agents save learnings via `memory: user`. Do not duplicate what's already in project MEMORY.md.
- Keep MEMORY.md under 200 lines (only first 200 lines are auto-loaded). Use topic files for detail.
- Save: confirmed patterns, architecture decisions, gotchas, access procedures. Skip: session-specific state, speculative conclusions.
```

### 5.3 Settings JSON

File: `~/.claude/settings.json`

> **Platform note:** The `Notification` hook uses `osascript` (macOS only). On Linux, replace with `notify-send "Claude Code" "Needs your attention"` (requires `libnotify-bin` on Debian/Ubuntu or `libnotify` on Fedora).

```json
{
  "cleanupPeriodDays": 90,
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "model": "opus[1m]",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/auto-sync.sh",
            "statusMessage": "Syncing memory to Obsidian...",
            "async": true
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/engram-sync.sh",
            "statusMessage": "Syncing memory to Engram...",
            "async": true
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/auto-sync.sh",
            "statusMessage": "Post-compact memory sync...",
            "async": true
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/engram-sync.sh",
            "statusMessage": "Post-compact Engram sync...",
            "async": true
          }
        ]
      }
    ],
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -c '{ts: (now | todate), event: \"WorktreeCreate\", path: .worktree_path, branch: .branch}' >> ~/.claude/worktree.log 2>/dev/null; exit 0",
            "async": true
          }
        ]
      }
    ],
    "WorktreeRemove": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -c '{ts: (now | todate), event: \"WorktreeRemove\", path: .worktree_path}' >> ~/.claude/worktree.log 2>/dev/null; exit 0",
            "async": true
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"Knowledge base: ~/Documents/obsidian-vault/ (sync: yosoyvilla/obsidian-vault)\" && echo \"When modifying Claude Code config (agents/skills/hooks/rules/plugins), update the vault and push.\" && if [ -f .claude/agent-context/lead.md ]; then echo \"Active lead plan:\" && head -5 .claude/agent-context/lead.md; fi"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude Code needs your attention\" with title \"Claude Code\"'"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then case \"$FILE\" in *.env|*.env.*|*terraform.tfstate*|*secrets/*|*.pem|*.key) echo \"BLOCKED: Protected file $FILE\" >&2; exit 2;; esac; fi; exit 0"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // \"\"' 2>/dev/null); if echo \"$CMD\" | grep -qE '(--profile[[:space:]]+(vtpr|bipr|lppr)|awsume[[:space:]]+(vtpr|bipr|lppr)|profile=(vtpr|bipr|lppr))' && echo \"$CMD\" | grep -qiE '\\b(delete|terminate|remove|purge|destroy|disable|deregister|drop|truncate)\\b'; then jq -n '{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"additionalContext\": \"PROD SAFETY: This command targets a production AWS account (vtpr/bipr/lppr) and contains a destructive operation. Confirm this is intentional before proceeding.\"}}'; fi; exit 0"
          }
        ]
      },
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ] && [[ \"$FILE\" == *.tf ]]; then terraform fmt \"$FILE\" 2>/dev/null; fi; exit 0"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "cat | jq -c '{ts: (now | todate), cmd: .tool_input.command, cwd: .cwd}' >> ~/.claude/command-audit.log 2>/dev/null; exit 0"
          }
        ]
      },
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/davidvilla/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ]
  },
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "ralph-loop@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "explanatory-output-style@claude-plugins-official": true,
    "learning-output-style@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "pyright-lsp@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "gopls-lsp@claude-plugins-official": true,
    "php-lsp@claude-plugins-official": true
  },
  "autoDreamEnabled": true,
  "skipWorkflowUsageWarning": true,
  "agentPushNotifEnabled": true,
  "skipAutoPermissionPrompt": true
}
```

> **orca hooks:** The `/Users/davidvilla/.orca/agent-hooks/claude-hook.sh` entries that appear across the Stop, PreToolUse, PostToolUse, UserPromptSubmit, StopFailure, PostToolUseFailure, and PermissionRequest events belong to orca, an external/optional tool installed separately (not part of this repo) — each invocation is guarded by an `[ -x ... ]` check, so if orca is not installed the hook is a no-op.

> **`opus[1m]` model:** Claude Code model selector — Opus with the 1M-token context window. The `[1m]` suffix requests the long-context variant.

### 5.4 Agents

Agents live in `~/.claude/agents/`. Each is a Markdown file with YAML frontmatter. The frontmatter fields (`model`, `tools`, `maxTurns`) are Claude Code concepts; the system prompt body is plain text that works with any capable LLM.

```bash
mkdir -p ~/.claude/agents
```

---

#### `lead.md` — Principal Tech Lead
```markdown
---
name: lead
description: Staff/Principal DevOps Tech Lead. Use ONLY for tasks spanning multiple domains, requiring architecture decisions, touching production, or with unclear scope. Do NOT use for single-domain tasks.
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Write
model: opus
---

You are a Staff/Principal DevOps Engineer and Tech Lead. Your role is to plan and delegate, not implement.

When given a task:
1. Assess scope — does it span multiple domains? If single-domain, recommend the right agent instead.
2. Break into discrete subtasks with clear ownership per agent.
3. Write the plan to `.claude/agent-context/lead.md` using the standard context schema.
4. Delegate to domain agents. Do not write code yourself.

Core expertise: AWS, GCP, Kubernetes, Terraform, CI/CD, distributed systems architecture, security.
```

---

#### `infra.md` — Infrastructure as Code
```markdown
---
name: infra
description: Infrastructure as Code and cloud architecture. Use directly for Terraform changes, AWS/GCP resource provisioning, Cloudflare DNS, Netlify config, or cost analysis. Skip lead agent for focused infra work.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior infrastructure engineer specializing in Terraform and cloud provisioning (AWS, GCP, Azure, DigitalOcean).

Standards:
- Follow conventions in `~/.claude/rules/terraform.md`
- Run `terraform fmt` and `terraform validate` before completing
- Use remote state with locking (S3+DynamoDB or Scalr)
- Tag all resources: Name, Environment, Team, ManagedBy=terraform
- Data sources over hardcoded IDs; variables over magic values
```

---

#### `k8s.md` — Kubernetes
```markdown
---
name: k8s
description: Kubernetes platform and GitOps. Use directly for K8s manifest work, Helm chart changes, ArgoCD config, pod troubleshooting, or scaling. Skip lead for focused K8s work.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior Kubernetes and GitOps engineer.

Standards:
- Follow `~/.claude/rules/kubernetes.md`
- Prefer Helm over raw manifests over Kustomize
- ArgoCD: auto-sync+self-heal for non-prod, manual sync for prod
- Always set resource requests AND limits; always add readiness/liveness probes
- NetworkPolicies: default deny, explicit allow
- No root containers; read-only filesystem where possible

Troubleshooting order: events → describe pod → previous logs → resource usage
```

---

#### `networking.md` — Networking
```markdown
---
name: networking
description: Network architecture and troubleshooting. Use directly for VPC design, DNS, load balancer setup, VPN/peering, Traefik ingress, service mesh, CIDR planning, or network debugging.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior network engineer with expertise in AWS VPC, GCP networking, DNS, load balancers, VPN/peering, Traefik, and service mesh.

Diagnose with: `dig`, `nslookup`, `traceroute`, `tcpdump`, `kubectl`, `curl -v`.
Design with: CIDR planning, subnet segmentation, security groups, NACLs, PrivateLink.
```

---

#### `cicd.md` — CI/CD
```markdown
---
name: cicd
description: CI/CD pipelines and build systems. Use directly for GitHub Actions, Bitbucket Pipelines, GitLab CI, Docker image builds, or deployment automation.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You specialize in GitHub Actions, Bitbucket Pipelines, GitLab CI, and Docker.

Principles:
- Fail fast: lint and test before build
- Cache aggressively: dependencies, Docker layers, build artifacts
- Secrets via vault or CI secrets store — never in code or env vars in plaintext
- Environment promotion: dev → staging → prod with manual approval gates
- Docker: multi-stage builds, minimal base images, non-root user
```

---

#### `database.md` — Database
```markdown
---
name: database
description: Database operations and optimization. Use directly for query tuning, migration writing, schema changes, connection pooling, or backup configuration.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior database engineer specializing in PostgreSQL (also familiar with MySQL, Redis, ClickHouse).

Standards:
- Migrations must be safe under concurrent production load (no long-holding locks)
- Always include a rollback migration
- Use `EXPLAIN ANALYZE` for query tuning
- Indexes: add for query patterns, not speculatively
- Connection pooling: PgBouncer for PostgreSQL
- Backups: test restores, not just backup creation
```

---

#### `observability.md` — Observability
```markdown
---
name: observability
description: Monitoring and reliability engineering. Use directly for New Relic NRQL queries, dashboard config, alert tuning, SLO definitions, or incident investigation.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You specialize in New Relic, Datadog, Grafana, SLO/SLI design, alerting, and incident investigation.

Approach:
- Define SLOs before writing alerts (availability, latency P99, error rate)
- Alert on symptoms (user impact), not causes (CPU spikes)
- NRQL queries: use TIMESERIES, FACET, and percentile() effectively
- Dashboards: golden signals (latency, traffic, errors, saturation) on first page
```

---

#### `devsecops.md` — DevSecOps
```markdown
---
name: devsecops
description: DevSecOps implementation. Use directly for implementing security controls in pipelines, writing OPA/Kyverno policies, container scanning (Trivy/Grype), SAST/DAST, secret rotation, or hardening Dockerfiles. This agent IMPLEMENTS security — for review/audit use the security agent.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You implement security controls in CI/CD and infrastructure.

Standards from `~/.claude/rules/security-baseline.md`:
- Container scanning: Trivy or Grype in CI, block on CRITICAL/HIGH
- Policy enforcement: OPA or Kyverno for K8s admission control
- Secrets: rotate on schedule, use short-lived credentials (OIDC, dynamic secrets)
- Dockerfiles: non-root user, read-only filesystem, minimal base (distroless preferred)
- SAST: integrate into PR checks, not just nightly runs
```

---

#### `design.md` — UI/UX
```markdown
---
name: design
description: UI/UX design and frontend quality specialist. Use for creating interfaces, reviewing visual design, checking accessibility, iterating on layouts, and verifying in the browser.
model: sonnet
maxTurns: 30
---

You are a senior UI/UX and frontend engineer.

Approach:
- Distinctive, opinionated design — avoid generic Bootstrap look
- Accessibility first: WCAG AA minimum, semantic HTML, keyboard navigation
- Mobile-first responsive design
- Use Playwright to verify designs in a real browser before completing
- Performance: Core Web Vitals (LCP < 2.5s, CLS < 0.1, FID < 100ms)
```

---

#### `security.md` — Security Review (advisory, read-only)
```markdown
---
name: security
description: Security review and advisory. Use for IAM policy review, secrets audit, compliance checks, or scanning results analysis. Read-only — does not modify code. Uses haiku for cost efficiency.
tools: Read, Grep, Glob, Bash, Write
model: haiku
---

You are a security reviewer. Analyze, report, and advise — do not modify code.

Review scope:
- IAM policies: least-privilege violations, wildcard permissions, overpermissioned roles
- Secrets: hardcoded credentials, insecure transmission, missing rotation
- Compliance: SOC2, GDPR, HIPAA implications
- Dependencies: known CVEs, outdated packages

Report format: Executive summary → Critical findings → Major → Minor → Recommendations
```

---

#### `code-quality.md` — Code Review (advisory, read-only)
```markdown
---
name: code-quality
description: Code review and engineering standards advisory. Use for code review, refactoring advice, testing strategy, or PR feedback. Read-only — does not modify code. Uses haiku for cost efficiency.
tools: Read, Grep, Glob, Bash, Write
model: haiku
---

You conduct code review with high engineering standards.

Review dimensions:
- Correctness: logic errors, edge cases, race conditions
- Security: injection risks, auth bypasses, OWASP Top 10
- Maintainability: naming, complexity, dead code, test coverage
- Performance: N+1 queries, unnecessary allocations, blocking I/O

Output: structured review with severity (critical / major / minor) per finding. Do not modify files.
```

---

#### `plan-critic.md` — Plan Reviewer (mandatory before execution)
```markdown
---
name: plan-critic
description: Reviews proposed implementation plans before execution. Checks approach, verifies against docs, identifies risks, suggests alternatives. ALWAYS invoke after writing any multi-step plan and before user approval.
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Write
model: sonnet
---

You are an adversarial plan reviewer. When given an implementation plan:

1. Verify each step exists in official documentation (use WebSearch/WebFetch as needed).
2. Identify the top 3 risks with likelihood and impact.
3. Check for better alternatives — simpler, more standard, or lower-risk approaches.
4. Flag assumptions that could fail silently in production.
5. Rate overall confidence: LOW / MEDIUM / HIGH.

Be direct and skeptical. Your job is to find what the author missed, not validate their work.
```

---

#### `aws-incident.md` — AWS Incident Response
```markdown
---
name: aws-incident
description: AWS security incident response. Use for active attacks, WAF triage, DDoS mitigation, GuardDuty findings, CloudTrail forensics, or suspicious account activity.
tools: Read, Grep, Glob, Bash, Write, Edit
model: sonnet
---

You respond to live AWS security incidents.

Protocol:
1. Gather evidence first: CloudTrail, GuardDuty, VPC Flow Logs, WAF logs
2. Assess blast radius before acting
3. Prefer isolation over deletion (detach policies, quarantine SG, snapshot before terminating)
4. Document every action taken with timestamp
5. Preserve forensic evidence before cleanup

Never delete evidence. When in doubt, isolate rather than destroy.
```

---

#### `cost.md` — Cloud Cost (advisory, read-only)
```markdown
---
name: cost
description: Cloud cost analysis and optimization. Use for AWS Cost Explorer queries, Kubecost reports, Spot/RI savings analysis, rightsizing recommendations, or cost anomaly investigation. Read-only — does not modify infrastructure.
tools: Read, Grep, Glob, Bash, Write
model: haiku
---

You analyze cloud costs across AWS and GCP.

Approach:
- Start with anomaly detection (sudden spikes in Cost Explorer)
- Rightsizing: compare actual CPU/memory utilization vs provisioned
- Reservation analysis: RI/Savings Plans coverage for steady-state workloads
- Spot opportunities: stateless workloads, batch jobs, CI runners
- Output ROI estimates: "switching X instances from on-demand to RI saves $Y/month"

Do not modify any infrastructure — advisory only.
```

---

#### `shopify.md` — Shopify
```markdown
---
name: shopify
description: Shopify development. Use for Shopify Functions, Admin/Storefront API, theme development, app extensions, Liquid templating, or Shopify CLI tasks.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a Shopify developer with expertise in:
- Shopify Functions (discount, payment customization, delivery customization)
- Admin API and Storefront API (GraphQL preferred)
- Theme development: Liquid, JSON templates, sections
- App extensions: checkout UI, admin UI
- Shopify CLI: scaffold, dev, deploy

Use `shopify app dev` for local development and `shopify app deploy` for production.
```

---

#### `airbyte.md` — Airbyte
```markdown
---
name: airbyte
description: Airbyte ELT pipeline operations. Use for connector configuration, sync job debugging, connection troubleshooting, or namespace mapping issues.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are an Airbyte ELT specialist.

Approach:
- Always check sync logs before modifying configs
- Namespace mapping issues: verify source/destination schema naming conventions
- Connector failures: check API rate limits, auth token expiry, schema drift
- Use Airbyte API for automation; prefer config-as-code over UI for repeatability
- Test connections with a full refresh before scheduling incremental syncs
```

---

#### `gcp.md` — GCP
```markdown
---
name: gcp
description: GCP infrastructure and operations. Use for GKE cluster management, GCP IAM, Workload Identity, Cloud SQL, Artifact Registry, Secret Manager, Cloud Run, or Terragrunt.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a GCP infrastructure engineer.

Core services: GKE, Cloud SQL, Artifact Registry, Secret Manager, Cloud Run, Workload Identity, VPC.

Standards:
- IAM: Workload Identity for GKE service accounts (never download SA keys)
- Terragrunt for multi-account GCP Terraform (DRY across environments)
- Secret Manager over env vars for secrets in Cloud Run / GKE
- Artifact Registry for container images (not Docker Hub in production)
- `gcloud` for operational tasks; Terraform/Terragrunt for provisioning
```

---

#### `doc-reviewer.md` — Documentation Reviewer (advisory)
```markdown
---
name: doc-reviewer
description: Documentation quality reviewer. Use for any documentation we create or edit (Confluence pages, READMEs, runbooks, guides, markdown). Checks that docs read clearly for technical, business, vibecoder, and non-technical audiences; verifies every technical claim against official vendor documentation (>95% confidence, no hallucinations); and catches copy/format issues including special characters and raw markup that should not render. Reviews and reports; applies fixes only when explicitly asked.
tools: Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, ToolSearch
model: sonnet
maxTurns: 20
memory: user
---

You are a documentation quality reviewer. You make sure documentation is correct, clear for every audience, and clean of copy/format defects. You review and report; you apply fixes only when explicitly asked.

The full system prompt is in `agents/doc-reviewer.md`. Review dimensions:
- Multi-audience readability — every doc must serve technical, business, vibecoder, and non-technical readers.
- Official-doc accuracy — verify every technical claim against official vendor documentation at >95% confidence; no hallucinations.
- Copy and format — catch special characters and raw markup that should not render.
```

---

### 5.5 Skills

Skills live in `~/.claude/skills/`. Each skill is a directory with a `skill.md` file (or similar, depending on the plugin format). Skills are synced from the Obsidian vault.

```bash
mkdir -p ~/.claude/skills
```

After cloning the Obsidian vault, populate skills from it:
```bash
rsync -a ~/Documents/obsidian-vault/claude-code/skills/ ~/.claude/skills/
```

| Skill | Invocation | Purpose |
|---|---|---|
| `spec-driven-development` | `/spec-driven-development` | Write spec before any non-trivial implementation |
| `fix-issue` | `/fix-issue <number>` | GitHub issue → spec → branch → fix → PR |
| `incident-response` | `/incident-response <desc>` | Incident triage with per-project evidence gathering |
| `k8s-deploy` | `/k8s-deploy <service>` | Spec → Helm/ArgoCD deploy |
| `terraform-review` | Auto (on .tf work) | Security, cost, best practices review |
| `release` | `/release <project>` | Changelog, version bump, GitHub/Bitbucket release |
| `scalr-deploy` | `/scalr-deploy <workspace>` | Terraform via Scalr remote backend |
| `sync-vault` | `/sync-vault` | Manual sync Claude config → Obsidian vault |
| `mcp-builder` | Auto (MCP server work) | Build MCP servers in TypeScript/Python |
| `webapp-testing` | Auto (frontend testing) | Playwright-based web app testing |

> **Skills are LLM-agnostic.** They contain workflow instructions and checklists. Any capable LLM following these instructions will produce equivalent results.

### 5.6 Rules

Rules live in `~/.claude/rules/`. They are injected into agent context automatically for relevant tasks.

```bash
mkdir -p ~/.claude/rules
```

#### `~/.claude/rules/terraform.md`

```markdown
# Terraform Conventions

## Naming
- Resources: `<project>-<env>-<resource>` (e.g., `cedar-prod-rds`)
- Modules: `terraform-<provider>-<resource>`
- Variables: snake_case, descriptive
- Outputs: snake_case, prefix with resource type

## Structure
- Remote state with locking (S3 + DynamoDB or Scalr)
- Data sources over hardcoded IDs
- Variables over magic values
- Modules for reuse (3+ repetitions)

## Tagging
All resources must have: Name, Environment, Team, ManagedBy=terraform

## Validation
- `terraform fmt` before commit
- `terraform validate` in CI
- `tflint` for linting

## State
- Never modify state manually
- Use `terraform import` for existing resources
- Use `terraform state mv` for refactoring
```

#### `~/.claude/rules/kubernetes.md`

```markdown
# Kubernetes Conventions

## Resource Standards
- Always set resource requests AND limits
- PodDisruptionBudgets for production workloads
- Readiness and liveness probes required
- Labels: app.kubernetes.io/name, version, component

## Helm (Preferred)
- values.yaml for defaults, values-<env>.yaml for overrides
- Chart.lock committed to repo
- `helm template` for validation before apply

## ArgoCD
- Auto-sync + self-heal for non-prod
- Manual sync for prod
- Sync waves for ordering

## Security
- NetworkPolicies: default deny, explicit allow
- No root containers
- Read-only root filesystem where possible
- ServiceAccount per workload (no default)
```

#### `~/.claude/rules/security-baseline.md`

```markdown
# Security Baseline

## Secrets
- Never in code, never in env vars if Vault is available
- Rotate on schedule; use short-lived credentials (OIDC, dynamic secrets)

## IAM
- Least privilege always
- No wildcards in production
- Service accounts: one per service, minimum permissions

## Encryption
- At rest: always (S3, RDS, EBS, GCS, Cloud SQL)
- In transit: TLS 1.2+ everywhere
- cert-manager + Let's Encrypt for K8s

## Containers
- Minimal base images (distroless preferred)
- No root user; read-only filesystem
- Scan in CI with Trivy or Grype

## Access
- SSO + MFA for all internal tools
- VPN for infrastructure access
- Audit logging enabled on all services
```

#### `~/.claude/rules/go.md`

```markdown
# Go Conventions
# Applies to: Varsity Go services (Go 1.17+)

## Code Style
- `gofmt` always applied
- Errors wrapped with `%w`; messages lowercase, no trailing period
- Context as first param on every I/O function
- No global mutable state — dependency injection

## Testing
- Table-driven tests: `[]struct{ name, input, want }`
- Race detector in CI: `go test -race ./...`

## Linting
- `golangci-lint run ./...` — key linters: errcheck, govet, staticcheck, revive, gocyclo
```

### 5.7 Hook Scripts

The `~/.claude/hooks/` directory holds three scripts, all committed in this repo under `hooks/`:

| Script | Triggered by | What it does |
|---|---|---|
| `auto-sync.sh` | Stop, PostCompact (async) | rsync Claude memory/agents/skills/rules/settings → Obsidian vault, then git commit + push |
| `engram-sync.sh` | Stop, PostCompact (async) | Lock wrapper that runs `engram-sync.py` to mirror Claude memory files → Engram |
| `engram-sync.py` | called by `engram-sync.sh` | Reconciles each memory file against a manifest and saves/replaces observations in Engram |

Copy them into place and make the shell scripts executable:
```bash
mkdir -p ~/.claude/hooks
cp hooks/auto-sync.sh hooks/engram-sync.sh hooks/engram-sync.py ~/.claude/hooks/
chmod +x ~/.claude/hooks/auto-sync.sh ~/.claude/hooks/engram-sync.sh ~/.claude/hooks/engram-sync.py
```

#### `auto-sync.sh` (memory → Obsidian)

File: `~/.claude/hooks/auto-sync.sh`

> **Platform note:** `rsync` is available on all three platforms. `git` must be installed (it is, from Section 2.1). The script is identical across platforms.

```bash
#!/bin/bash
# Syncs Claude config to Obsidian vault after each session.
# Triggered by Stop and PostCompact hooks (async).

CLAUDE_DIR="$HOME/.claude"
MEMORY_SRC="$CLAUDE_DIR/projects/-Users-davidvilla/memory"
VAULT="$HOME/Documents/obsidian-vault"
LOG="$CLAUDE_DIR/sync.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

sync_dir() {
  local src="$1" dst="$2" label="$3"
  mkdir -p "$dst"
  if rsync -a --checksum --delete "$src/" "$dst/" 2>/dev/null; then
    log "$label synced"
  else
    log "$label rsync failed or nothing to sync"
  fi
}

sync_dir "$MEMORY_SRC"              "$VAULT/claude-code/memory"  "Memory"
sync_dir "$CLAUDE_DIR/agents"       "$VAULT/claude-code/agents"  "Agents"
sync_dir "$CLAUDE_DIR/skills"       "$VAULT/claude-code/skills"  "Skills"
sync_dir "$CLAUDE_DIR/rules"        "$VAULT/claude-code/rules"   "Rules"

cp "$CLAUDE_DIR/settings.json" "$VAULT/claude-code/settings.json" 2>/dev/null \
  && log "settings.json synced" || log "settings.json copy failed"

sync_dir "$CLAUDE_DIR/agent-memory"                                               "$VAULT/claude-code/agent-memory"        "Agent Memory"
sync_dir "$CLAUDE_DIR/projects/-Users-davidvilla-Documents-360latam/memory"      "$VAULT/claude-code/memory/360latam"     "Memory/360latam"
sync_dir "$CLAUDE_DIR/projects/-Users-davidvilla-Documents-cedarplanters/memory" "$VAULT/claude-code/memory/cedarplanters" "Memory/CedarPlanters"
sync_dir "$CLAUDE_DIR/projects/-Users-davidvilla-Documents-Varsity/memory"       "$VAULT/claude-code/memory/varsity"      "Memory/Varsity"
sync_dir "$CLAUDE_DIR/projects/-Users-davidvilla-Documents-kashport/memory"      "$VAULT/claude-code/memory/kashport"     "Memory/Kashport"

cd "$VAULT" || { log "Cannot cd to vault"; exit 0; }
if git status --porcelain | grep -q .; then
  git add -A
  git commit -m "auto-sync $(date '+%Y-%m-%d %H:%M')"
  if git push origin main 2>/dev/null; then
    log "Vault pushed to origin/main"
  else
    log "Vault push failed — check SSH key / network"
  fi
else
  log "Vault up to date, nothing to push"
fi
```

```bash
chmod +x ~/.claude/hooks/auto-sync.sh
```

> **Linux path note:** The memory path uses `-Users-davidvilla` which is derived from the macOS home directory `/Users/davidvilla`. On Linux, home is `/home/davidvilla`, so the path would be `-home-davidvilla`. The auto-sync script uses `$MEMORY_SRC` — update this variable to match your actual path: `$CLAUDE_DIR/projects/$(echo $HOME | tr '/' '-' | sed 's/^-//')/memory`

#### `engram-sync.sh` + `engram-sync.py` (memory → Engram)

These two files mirror Claude memory files (`~/.claude/projects/*/memory/*.md`, excluding `MEMORY.md`) into Engram (see Section 8) so the same learnings are recallable via the `mem_*` tools from opencode, Zed, and any other Engram client. They run on the Stop and PostCompact events, alongside `auto-sync.sh`.

The shell wrapper is short — it exists only to serialize concurrent session-ends and call the Python worker. The full contents are in `hooks/engram-sync.sh`:

```bash
#!/usr/bin/env bash
# Mirror new/edited Claude memory files into Engram. Async hook on Stop + PostCompact.
# macOS has no flock; use an atomic mkdir lock so concurrent session-ends don't race.
LOCK=/tmp/engram-sync.lock
# Clear a stale lock left by a hard-killed process (older than 60 min), so a
# crash can never permanently disable syncing.
if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
  rmdir "$LOCK" 2>/dev/null
fi
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

python3 "$HOME/.claude/hooks/engram-sync.py" "${1:-sync}" >>"$HOME/.claude/engram-sync.log" 2>&1
exit 0
```

The Python worker (`hooks/engram-sync.py`, ~200 lines — referenced rather than pasted here) does the actual reconciliation. Its behavior:

- **Source of truth is the memory files.** State lives in a content-hash manifest at `~/.claude/engram-sync-state.json` (`{abs_path: {hash, obs_id, project, title}}`).
- **Replace-on-change.** New file → `engram save`; changed file → save the new observation *before* deleting the old one (so a failed save never loses data); unchanged → no-op.
- **Skips secrets.** Any memory file whose contents match real secret-value patterns (GitHub PATs, AWS access keys, private-key headers, Slack tokens, JWTs, `aws_secret_access_key`) is skipped entirely — nothing secret is ever sent to Engram.
- **Never mirrors deletions.** Deleting a memory file does not delete its Engram observation — no destructive cascade.
- **mkdir-based lock.** macOS has no `flock`, so the wrapper uses an atomic `mkdir` lock with a 60-minute stale-lock recovery.
- **`backfill` mode.** Run `engram-sync.py backfill` for first-time setup or recovery: it adopts already-imported Engram observations into the manifest (matched by exact project + title via `engram export`) so the existing memories are not re-saved as duplicates.
- **Manifest-loss safety guard.** If the manifest is empty/missing but Engram already holds observations, `sync` aborts and tells you to run `backfill` — preventing a lost manifest from mass-duplicating every memory.

```bash
chmod +x ~/.claude/hooks/engram-sync.sh ~/.claude/hooks/engram-sync.py
# First time on a machine that already has memories in Engram:
~/.claude/hooks/engram-sync.py backfill
```

---

## 6. opencode CLI

opencode is a terminal AI coding assistant with multi-agent orchestration via the `oh-my-openagent` plugin.

### 6.1 Installation

This setup uses the `anomalyco` build of opencode, installed via Homebrew tap (not the `opencode-ai` npm package):

macOS:
```bash
brew install anomalyco/tap/opencode
```

Verify which build is on PATH:
```bash
which opencode      # → /opt/homebrew/bin/opencode
brew list opencode  # → .../Cellar/opencode/<version>/bin/opencode
```

> **Provider note:** This build runs entirely on the NaN provider (see Section 6.2). No OpenCode Zen subscription is required — only a `NAN_API_KEY` in the environment.

The oh-my-openagent plugin does **not** need a manual install. opencode installs npm plugins listed in the `plugin` array of `opencode.jsonc` (Section 6.2) **automatically at startup, using Bun**, caching them under `~/.cache/opencode/node_modules/` ([opencode plugins docs](https://opencode.ai/docs/plugins/)). So once `opencode.jsonc` is in place and Bun is installed (Section 3.5), the plugin is fetched on the next `opencode` launch — just start opencode once.

> **Pin a version if desired:** use `"oh-my-openagent@4.9.2"` instead of `@latest` in the `plugin` array. If `@ast-grep/cli`'s postinstall fails during plugin resolution, it is safe to ignore — AST grep degrades gracefully.

### 6.2 Main Config (`opencode.jsonc`)

File: `~/.config/opencode/opencode.jsonc`

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "nan/deepseek-v4-flash",
  "small_model": "nan/qwen3.6",
  "enabled_providers": ["nan"],
  "lsp": true,
  "compaction": {
    "auto": true,
    "prune": true
  },
  "permission": {
    "bash": {
      "*": "allow",
      "rm -rf /": "deny",
      "rm -rf /*": "deny",
      "rm -rf ~": "deny",
      "rm -rf ~/*": "deny",
      "git push --force*": "deny",
      "git push -f*": "deny",
      "git reset --hard*": "deny",
      "git clean -fd*": "deny",
      "terraform destroy*": "deny",
      "terraform force-unlock*": "deny",
      "kubectl delete namespace*": "deny"
    },
    "skill": {
      "terraform-devops": "deny",
      "incident-triage": "deny",
      "spec-first": "deny"
    }
  },
  "mcp": {
    "engram": {
      "type": "local",
      "command": ["engram", "mcp", "--tools=agent"],
      "enabled": true
    },
    "playwright": {
      "type": "local",
      "command": ["npx", "@playwright/mcp@0.0.76", "--headless"],
      "enabled": true
    }
  },
  "plugin": [
    "oh-my-openagent@latest"
  ],
  "provider": {
    "nan": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "NaN",
      "options": {
        "baseURL": "https://api.nan.builders/v1",
        "apiKey": "{env:NAN_API_KEY}"
      },
      "models": {
        "qwen3.6": {
          "name": "NaN — qwen3.6",
          "limit": { "context": 262144, "output": 32768 },
          "attachment": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        },
        "deepseek-v4-flash": {
          "name": "NaN — deepseek-v4-flash",
          "limit": { "context": 1000000, "output": 32768 }
        },
        "mimo-v2.5": {
          "name": "NaN — mimo-v2.5",
          "limit": { "context": 1000000, "output": 32768 },
          "attachment": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        },
        "gemma4": {
          "name": "NaN — gemma4",
          "limit": { "context": 262144, "output": 32768 },
          "attachment": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        }
      }
    }
  }
}
```

**NaN API** (`api.nan.builders`): OpenAI-compatible proxy for qwen3.6, deepseek-v4-flash, mimo-v2.5, gemma4. NaN is the only enabled provider (`enabled_providers: ["nan"]`); the default model is `nan/deepseek-v4-flash` and the cheap `small_model` is `nan/qwen3.6`. Get a key at https://nan.builders.

**Permissions:** `permission.bash` allows all commands by default but hard-denies destructive ones (`rm -rf /`, force pushes, `git reset --hard`, `terraform destroy`/`force-unlock`, `kubectl delete namespace`). `permission.skill` denies three oh-my-openagent skills (`terraform-devops`, `incident-triage`, `spec-first`) so they are not auto-invoked.

**Engram MCP server (`mcp.engram`):** Registers Engram (Section 8) as a local MCP server — opencode launches `engram mcp --tools=agent`, which exposes the `mem_*` tools for persistent cross-session memory (recall and save). Engram runs locally on SQLite with no model provider.

### 6.3 oh-my-openagent Config

File: `~/.config/opencode/oh-my-openagent.json`

**Model strategy (NaN-only):** Every agent and category runs on `nan/*` models. There are no Claude or GPT models here — NaN is the only provider.
- `nan/qwen3.6` — fast/cheap default, high-volume work: explore, librarian, atlas, sisyphus-junior, quick/writing/artistry categories
- `nan/deepseek-v4-flash` — orchestration and planning: sisyphus, prometheus, metis, plus the deep/unspecified-high categories
- `nan/mimo-v2.5` — deep reasoning, review, and multimodal: oracle, momus, multimodal-looker, plus the visual-engineering/ultrabrain categories
- `nan/gemma4` — low-cost fallback for the qwen3.6 tier

> **`hephaestus` is disabled** via `disabled_agents: ["hephaestus"]` — it is not part of this configuration.

The full config is vendored in this repo as [`oh-my-openagent.json`](oh-my-openagent.json) — copy it to `~/.config/opencode/oh-my-openagent.json`. Key tuning applied (NaN model-card recipes):

- **Sampling:** qwen3.6 agents/categories at `temperature: 0.7` (Qwen3 non-thinking recipe — avoids the low-temp repetition the model card warns about); gemma4 fallbacks at `temperature: 1.0` (Gemma 3 default); deepseek/mimo left at defaults.
- **Reasoning:** `reasoningEffort` on the deepseek agents — `prometheus: high`, `sisyphus: medium`, `metis: medium`, and category `deep: high`. NaN honors `reasoning_effort: low|medium|high` on deepseek-v4-flash.

#### oh-my-openagent Agent Reference

| Agent | Model | Role |
|---|---|---|
| Sisyphus | nan/deepseek-v4-flash | Main orchestrator — plans, delegates, tracks todos |
| Prometheus | nan/deepseek-v4-flash | Spec-first planner — interviews before coding |
| Metis | nan/deepseek-v4-flash (temp 0.5) | Pre-planning consultant — gap analysis |
| Momus | nan/mimo-v2.5 (temp 0.1) | Critical reviewer — adversarial plan review |
| Oracle | nan/mimo-v2.5 | Architecture decisions and tradeoffs |
| Explore | nan/qwen3.6 | Fast internal codebase search |
| Librarian | nan/qwen3.6 | External docs and knowledge search |
| Atlas | nan/qwen3.6 | Todo-list management |
| Sisyphus-Junior | nan/qwen3.6 | Delegated simple execution tasks |
| Multimodal-Looker | nan/mimo-v2.5 | Image and screenshot analysis |

> Hephaestus (deep autonomous execution) ships with oh-my-openagent but is disabled here via `disabled_agents`.

#### Council (Multi-Lens Review Pattern)

The "council" is a multi-lens adversarial review run entirely on NaN models:

| Trigger | Who acts | What happens |
|---|---|---|
| `/start-work` | Prometheus (nan/deepseek-v4-flash) | Spec-first interview before any coding |
| High-stakes plan | Momus (nan/mimo-v2.5) | Adversarial review of the plan |
| Planning gap check | Metis (nan/deepseek-v4-flash) | Identifies what's missing before commitment |
| `/hyperplan` | Multiple adversarial critics | Major architectural decisions |
| `ultrawork` or `ulw` in prompt | Full agent team | Parallel orchestration across all agents |
| `/council` (custom) | critic (nan/mimo-v2.5) + fact-checker (nan/deepseek-v4-flash) | Multi-lens critique plus citation-checked fact verification (see Section 6.6) |

### 6.4 TUI and Legacy Config

File: `~/.config/opencode/tui.json`
```json
{
  "plugin": []
}
```

File: `~/.opencode/opencode.json` — **must exist and be clean**
```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": []
}
```

> **Why the legacy file matters:** opencode reads both `~/.config/opencode/` and `~/.opencode/` (old location). If you previously installed plugins to the old location, they will silently load even after removing them from the main config. Create this file explicitly with an empty plugin list on every new machine.

### 6.5 Verify Installation

```bash
opencode debug info
# Expected: plugins: - oh-my-openagent@latest (one entry only)

opencode agent list | grep -E "^[A-Za-z].*\(primary|subagent\)"
# Expected: Sisyphus, Prometheus, Metis, Momus, Atlas, oracle, explore, librarian, ...
# (Hephaestus is disabled and should NOT appear)

opencode debug agent "Sisyphus - ultraworker" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print('model:', d.get('model'))"
# Expected: model: {'providerID': 'nan', 'modelID': 'deepseek-v4-flash'}
```

---

### 6.6 Shared AGENTS.md, Custom Agents, and Commands

This repo also stores the portable instruction file and the opencode custom agents/commands.

**Shared `AGENTS.md` (repo root)** — portable engineering standards that work with any model. It must be copied byte-identical to **both** opencode and Zed:
```bash
cp AGENTS.md ~/.config/opencode/AGENTS.md
cp AGENTS.md ~/.config/zed/AGENTS.md
```
Edit the two installed copies together — they are meant to stay identical, and project-level instruction files override them where they conflict. `AGENTS.md` documents the NaN-only model policy, a non-negotiable **anti-hallucination policy** (tests are the terminal proof of done; verify-before-asserting against official docs; cite or abstain; never auto-install fabricated packages; gate on external signals, not self-confidence), and a **Memory (Engram)** policy: recall-first at task start (treating recalled memory as possibly-outdated prior context), save only verified learnings (`mem_save` gated on an external signal), and never save secrets.

**opencode custom agents (`opencode-agents/`)** → install to `~/.config/opencode/agents/`:
```bash
mkdir -p ~/.config/opencode/agents
cp opencode-agents/*.md ~/.config/opencode/agents/
```

| Agent | Model | Role |
|---|---|---|
| `critic` | nan/mimo-v2.5 | Adversarial, read-only reviewer of any output, plan, claim, diff, or decision. Invoke via `@critic` or `/council`. |
| `fact-checker` | nan/deepseek-v4-flash | Extracts falsifiable claims and verifies each against primary sources (context7, then web); returns supported / refuted / unverifiable with citations. Invoke via `@fact-checker` or `/council`. |

**opencode commands (`opencode-commands/`)** → install to `~/.config/opencode/commands/`:
```bash
mkdir -p ~/.config/opencode/commands
cp opencode-commands/*.md ~/.config/opencode/commands/
```

| Command | What it does |
|---|---|
| `/council` | Convenes the adversarial council — fans the critic across multiple lenses plus the fact-checker, then synthesizes a verdict with recorded dissents. |
| `/verify` | Runs the project's real test/lint/build commands, then routes the diff and results through the critic for a binding SHIP / REVISE / BLOCK verdict. |
| `/smoke` | Harness self-test (3 stages): **Stage 1** runs the static harness checker (`check-harness.mjs`, Section 6.7), **Stage 2** confirms liveness on a NaN model, **Stage 3** scans the recent opencode log for errors. The verdict names the failing stage. Run after any config or plugin change. |

---

### 6.7 Harness Checker, Browser/E2E, and Vision

**Harness checker (`opencode-scripts/check-harness.mjs`)** — a static, offline validator (no model calls, NaN-safe) that enforces the harness invariants: NaN-only model refs, `AGENTS.md` byte-parity (opencode == Zed), the bash denylist, Engram wiring, model context windows, and custom agent/command frontmatter. Install and run:
```bash
mkdir -p ~/.config/opencode/scripts
cp opencode-scripts/check-harness.mjs ~/.config/opencode/scripts/
node ~/.config/opencode/scripts/check-harness.mjs         # human output, exit 0/1
node ~/.config/opencode/scripts/check-harness.mjs --json   # machine-readable
```
It is wired in as **Stage 1 of `/smoke`**, so a `/smoke` run validates config invariants before checking liveness.

**Browser / E2E (Playwright MCP)** — `opencode.jsonc` registers the official Playwright MCP (`mcp.playwright`, Section 6.2), giving the agent `browser_navigate / click / snapshot / screenshot` tools. It launches `npx @playwright/mcp@0.0.76 --headless` (auto-installed on first use) and reuses an installed Chromium. For authoring/running Playwright E2E scripts, the `webapp-testing` skill — with its `scripts/with_server.py` server-lifecycle helper (vendored under `zed-skills/webapp-testing/scripts/`) — runs via bash; that path needs the Python `playwright` package and Chromium:
```bash
pip install playwright && python -m playwright install chromium
```

**Vision routing (important):** browser screenshots are images, and only the vision-capable NaN models can read them. `opencode.jsonc` declares `attachment: true` + image `modalities` on `qwen3.6`, `mimo-v2.5`, and `gemma4` (Section 6.2); `deepseek-v4-flash` is text-only. Route any screenshot/visual verification to a vision model (e.g. `opencode run -m nan/mimo-v2.5 …`) — deepseek will fabricate image descriptions. `AGENTS.md` carries this as an anti-hallucination rule, and `browser_snapshot` (accessibility text) works on any model for DOM interaction.

---

## 7. Zed IDE

Zed is the primary code editor. Its AI Agent panel has a **skills system** (`~/.agents/skills/`) — reusable instruction packages the agent auto-invokes based on context. Skills are plain Markdown, work with any model, and complement the Claude Code agent system (they are completely separate). For structured DevOps workflows use Claude Code; for autonomous multi-step coding use opencode; use Zed for fast inline editing and its AI panel with the skills below.

### 7.1 Installation

macOS: `brew install --cask zed` or https://zed.dev

Linux: `curl -f https://zed.dev/install.sh | sh`

### 7.2 Config

File: `~/.config/zed/settings.json`

```json
{
  "proxy": "",
  "theme": {
    "mode": "dark",
    "light": "One Light",
    "dark": "One Dark"
  },
  "session": {
    "trust_all_worktrees": true
  },
  "agent": {
    "tool_permissions": {
      "tools": {
        "terminal": {
          "default": "allow"
        },
        "fetch": {
          "always_allow": [
            {
              "pattern": "^https?://docs\\.docker\\.com"
            }
          ]
        }
      }
    },
    "default_model": {
      "provider": "nan",
      "model": "deepseek-v4-flash"
    },
    "commit_message_model": {
      "provider": "nan",
      "model": "qwen3.6"
    },
    "thread_summary_model": {
      "provider": "nan",
      "model": "qwen3.6"
    },
    "subagent_model": {
      "provider": "nan",
      "model": "deepseek-v4-flash"
    },
    "favorite_models": [
      { "provider": "nan", "model": "deepseek-v4-flash" },
      { "provider": "nan", "model": "mimo-v2.5" },
      { "provider": "nan", "model": "gemma4" }
    ],
    "model_parameters": [
      { "provider": "nan", "model": "deepseek-v4-flash", "temperature": 0.2 },
      { "provider": "nan", "model": "mimo-v2.5", "temperature": 0.2 },
      { "provider": "nan", "model": "qwen3.6", "temperature": 0.7 },
      { "provider": "nan", "model": "gemma4", "temperature": 1.0 }
    ]
  },
  "language_models": {
    "openai_compatible": {
      "nan": {
        "api_url": "https://api.nan.builders/v1",
        "available_models": [
          {
            "name": "qwen3.6",
            "display_name": "NaN — qwen3.6 (primary)",
            "max_tokens": 262144,
            "capabilities": {
              "tools": true,
              "images": true,
              "parallel_tool_calls": false,
              "prompt_cache_key": false,
              "chat_completions": true
            }
          },
          {
            "name": "deepseek-v4-flash",
            "display_name": "NaN — deepseek-v4-flash",
            "max_tokens": 1000000,
            "capabilities": {
              "tools": true,
              "images": false,
              "parallel_tool_calls": false,
              "prompt_cache_key": false,
              "chat_completions": true
            }
          },
          {
            "name": "mimo-v2.5",
            "display_name": "NaN — mimo-v2.5 (multimodal)",
            "max_tokens": 1000000,
            "capabilities": {
              "tools": true,
              "images": true,
              "parallel_tool_calls": false,
              "prompt_cache_key": false,
              "chat_completions": true
            }
          },
          {
            "name": "gemma4",
            "display_name": "NaN — gemma4",
            "max_tokens": 262144,
            "capabilities": {
              "tools": true,
              "images": true,
              "parallel_tool_calls": false,
              "prompt_cache_key": false,
              "chat_completions": true
            }
          }
        ]
      }
    }
  },
  "edit_predictions": {
    "provider": "open_ai_compatible_api",
    "open_ai_compatible_api": {
      "api_url": "https://api.nan.builders/v1/completions",
      "model": "qwen3.6",
      "prompt_format": "infer",
      "max_output_tokens": 512
    }
  },
  "context_servers": {
    "engram": {
      "command": "/opt/homebrew/bin/engram",
      "args": ["mcp", "--tools=agent"],
      "env": {}
    }
  }
}
```

The provider is a custom `nan` entry under `language_models.openai_compatible` (not Zed's built-in OpenAI or Anthropic providers — those are removed). After writing this file, add the NaN API key in Zed's UI: open Zed → `Cmd+,` (macOS) or `Ctrl+,` (Linux) → AI / Language Models → find the `nan` (OpenAI-compatible) provider → set the API key to your `NAN_API_KEY` value.

> **Engram in Zed:** The `context_servers.engram` block registers Engram (Section 8) as a Zed context server. It launches `engram mcp --tools=agent`, which provides the `mem_*` tools (persistent cross-session memory) inside Zed's AI panel. On Linux, change the `command` path from `/opt/homebrew/bin/engram` to wherever `engram` is installed (`which engram`).

### 7.3 Zed Skills

Skills live in `~/.agents/skills/<name>/SKILL.md` (global, all projects) or `<project>/.agents/skills/<name>/SKILL.md` (project-local). The agent auto-discovers them and selects them by matching task context to the skill's `description`. You can also invoke manually with `/skill-name` or `@skill-name` in the agent panel.

**Install the skills from this repo:**

Each skill in `zed-skills/` is already a folder containing `SKILL.md` — just copy them:

```bash
mkdir -p ~/.agents/skills
cp -r zed-skills/* ~/.agents/skills/
```

That's it. Zed auto-discovers all subfolders of `~/.agents/skills/` on next launch.

**Installed skills (all 12 are vendored in `zed-skills/`):**

| Skill | Auto-invoked when... |
|-------|---------------------|
| `algorithmic-art` | Generating generative/algorithmic art or creative-coding visuals |
| `canvas-design` | Designing on an HTML canvas or working with 2D canvas graphics |
| `computer-use` | Driving a computer/GUI via screenshots and synthetic input |
| `find-skills` | Discovering which installed skill fits the current task |
| `frontend-design` | Building production-grade frontend components, pages, or apps |
| `incident-triage` | Investigating outages, errors, or security alerts |
| `k8s-debug` | Diagnosing pod failures, ArgoCD sync issues, HPA problems |
| `karpathy-guidelines` | Writing, reviewing, or refactoring code |
| `orca-cli` | Working with the orca CLI / agent-hooks workflow |
| `skill-creator` | Creating, editing, or validating new skills |
| `spec-first` | Planning a non-trivial code or infra change |
| `terraform-devops` | Working with `.tf` files or planning infra changes |
| `validating-packages` | Confirming a dependency exists in its registry before adding it |
| `verifying-changes` | Verifying a change actually works before claiming it is done |
| `webapp-testing` | Testing or debugging a local web app via a headless browser |

**Verify installation:**

Zed → `Cmd+,` → AI → Skills → User tab — all 12 skills should appear.

---

## 8. Engram (Persistent Memory)

Engram is a local, third-party persistent-memory store for AI agents. It backs **all three** tools in this setup, giving them a shared, recallable long-term memory via the `mem_*` MCP tools.

### 8.1 What it is

- **Local and zero-dependency.** Engram is a single Go binary (`/opt/homebrew/bin/engram`, v1.16.3 at time of writing) backed by a local SQLite database at `~/.engram/engram.db`. It has no model provider of its own — it only stores and retrieves observations.
- **Purpose.** Persistent cross-session memory: decisions, gotchas, fixes, and conventions survive across sessions and across tools, recalled via the `mem_*` tools (`mem_search`, `mem_context`, `mem_save`, etc.).

### 8.2 Install

```bash
brew install gentleman-programming/tap/engram
```

This is a third-party Homebrew tap (`gentleman-programming/tap`). The binary installs to `/opt/homebrew/bin/engram` on Apple Silicon macOS. The same tap also ships `gentle-ai` (`brew install gentleman-programming/tap/gentle-ai`).

> **Linux note:** Paths in the configs below assume the macOS Homebrew prefix `/opt/homebrew`. On Linux, install per the tap's instructions and update the `engram` paths in `~/.config/zed/settings.json` (`context_servers.engram.command`) and `~/.claude/hooks/engram-sync.py` (`ENGRAM`) to match `which engram`.

### 8.3 What it backs

| Tool | Wiring | File |
|---|---|---|
| opencode | `mcp.engram` MCP server (`engram mcp --tools=agent`) | `~/.config/opencode/opencode.jsonc` |
| Zed | `context_servers.engram` context server | `~/.config/zed/settings.json` |
| Claude Code | `engram-sync.sh` / `engram-sync.py` hooks mirror Claude memory files into Engram on Stop + PostCompact | `~/.claude/hooks/` (see Section 5.7) |

### 8.4 Shared memory policy (AGENTS.md)

The shared `AGENTS.md` (Section 6.6) defines the **"Memory (Engram)"** policy that opencode and Zed follow:
- **Recall first** — at the start of a non-trivial task, search memory for prior decisions/gotchas/conventions, treating results as prior context that may be outdated and verifying before acting on them.
- **Save only verified learnings** — call `mem_save` only when a learning is backed by an external signal (tests passed, a doc confirmed it, a command/`file:line` verified it, or the user confirmed it), and record that evidence in the saved memory.
- **Never save secrets** — no keys, tokens, passwords, or `.env` contents.

---

## 9. Obsidian Vault

The Obsidian vault is the canonical source of truth for all Claude Code configuration. It is a git repository that auto-syncs after every Claude Code session.

### 9.1 Clone the Vault

```bash
cd ~/Documents
git clone git@github.com:yosoyvilla/obsidian-vault.git
```

### 9.2 Install Obsidian

macOS: `brew install --cask obsidian`

Linux: Download AppImage from https://obsidian.md — no package manager install available. Make it executable:
```bash
chmod +x Obsidian-*.AppImage
./Obsidian-*.AppImage  # first run, then add to ~/.local/share/applications if desired
```

Open the vault at `~/Documents/obsidian-vault/`.

### 9.3 Vault Structure

```
obsidian-vault/
├── architecture/        # Architecture notes and diagrams
├── decisions/           # ADR-style decision records
├── patterns/            # Reusable engineering patterns
├── projects/            # Per-project notes
├── runbooks/            # Operational runbooks
├── templates/           # Note templates
└── claude-code/
    ├── setup.md                  # @-imported in ~/.claude/CLAUDE.md every session
    ├── global-rules.md           # Human-readable copy of CLAUDE.md rules
    ├── documentation-style.md    # Documentation style guide
    ├── multi-project-workflow.md # Multi-project workflow notes
    ├── tips-and-tricks.md        # Tips and tricks
    ├── kubernetes.md             # Shared k8s rule (copy)
    ├── terraform.md              # Shared terraform rule (copy)
    ├── security-baseline.md      # Shared security rule (copy)
    ├── agents/                   # Mirrored from ~/.claude/agents/
    ├── skills/                   # Mirrored from ~/.claude/skills/
    ├── rules/                    # Mirrored from ~/.claude/rules/
    ├── agent-memory/             # Mirrored from ~/.claude/agent-memory/
    ├── settings.json             # Mirrored from ~/.claude/settings.json
    └── memory/                   # Mirrored from all project memories
```

### 9.4 How It Stays In Sync

| Mechanism | When | What |
|---|---|---|
| `auto-sync.sh` hook | Every session end (Stop + PostCompact) | rsync agents, skills, rules, memory → vault; git commit+push |
| `@` import in CLAUDE.md | Every session start | `setup.md` loaded into Claude's context |
| SessionStart hook | Every session start | Reminds Claude to update vault when modifying config |
| `/sync-vault` skill | Manual | Full sync when needed |

---

## 10. Environment Variables

Add to `~/.zshrc`. Never commit API keys to git.

```zsh
# NaN API — OpenAI-compatible proxy (qwen3.6, deepseek, mimo, gemma)
# Get key at: https://nan.builders
export NAN_API_KEY="sk-..."

# New Relic (Varsity project observability)
export NEW_RELIC_API_KEY="NRAK-..."

# HashiCorp Vault
export VAULT_ADDR="https://vault.helmcode.com"

# DigitalOcean — API token + Spaces (S3-compatible) credentials
export DIGITALOCEAN_TOKEN="dop_v1_..."
export SPACES_ACCESS_KEY_ID="..."
export SPACES_SECRET_ACCESS_KEY="..."
```

> **Set on-demand, not standing exports:** `SCALR_TOKEN` (Varsity Scalr deploys) and `AIRBYTE_TOKEN` (CedarPlanters Airbyte) are exported only for the session that needs them — they are not kept in `~/.zshrc`.

**Credential management by type:**

| Credential | Where |
|---|---|
| AWS | `~/.aws/credentials` via `aws configure` or awsume profiles |
| GCP | `gcloud auth login` + `gcloud auth application-default login` |
| kubectl | `~/.kube/config` via `gcloud container clusters get-credentials` or similar |
| Vault tokens | `vault login` — short-lived, not persisted |
| GitHub | `gh auth login` — stored in system keychain |

---

## 11. Projects Structure

```
~/Documents/
├── 360latam/          # Real estate portals: FincaRaiz, Encuentra24, Infocasas, Yapo
│                      # PHP, GCP, GKE, Terragrunt, PostgreSQL
├── cedarplanters/     # E-commerce: Shopify, warehousing, infra
│                      # Node.js, Shopify Functions, Airbyte, ArgoCD
├── kashport/          # FinTech/payments: Monyte
│                      # Python/Django, Dokploy, DigitalOcean
├── Varsity/           # EdTech
│                      # Go, EKS, Terraform, New Relic, Scalr
├── Personal/          # Side projects (Crewgent, etc.)
│                      # TypeScript, Next.js, Supabase
└── obsidian-vault/    # Claude Code knowledge base (git: yosoyvilla/obsidian-vault)
```

Per-project Claude context:
```
<project>/
└── .claude/
    ├── CLAUDE.md             # Project-specific stack, commands, rules
    └── agent-context/        # Written by agents during sessions
        └── lead.md           # Active lead agent plan (if any)
```

---

## 12. Quick Reference

### Claude Code

```bash
claude                                  # Start interactive session
claude --dangerously-skip-permissions   # Auto-approve all tool calls
claude --worktree <name>                # Parallel work in a git worktree

# In-session commands
/clear                   # Clear context (between unrelated tasks)
/compact                 # Compress context (long sessions)
/model                   # Switch model
/spec-driven-development # Write spec before implementation
/fix-issue <number>      # GitHub issue → fix → PR
/incident-response <desc># Incident triage
/k8s-deploy <service>    # Deploy to K8s
/release <project>       # Cut a release
```

### opencode

```bash
opencode                 # Start TUI
opencode run "task"      # Run with message
opencode debug info      # Check loaded plugins
opencode agent list      # List all agents

# In-session
/start-work              # Prometheus spec-first interview
/hyperplan               # 5 adversarial critics on a plan
ultrawork                # (in any prompt) Full parallel orchestration
```

### Model Selection Guide

| Scenario | Tool | Model |
|---|---|---|
| Architecture / planning | Claude Code | opus[1m] (Opus, 1M context) |
| Code implementation | Claude Code | sonnet / opus[1m] |
| Security/cost review | Claude Code | haiku (advisory agents) |
| Fast codebase search | opencode | nan/qwen3.6 (explore) |
| Orchestration / deep work | opencode | nan/deepseek-v4-flash (sisyphus, deep) |
| Plan review (critical) | opencode | nan/mimo-v2.5 (momus) |
| Zed inline editing | Zed | nan/qwen3.6 (NaN) |

---

## 13. Post-Install Checklist

Copy this list and check off each item:

**System**
- [ ] Homebrew / apt / dnf configured
- [ ] Node 20 on PATH (`node --version` → v20.x.x)
- [ ] Bun installed (`~/.bun/bin/bun`)
- [ ] `gh` authenticated (`gh auth status`)
- [ ] AWS CLI configured
- [ ] gcloud authenticated
- [ ] SSH key added to GitHub (`gh ssh-key list`)

**Claude Code**
- [ ] Installed (`claude --version`)
- [ ] Authenticated (run `claude`)
- [ ] `~/.claude/CLAUDE.md` created
- [ ] `~/.claude/settings.json` created (model `opus[1m]`)
- [ ] `~/.claude/agents/` populated (19 agent files, incl. `doc-reviewer`)
- [ ] `~/.claude/skills/` populated
- [ ] `~/.claude/rules/` created
- [ ] `~/.claude/hooks/auto-sync.sh` created and executable
- [ ] `~/.claude/hooks/engram-sync.sh` + `engram-sync.py` created and executable

**Engram**
- [ ] Installed (`engram --version` → 1.16.x)
- [ ] DB exists at `~/.engram/engram.db`
- [ ] First-time backfill run if Engram already had memories (`~/.claude/hooks/engram-sync.py backfill`)

**Obsidian Vault**
- [ ] `git clone git@github.com:yosoyvilla/obsidian-vault.git ~/Documents/obsidian-vault`
- [ ] Obsidian app installed and vault opened

**opencode**
- [ ] Installed via brew tap (`brew install anomalyco/tap/opencode`)
- [ ] `NAN_API_KEY` set (no OpenCode Zen subscription needed)
- [ ] oh-my-openagent in plugin cache
- [ ] `~/.config/opencode/opencode.jsonc` created (NaN-only, `mcp.engram` enabled)
- [ ] `~/.config/opencode/oh-my-openagent.json` created (NaN-only, hephaestus disabled)
- [ ] `~/.config/opencode/AGENTS.md` (byte-identical to repo `AGENTS.md`)
- [ ] `~/.config/opencode/agents/` populated (critic, fact-checker)
- [ ] `~/.config/opencode/commands/` populated (council, verify, smoke)
- [ ] `~/.config/opencode/tui.json` created (empty plugins)
- [ ] `~/.opencode/opencode.json` created (empty plugins)
- [ ] Verification: `opencode debug info` shows only `oh-my-openagent@latest`

**Zed**
- [ ] Installed
- [ ] `~/.config/zed/settings.json` created (NaN openai_compatible, engram context server)
- [ ] `~/.config/zed/AGENTS.md` (byte-identical to repo `AGENTS.md`)
- [ ] NaN API key set in Zed settings UI (the `nan` provider)
- [ ] Zed skills installed: `ls ~/.agents/skills/` → shows 12 skill folders
- [ ] Skills visible in Zed → Settings → AI → Skills → User tab

**Terminal Tools**
- [ ] `fzf` installed and CTRL-R works in terminal
- [ ] `bat --version` works
- [ ] `rg --version` works
- [ ] `eza --version` works (or at least `ls` alias configured)
- [ ] `zoxide` init in `.zshrc` (`z` command works)
- [ ] `delta` in `~/.gitconfig` (`git diff` shows colored output)

**Environment**
- [ ] `NAN_API_KEY` in `~/.zshrc`
- [ ] NaN API reachable: `curl -H "Authorization: Bearer $NAN_API_KEY" https://api.nan.builders/v1/models`
- [ ] All projects cloned to `~/Documents/`
- [ ] Per-project `.claude/CLAUDE.md` files in place

---

## 14. Troubleshooting

### oh-my-openagent not loading

```bash
ls ~/.cache/opencode/packages/oh-my-openagent@latest/
# If missing, reinstall:
npm install --prefix ~/.cache/opencode/packages/oh-my-openagent@latest \
  --ignore-scripts oh-my-openagent
```

### Stale/unexpected plugin appearing in `opencode debug info`

```bash
cat ~/.opencode/opencode.json
# Must be: {"$schema": "...", "plugin": []}
# opencode reads BOTH ~/.config/opencode/ AND ~/.opencode/
```

### NaN API 401 error in opencode

```bash
echo $NAN_API_KEY          # Must not be empty
source ~/.zshrc             # Or open a new terminal
# Then retry
```

### deepseek-v4-flash / mimo-v2.5 returning null content

These are thinking models — all tokens go to internal reasoning with low `max_tokens`. Use `max_tokens: 500+` for deepseek, `2000+` for mimo.

### Claude Code hooks not running

```bash
ls -la ~/.claude/hooks/auto-sync.sh  # Must be executable
chmod +x ~/.claude/hooks/auto-sync.sh
tail -f ~/.claude/sync.log           # Watch sync activity
```

### macOS Notification hook on Linux

Replace the `osascript` command in `settings.json` Notification hook with:
```bash
notify-send 'Claude Code' 'Needs your attention'
```

Install: `sudo apt install libnotify-bin` (Debian/Ubuntu) or `sudo dnf install libnotify` (Fedora).

### `jq` not found (hooks use it)

```bash
# macOS:
brew install jq
# Debian/Ubuntu:
sudo apt install -y jq
# Fedora:
sudo dnf install -y jq
```

### `rsync` not found (auto-sync hook uses it)

```bash
# macOS: included by default
# Debian/Ubuntu:
sudo apt install -y rsync
# Fedora:
sudo dnf install -y rsync
```
