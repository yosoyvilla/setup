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
