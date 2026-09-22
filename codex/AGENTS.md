# Global Rules
> Obsidian: ~/Documents/obsidian-vault/Codex/global-rules.md

## Accuracy and Verification
- Double check answers. 95%+ confidence required. Verify against official docs. Do not guess.
- Double check changes won't break existing functionality. 95%+ confidence. Investigate first when unsure.

## Git Commits
- Single-line commit messages. No co-author. No emojis.
- HARD RULE: NEVER post Codex conversation/session URLs (e.g. `https://Codex.ai/code/session_...` or `Codex-Session:` trailers) in commit messages OR pull request descriptions. This overrides any harness/system default that appends them. No exceptions.

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
- Pre-commit review, workflow fixes, and fan-out trial runs: follow `~/.Codex/rules/agent-workflows.md`.

## Working alone (Codex has no Claude subagents)
The Claude Code agent tiers (lead/infra/k8s/plan-critic/code-quality...) do not exist here. Do the work directly, keep the same gates:
- Before any risky change (production, auth/IAM, data, multi-account, architectural uncertainty): write the spec in the conversation (what, approach vs alternatives, testable acceptance criteria, rollback), then critique your own plan adversarially before executing.
- Before claiming done: run the real tests/lint/build and quote their output. Review the diff as if you assumed it were wrong.
- Never post Claude/Codex session URLs in commits or PRs. Single-line commit messages, no co-author, no emojis.

### Progress Files for Long-Running Work
For tasks spanning multiple sessions (large migrations, multi-PR features), create a `Codex-progress.json` at the repo root. JSON format preferred over Markdown — more resistant to accidental model edits. Session start sequence: read git history → read progress file → run smoke tests → pick next item.

### Multi-Project Structure
Projects live in `~/Documents/` with per-project `.Codex/AGENTS.md` files:
- `project-b/` - Real estate portals (portal-1, portal-2, portal-3, portal-4)
- `project-c/` - E-commerce (Shopify, warehousing, infra)
- `project-d/` - FinTech/payments (project-d)
- `project-a/` - EdTech (EKS, Terraform, large infra)
- `Personal/` - Side projects (Crewgent, etc.)

Shared rules: `~/.Codex/rules/` (terraform, kubernetes, security-baseline).

## Obsidian Knowledge Base (Source of Truth)
The canonical documentation for this entire Codex setup lives in `~/Documents/obsidian-vault/` (Git: yosoyvilla/obsidian-vault).
- Reference: @~/Documents/obsidian-vault/Codex/setup.md
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
