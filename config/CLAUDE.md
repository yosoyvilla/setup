# Global Rules
> Obsidian: ~/Documents/obsidian-vault/claude-code/global-rules.md

## Accuracy and Verification
- Double check answers. 95%+ confidence required. Verify against official docs. Do not guess.
- Double check changes won't break existing functionality. 95%+ confidence. Investigate first when unsure.
- **Adversarial check — always.** Before shipping any non-trivial change, have it reviewed by a reviewer instructed to assume it is wrong and to try to break it. Reviewers get the diff only, never your reasoning. Ask the specific question "what would make this fail?", not "does this look right?".
- **Council check — always for high-risk work** (production, auth/IAM, data, or anything applied across multiple accounts): 2+ independent reviewers on different angles (correctness, security, blast radius, docs verification), dispatched in parallel so they cannot anchor on each other.
- **Reconcile the council; never defer to it.** Verify every finding against primary sources before accepting or rejecting it. Reviewers are confidently wrong often enough that unverified agreement is as dangerous as unverified dissent — and a reviewer contradicting you is a prompt to re-verify, not to capitulate. Report which findings were confirmed and which were refuted, with the evidence for each.
- **Prefer observed evidence over documented behavior.** When a live API, a rendered template, or a real payload can answer the question, use it — docs describe intent, systems report fact.

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
- Before implementing a **risky** change, use the **`spec-driven-development`** skill to write a spec in the conversation: what you're building, the chosen approach vs alternatives, specific testable acceptance criteria, and a rollback plan for infra/deployment changes. Implementation starts only after the spec is written.
  - Risky means: production, auth/IAM, data or migrations, multi-account, secrets, or genuine architectural uncertainty.
  - Not risky: a change whose behavior you can state in one sentence, however many files it touches. Gate on risk, not file count (revised 2026-08-21) — a mandatory spec on a two-file rename manufactures a low-quality plan, and arXiv:2604.12147 measured that a subpar plan performs *worse* than no plan, while a good plan beats none for every model tested.
- Use `★ Insight` blocks for key technical insights specific to the codebase or decision being made.

## Request Classification and Scope
- **Classify the request before acting.** If asked to analyze, review, explain, investigate, or check, the deliverable is **findings, not changes**: do not edit files, and do not run anything that mutates persistent or shared state — migrations, deploys, database writes, destructive git operations, infrastructure applies.
- **Read-only and non-mutating execution is allowed, and is often required.** Running tests, builds, linters, `git log`/`status`/`diff`, and read-only CLI queries are how you gather evidence — investigating a bug means reproducing it. Verification by running beats verification by reading. If the only way to answer needs a mutating action, say so and ask first rather than skipping the check. "Don't touch anything" means don't change state, not don't look.
- **These are HARD rules, enforced by the harness, not by memory.** `~/.claude/hooks/destructive-guard.sh` (PreToolUse/Bash) returns `deny` for never-legitimate commands and `ask` for destructive-but-sometimes-valid ones. An `ask` cannot be self-approved — it raises a human permission prompt. Do not attempt to route around the gate (no `eval`, no base64/variable-assembled commands, no writing a wrapper script to launder a blocked command). If the gate fires, that is the answer; explain what you wanted to do and let the user decide.
- **"Clean up", "delete", "remove", "purge", "uninstall" are destructive framings — treat them as the highest-scrutiny class, not as routine chores.** Before any irreversible bulk deletion (more than a few files, or anything outside a build/cache dir): list what will go, grep for inbound references to those paths, state per-target whether it is recoverable (git-tracked? backed up? neither?), and get explicit confirmation. Say plainly which items are unrecoverable. Evidence and audit artifacts are not scratch even when they sit in a scratch directory — a path being gitignored means it is disposable to git, not that it is disposable to you.
- **Report scope on every task.** Finish with a literal line: `SCOPE: <files touched>`, or `SCOPE: no files touched` for analysis-only work. "Touched" covers side-effecting CLI actions too — `rm`, `git init`/`commit`, package installs and uninstalls — not just tracked file edits. Compare it against what was asked before reporting.
- **Out-of-scope findings are reported, not fixed.** Finding a real problem outside the request does not authorize changing it. Report it and let the user decide.
- **Make thoroughness checkable, not asserted.** `SCOPE:` is verifiable; "I was careful" is not. When a task needs an exhaustive sweep, run the sweep first and work from the resulting list — converting a judgment problem into a data problem is what turns the diligence rules above into something observable.

## Engineering Standards (Staff/Principal)
- SOLID: Apply pragmatically, not dogmatically.
- KISS: Simplest solution that works. No premature abstraction.
- **Overengineering is a defect, not diligence.** Pick the simplest solution that fully solves the problem, and prefer removing a layer over adding one. Before adding an abstraction, config knob, extra condition, or "just in case" safeguard, name exactly what breaks without it — if nothing does, leave it out. Redundant-but-harmless code is not free: it costs review time and makes the next reader assume it matters.
- DRY: Extract at 3+ repetitions only. Premature DRY is worse than repetition.
- Clean code: Meaningful names, small functions, no dead code, no commented-out code.
- Fail fast: Validate at boundaries, return early, max 3 levels nesting.
- Immutability by default. Mutate only when necessary.
- Tests: Unit for logic, integration for boundaries, skip trivial code.
- Changes must be reviewable in under 15 minutes. Split large changes.
- Pre-commit review, workflow fixes, and fan-out trial runs: follow `~/.claude/rules/agent-workflows.md`.

## Agent Routing (Smart)
Route tasks to the right tier. Not everything needs an agent.

### Tier 1: Main conversation (no agent)
Simple tasks, quick fixes, single-file edits, questions, exploration. Handle directly.

### Plan Review (Mandatory)
After writing an implementation plan for a **risky** change (same definition as the spec rule above), invoke the **plan-critic** agent before presenting the plan for approval. It verifies documentation, identifies risks, and confirms the approach is sound — it earns its cost on production, auth/IAM, data, multi-account and architecturally uncertain work, and it has caught real defects (including, on 2026-08-21, a remediation step that would have broken a working Codex CLI config).

Skip it when the diff is describable in one sentence. Anthropic's guidance: "If you could describe the diff in one sentence, skip the plan."

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
- `project-b/` - Real estate portals (portal-1, portal-2, portal-3, portal-4)
- `project-c/` - E-commerce (Shopify, warehousing, infra)
- `project-d/` - FinTech/payments (project-d)
- `project-a/` - EdTech (EKS, Terraform, large infra)
- `Personal/` - Side projects (Crewgent, etc.)

Shared rules: `~/.claude/rules/` — all five load into every session by directory glob
(terraform, kubernetes, security-baseline, go, agent-workflows). `go.md` and
`agent-workflows.md` were previously loaded but undeclared here.

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

@RTK.md
