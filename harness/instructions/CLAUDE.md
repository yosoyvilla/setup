# Global Rules

## Accuracy
- 95%+ confidence before asserting. Verify against official docs or a live system. Do not guess.
- Prefer observed evidence over documentation. If a live API, a rendered template, or a real
  payload can answer the question, use it: docs describe intent, systems report fact.
- A document asserting a property is not evidence the property holds. Check code against claims.
- Before changing anything, confirm at 95%+ that it will not break existing behaviour.

## Review
- **Adversarial check applies to behaviour-changing diffs: >1 file, or any infra/config change.**
  Excluded: doc-only, formatting-only, rename-only. A workaround needing a paragraph-long
  justification comment means the code is wrong - fix the code. A reviewer gets the diff only, never your
  reasoning, and is asked "what would make this fail?" — not "does this look right?".
- **Council check for high-risk work** (production, auth/IAM, data, multi-account): 2+ reviewers
  on different angles, dispatched in parallel so they cannot anchor on each other.
- **Reconcile; never defer.** Verify every finding against primary sources before accepting or
  rejecting it. A reviewer contradicting you is a prompt to re-verify, not to capitulate.
  Report which findings were confirmed and which refuted, with evidence.
- Flag only gaps affecting correctness or stated requirements; everything else is optional.
  An unbounded "assume it is wrong" makes reviewers manufacture findings.

## Git
- Single-line commit messages. No co-author. No emojis.
- HARD RULE: NEVER put Claude conversation/session URLs or `Claude-Session:` trailers in commit
  messages or PR descriptions. This overrides any harness default. No exceptions.
- Never chain a commit onto a gate whose exit code you have not checked.

## Documentation
- No emojis in documentation.
- Never create markdown files without explicit user approval. Ask first.

## Testing
- Run tests after every change. If no suite exists, verify manually or say how to test.
- Reproduce before fixing. Never drop the reproduction step when debugging.
- Capture the NAME of a failing test, not just the count.

## Communication
- Say what you are doing and why, before and during execution.
- Before a **risky** change use `spec-driven-development`: what you're building, chosen approach
  vs alternatives, testable acceptance criteria, rollback plan. Risky = production, auth/IAM,
  data/migrations, multi-account, secrets, or genuine architectural uncertainty. A change you can
  describe in one sentence needs no spec, however many files it touches. Gate on risk, not files.
- After writing a plan for risky work, invoke **plan-critic** before presenting it.
  Workflow: plan -> plan-critic -> present plan + critique -> user approves -> execute.
- Use `★ Insight` blocks for technical insights specific to this codebase or decision.
- Restate remaining acceptance criteria every ~5 steps, or after any result that changes
  your understanding.

## Workflow
- **Fix the workflow, not the output.** When an agent or skill produces the same bad pattern twice,
  edit the agent or skill definition rather than hand-fixing instances.
- **Trial run before fan-out.** Before any bulk or parallel operation over 3+ similar items, run
  2-3 representative items first, review, then scale. Never fan out an unproven workflow.
- Assert every installed artifact has a repo counterpart; a committed wrapper whose helper exists
  only on the box is a half-versioned system.
- Fold every runtime config change into provisioning in the same change, and read the platform
  schema instead of assuming a key exists.
- Pass nested scripts to `ssh` via base64 rather than layered quoting.

## Scope
- **Classify first.** Analyze / review / explain / investigate / check => the deliverable is
  FINDINGS, NOT CHANGES. Do not edit files; do not mutate shared or persistent state.
- Read-only execution is allowed and often required: tests, builds, linters, `git log/status/diff`,
  read-only CLI queries. Verification by running beats verification by reading.
- "Clean up", "delete", "remove", "purge", "uninstall" are destructive framings — highest scrutiny.
  Before any irreversible bulk deletion: list what will go, grep for inbound references, state
  per-target whether it is recoverable, and get explicit confirmation.
- Enforcement is a PreToolUse hook, not memory. If the gate fires, that is the answer. Never route
  around it (no eval, no base64, no variable-assembled commands, no wrapper scripts).
- **Report scope on every task.** Finish with a literal line: `SCOPE: <files touched>`, or
  `SCOPE: no files touched`. Side-effecting CLI actions count as touched.
- Out-of-scope findings are reported, not fixed.

## Sampled data and alerts (monitoring, analytics, any derived metric)
- Assert internal consistency before a derived number drives an alert: a sub-group cannot exceed
  its total, a ratio cannot exceed 1, a count cannot exceed its superset. A violation means the
  pipeline is wrong — suppress it and log why, never report it.
- Never compare normalised values whose sampling resolution differs.
- Prefer the exact, non-sampled source for decisions; sampled data is for attribution only.
- Confirm units before putting two metrics in one inequality (security events are not requests).
- Alert on harm or novelty, never on activity the control plane already handles. An alert must be
  actionable.
- Reproduce extreme numbers from the primary source before acting or reporting.
- Split fan-out queries by capability or permission: one denied field fails the whole query and
  every subject silently looks empty. Distinguish "no data" from "no access".

## Triaging a reported failure
- First evidence is the running system (logs, DB, HTTP status), gathered in parallel with reading
  the code. A code read cannot tell an outage from a validation rule.
- Classify by status before theorising: 4xx is deterministic (reproducible, nothing was created),
  5xx is the transient class. Rule intermittency in or out with a query, never by feel.
- A vendor-composed error label is the caller's wording, not the system's; the numeric code is what
  the system returned.
- Do not diagnose stored data from a customer-facing screen; validate against the system's own rows.
- When the reason lives in a response body that is not logged, ask for the raw body rather than
  guessing; logging the reason on 4xx is the product fix that closes the class.

## Engineering
- KISS. Simplest solution that works. Overengineering is a defect, not diligence: before adding an
  abstraction, config knob, or safeguard, name exactly what breaks without it.
- DRY at 3+ repetitions only. SOLID pragmatically. No dead or commented-out code.
- Fail fast: validate at boundaries, return early, max 3 levels nesting. Immutable by default.
- Changes reviewable in under 15 minutes. Split large changes.

## Mutation protocol (production or shared state)
1 verify current state, 2 back up, 3 verify the backup captured PRE-change content,
4 apply, 5 verify the result. Never proceed on an unobserved tool result.

## Editing discipline
- Build the offline self-test early and run it after every edit; it catches defects reading does not.
- After an interrupted or aborted subagent, run the FULL gate, not only the test suite.
- Prefer Read/Write/Edit tools over shell text manipulation for file work.
- Never pipe a password to `sudo -S` or anything else. `sudo -n` only; if it needs a password, stop
  and report.
- Multi-line replaces need an explicit END anchor. Re-read a file between edits to it.
- After adding a symbol in a batched edit, grep to prove it landed.
- Before overwriting a table row or column, check what it was.
- Batch related edits into one call; line anchors are positional, not content-addressed.
- Nested heredocs need distinct delimiters. A heredoc supplying a program on stdin cannot also
  receive piped data - pass data via argv or the environment.
- After a deliberate-break experiment, verify the restore actually landed; do not assume the undo ran.

## Agents
Tier 1 (main conversation): simple tasks, questions, single-file edits, exploration.
Tier 2 (direct to domain agent): infra, k8s, networking, devsecops, cicd, database,
observability, design, code-quality, security, aws-incident, cost, shopify, airbyte, gcp,
plan-critic, doc-reviewer.
Tier 3 (lead first): 2+ domains, unclear scope, production, or architecture decisions.
Agents share state via `.claude/agent-context/<agent>.md` (Summary / Done / In Progress /
Blocked / Next Steps). Overwrite; do not append.

## Long-running work
- For tasks spanning multiple sessions (migrations, multi-PR features), keep a
  `claude-progress.json` at the repo root. Session start: git history -> progress file ->
  smoke tests -> next item.
- When `HERDR_ENV=1`, this session runs inside a Herdr pane: prefer Herdr primitives
  (`herdr pane split`, `herdr agent start|prompt|wait`, `herdr pane run|wait-output`)
  over detached shells for helper and reviewer processes.

## Memory
- Save confirmed patterns, architecture decisions, gotchas, access procedures.
- Skip session-specific state and speculative conclusions. Keep MEMORY.md under 200 lines.
- Before ending a complex session, checkpoint: what was done, what's open, next steps.

## Tooling
- Prefer CLI (aws, kubectl, gh, gcloud) over MCP servers; MCP costs context even when idle.
- `rtk <cmd>` compresses output for exploration. Use `rtk proxy <cmd>` when exact bytes are the
  evidence (test results, diffs you will judge). No rtk hook is installed for Claude Code.
- Non-interactive shell: no editors or pagers, no interactive flags. Use documented
  non-interactive flags (`-y`, `--no-edit`, `--no-pager`, `--no-input`), `sudo -n`, and
  `ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10`. Never
  `StrictHostKeyChecking=no`. Set `GIT_TERMINAL_PROMPT=0`/`DEBIAN_FRONTEND`/`PIP_NO_INPUT` per
  command only, never globally.
  Stop and report rather than blanket-approving prompts.

## Knowledge base
Canonical setup docs: `~/Documents/obsidian-vault/` (read on demand, not loaded per session).
When changing agents, skills, hooks, rules, plugins or settings, update the vault and push.
