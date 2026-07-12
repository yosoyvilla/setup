# Agent Workflow Principles

> Obsidian: ~/Documents/obsidian-vault/claude-code/agent-workflows.md
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

## Fix the Workflow, Not the Output
When an agent or skill produces the same bad pattern twice, edit the agent or
skill definition (and sync the vault) instead of hand-fixing instances.
One definition edit fixes the class of error; a hand-fix repairs one instance.

## Trial Run Before Fan-Out
Before any bulk or parallel operation over 3+ similar items (mass edits,
multi-file migrations, parallel agents), run 2-3 representative items first,
review the results, then scale. Never fan out an unproven workflow.
