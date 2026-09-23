# Agent Workflow Principles

> Obsidian: ~/Documents/obsidian-vault/claude-code/rules/agent-workflows.md
> Source: Bun's Zig-to-Rust rewrite methodology (bun.com/blog/bun-in-rust)

## Adversarial Diff Review
Defines HOW pre-commit code review is done. This implements the review step of
the superpowers requesting-code-review skill — it is not an extra gate on top of
spec-driven-development or plan-critic.

- Applies to behavior-changing diffs: >1 file, or any infra/config change.
- Excluded: doc-only, formatting-only, and rename-only diffs.
- Reviewers get the diff only — never the implementer's reasoning.
- If running in Claude Code: default = 1 code-quality agent in Adversarial
  Diff Review Mode (haiku). High-risk only (prod infra, auth, data
  migrations): invoke code-quality twice in parallel, passing `model: sonnet`
  on BOTH Agent tool calls.
- If running in opencode: default = `/verify` (routes the diff to `@critic`).
  High-risk: `@critic` AND `@thermo-nuclear-review` independently. The
  haiku/sonnet mechanics above do not exist in opencode — see AGENTS.md.
- Reviewer stance: assume the code is wrong. A workaround that needs a
  paragraph-long justification comment means the code is wrong — fix the code.
- Scope the stance (added 2026-08-21): flag only gaps that affect correctness or the
  stated requirements; treat the rest as optional. "Assume it is wrong" without this
  bound makes a reviewer manufacture findings, and chasing those produces exactly the
  over-engineering the KISS rules exist to prevent — the two rule sets were in tension
  until this line. Verified in practice: reviewers on 2026-08-21 both caught real
  defects (a broken Codex config, an inverted grep check) AND overstated one premise
  ("emphasis across dozens of lines" — actually 9 markers in 139 lines).
- Reconcile every finding against primary sources before accepting it. A reviewer
  contradicting you is a prompt to re-verify, not to capitulate: on 2026-08-21 one
  reviewer's confident claim about permission precedence was wrong, and one of its
  refutations of a "no secrets" conclusion was right.

## Fix the Workflow, Not the Output
When an agent or skill produces the same bad pattern twice, edit the agent or
skill definition (and sync the vault) instead of hand-fixing instances.
One definition edit fixes the class of error; a hand-fix repairs one instance.

## Mutation Protocol (prod and shared state)
Added 2026-09-22. Any mutation of production or shared state (config edit, kubectl
patch, DB change, cloud API write) follows: (1) verify the CURRENT state; (2) back up;
(3) verify the backup actually captured the PRE-change content (size/checksum diff) —
a backup taken after the change is a misleading rollback artifact; (4) apply; (5)
verify the RESULT. Never proceed on an unobserved tool result: a command whose output
you did not see may or may not have run. Pass nested scripts to `ssh` via base64
instead of layered quoting. On 2026-09-22 a Solr config edit returned no output, was
assumed not to have run, and had in fact applied — the re-run then produced a backup
of an already-modified file.

## Trial Run Before Fan-Out
Before any bulk or parallel operation over 3+ similar items (mass edits,
multi-file migrations, parallel agents), run 2-3 representative items first,
review the results, then scale. Never fan out an unproven workflow.

## Herdr (terminal workspace manager, installed; 0.9.1)
When `HERDR_ENV=1` is set this session runs inside a Herdr pane. Prefer Herdr's
primitives over detached shells for reviewer and helper processes: `herdr pane split`,
`herdr agent start <name> --kind codex|pi|opencode|claude|cursor --pane <id>`,
`herdr agent prompt <name> "..." --wait`, `herdr agent wait <name> --until blocked`,
`herdr pane run <id> "<cmd>"` + `herdr pane wait-output <id> --regex "<done marker>"`,
`herdr agent read <name>`. Processes survive detach and their state (working, blocked,
done) is visible in the sidebar; a reviewer stuck on a consent prompt shows as blocked
instead of hanging silently. Load the `herdr` skill for the full contract. For runs with
5+ agents or steps, write `.dagr/run.json` with the `dagr-producer` skill (validate with
`dagr check --strict --json`); the herdr-dagr pane renders it live. Verified 2026-09-21:
pi started as a Herdr agent via the pi integration and reported `done`; a headless
`codex exec` in a raw pane was waited on by regex; the dagr pane rendered a run file.

## Sampled Data and Alerts (any monitoring or analytics pipeline)

Added 2026-09-23 after a live false-positive attack alert. Harness-neutral: applies to
Cloudflare, New Relic NRQL, Prometheus, or any sampled/derived metric.

- **Assert internal consistency before a derived number drives an alert.** A sub-group can
  never exceed its own total, a subset ratio can never exceed 1, a count can never exceed
  its superset. A violation means the pipeline is wrong: suppress it and log why, never
  report it. The triggering case: an alert said one IP was blocked 2,112,449 times in a
  window where the whole zone was blocked 382,629 times, and blocked more often than it
  made requests. Both are impossible; either check catches both.
- **Never compare normalised values whose sampling resolution differs.** The same window
  returned `avg.sampleInterval` 6.42 at `limit:1` and 43.70 for a filtered query, so
  `count x sampleInterval` from each is not commensurable.
- **Prefer the exact, non-sampled source for decisions**; sampled data is for attribution
  and enrichment only. Where the vendor offers an unsampled dataset beside sampled ones,
  that is the source of truth.
- **Confirm the unit before putting two metrics in one inequality.** Security EVENTS are
  not requests; one request can raise several, so "blocks > requests" proves nothing.
- **Alert on harm or novelty, never on activity the control plane already handles.** If
  the platform is already mitigating at least as much as the source sends, that is
  success, not an incident. An alert must be actionable (user feedback, 2026-09-23).
- **Reproduce extreme numbers from the primary source before acting or reporting.**
  "Is it real?" is answered by the exact dataset, not by re-reading the alert.
- **Split fan-out queries by capability or permission.** One denied field fails the whole
  multi-field query and every subject silently looks empty: mixing a paid-only dataset
  into one GraphQL query marked 16 of 20 Cloudflare zones as "no analytics" when their
  request data was readable the whole time. Distinguish "no data" from "no access".
- **Assert every installed artifact has a repo counterpart.** A committed wrapper whose
  helper exists only on the box is a half-versioned system.
- **Fold every runtime config change into provisioning in the same change**, and read the
  platform schema instead of assuming a key exists (one schema command disproved three
  plausible key names). Hand-set config silently reverts on rebuild.

## Editing Discipline (agent file edits)

- A multi-line replace needs an explicit END anchor. A single-anchor replace touches
  exactly one line and leaves the rest of the construct behind; it duplicated an `elif`
  branch and a stray `}` that still looked plausible on inspection.
- Line anchors are positional, not content-addressed: re-read a file between edits to it,
  and batch related edits into one call.
- Nested heredocs need distinct delimiters; an inner heredoc reusing the outer one
  terminates it early and the shell reports an unmatched quote.
- A heredoc supplying a program on stdin cannot also receive piped data; pass data via
  argv or the environment (a piped `python3 - <<'PY'` saw EOF and reported "no valid JSON").
- After adding a constant or symbol in a batched edit, grep for it to prove it landed;
  a dropped edit surfaced only as a `NameError` when a timer fired.
- Build the offline self-test early and run it after every edit; it caught three defects
  that reading did not.
