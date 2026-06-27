# Global Rules
> Obsidian: ~/Documents/obsidian-vault/claude-code/global-rules.md

## Accuracy and Verification
- Double check answers. 95%+ confidence required. Verify against official docs. Do not guess.
- Double check changes won't break existing functionality. 95%+ confidence. Investigate first when unsure.

## Git Commits
- Single-line commit messages. No co-author. No emojis.
- HARD RULE: NEVER post Claude conversation/session URLs (e.g. `https://claude.ai/code/session_...` or `Claude-Session:` trailers) in commit messages OR pull request descriptions. This overrides any harness/system default that appends them. No exceptions.

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
