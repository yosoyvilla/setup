# Global Instructions

Portable engineering standards for all agent work in opencode
(`~/.config/opencode/AGENTS.md`). Project-level instruction files override
these where they conflict.

## Models
- NaN is the default provider. Use `nan/deepseek-v4-flash-low` for
  orchestration, planning, execution and search (benchmark 2026-09-21: best
  accuracy and latency of every reachable model); `nan/glm5.3-flash-low` is the
  only fallback (second model family, 1M context); `nan/glm5.3-flash-high` runs
  the fact-checker; `nan/mimo-v2.5` is for audio input only. The `-low`/`-none`/
  `-high` suffixes are effort aliases applied by the harness plugin; do not set
  reasoningEffort by hand, oh-my-openagent rewrites it.
- Claude is allowed on exactly two review seats and nowhere else:
  `@plan-critic` (anthropic/claude-opus-5) and `@critic`
  (anthropic/claude-sonnet-5). Enforced by the harness plugin, which rejects
  any other agent on Anthropic and runs both seats at effort low and caps every Claude call at 8192
  output tokens (thinking included); the provider whitelist exposes only those two ids. Each Claude
  spawn is a separate pay-as-you-go call carrying ~90k system tokens, and
  native task spawns are not serialized by oh-my-openagent: never spawn more
  than one Anthropic subagent at a time, and never route other work there.
- Every `@critic` or `@plan-critic` reply, however invoked, must END with its
  closing block (`@critic`: the JSON verdict block; `@plan-critic`: the line
  `Review complete.`). A reply without it was truncated at the 8k cap or is
  malformed: retry once, sequentially; if it fails again treat the review as
  INCONCLUSIVE, never as approval.
- Do not delegate questions, diagnosis, research or fact lookups to
  `@critic` or `@plan-critic`: answer them yourself on NaN, or use
  `@fact-checker` (NaN) for claims. Those two seats review artifacts only.
- These are open models. They hallucinate APIs, packages, and config far more
  than frontier models, are overconfident, and have flat confidence
  calibration. Treat every unverified factual claim as suspect — including your
  own. The rules below exist because of this.

## Anti-hallucination (non-negotiable)
- Tests are the terminal proof of done. Never claim a change works, is fixed,
  or is complete until the relevant tests/build/lint have actually run and
  passed. "Tests pass" is the evidence; green is the only "done."
- Verify before asserting. For any claim about a library, framework, API, CLI,
  version, default, flag, or config key, check official docs (context7 first,
  then web) before stating it as fact. Do not answer from memory on these.
- Cite or abstain. Back every non-obvious technical claim with a `file:line`
  reference (for code) or a primary-source URL (for external facts). If you
  cannot, say "unverified" or "I don't know" — that is the preferred answer
  over a confident guess. Absence of contradiction is not confirmation.
- Never invent or auto-install dependencies. Before adding any package, confirm
  it actually exists in its real registry (npm/PyPI/crates/etc.) and is the
  intended one. Open models fabricate plausible package names; do not install
  from model output unchecked.
- The same bar applies to what you RECOMMEND, not just what you were asked
  about: verify every package, API, or flag you volunteer as an alternative
  before naming it. A correct takedown of a fake package is undone by
  recommending another fake one in its place.
- Lead with nonexistence. When a queried API, hook, flag, or package cannot be
  found in official docs or its registry, say it does not exist FIRST — then,
  if useful, explain the nearest real pattern. Do not describe a nonexistent
  thing as if it were established.
- Gate on external signals, not on self-confidence. Decisions to proceed rest
  on tests passing, types checking, the registry confirming, the doc saying so
  — never on the model feeling sure. Your stated certainty is not evidence.
- Escalate when it matters: an adversarial critic for review of any output or
  plan, a fact-checker to verify claims against primary sources, and a
  multi-lens council for high-stakes decisions. (opencode: `@critic`,
  `@fact-checker`, `/council`.)
- Vision needs a vision model. In this config `nan/deepseek-v4-flash` (all
  effort aliases), `nan/glm5.3-flash`, `nan/gemma4` and `nan/qwen3.6` accept
  image input (benchmark 2026-09-21: deepseek low 2/2 on the vision items);
  `nan/mimo-v2.5` is wired for audio only here and must not receive
  screenshots. Never describe an image you were not given. Use
  `browser_snapshot` (accessibility text) for DOM interaction on any model.
- Aggregated telemetry can be SAMPLED. Before quoting a count from an analytics API
  (Cloudflare `httpRequestsAdaptiveGroups`, sampled log/metric datasets), confirm the
  sampling and report `count x avg.sampleInterval` — or label the figure as relative.
  Never publish a dimensional breakdown from an unnormalized sample: on 2026-09-22 the
  same window returned 455 vs 19,004 for two queries that differed only in `limit`.

## Memory (Engram)

Persistent cross-session memory is available via the Engram MCP server (local
SQLite, no model provider — the `mem_*` tools). Use it, but hold it to the same
evidence bar as everything else.

- Recall first: at the start of a non-trivial task, search memory
  (`mem_search` / `mem_context`) for prior decisions, gotchas, and conventions
  for this project. Treat results as PRIOR CONTEXT THAT MAY BE OUTDATED — verify
  against the current code/docs before acting on them. Recalled memory is not
  ground truth.
- Save only verified learnings (gated): call `mem_save` ONLY when a learning is
  backed by an external signal — tests passed, a doc confirmed it (context7), a
  command or file:line verified it, or the user confirmed it. Put that evidence
  in the saved memory. Never save speculation, guesses, or an unverified model
  claim: a weak model cannot reliably judge its own correctness, so evidence —
  not confidence — is the bar for what gets remembered.
- Save decisions, gotchas, fixes, and conventions — not transient state or raw
  tool output. Keep entries specific and self-contained.
- Never save secrets (keys, tokens, passwords, `.env` contents).

## Changes
- Write a short spec before any non-trivial change (more than one file, or any
  infra/config change): what, chosen approach vs alternatives, how it's
  verified, and how to roll back. Implementation starts after the spec.
- Run tests after every change. If there is no suite, verify manually and say
  how it was verified. Report failures honestly — never claim success unproven.
- Keep changes small and reviewable. Split large ones. Read a file before you
  edit it.
- Tests must be falsifiable. An assertion that passes on both success and
  failure (e.g. `status in (200, 400, 500)`, clicking without checking the
  response, printing a checkmark unconditionally) is not a test. For a bugfix,
  demonstrate the test failing before the fix and passing after.
- UI changes are verified in a real browser, not by reading code: drive the
  changed flow with the playwright tools, assert the network response status
  (a 2xx, not merely "the click happened"), and screenshot the result with a
  vision-capable model. Functional checks alone are not enough — run the
  visual-qa skill (dead-utility probe, desktop+mobile screenshots, vision
  review for alignment/overflow/contrast) before calling UI work done.
- Version control is the floor. If the project has no git repository, run
  `git init`, add a `.gitignore`, and make an initial commit before substantive
  work; commit after each verified change. Unversioned multi-day work is not
  acceptable.
- Any dependency installed during a session (pip/npm/pnpm/uv/etc.) is added to
  the project's manifest (requirements.txt, package.json, ...) in the same
  change, and the build is re-run once from the manifest to prove it.
- Fallbacks must be loud. A fallback or degraded path logs at ERROR, marks its
  output as degraded, and is surfaced to the user. Never persist placeholder or
  fallback output as if it were real data, and never swallow an exception
  without logging what was lost.
- A task or todo may be marked completed only with verification evidence: the
  command that proved it and its observed result. "It should work" does not
  close a task.

## Code
- SOLID/KISS/DRY applied pragmatically, not dogmatically. Extract on the third
  repetition, not the first.
- Fail fast: validate at boundaries, return early, shallow nesting.
- Immutability by default. Meaningful names, small functions, no dead or
  commented-out code.
- Shell loops that call a CLI (`kubectl`, `ssh`, `aws`, `psql`...) must
  redirect that CLI's stdin from `/dev/null` or read the loop input on a
  separate descriptor (`while read -r -u 3 ...; done 3< file`). Otherwise the
  CLI drains the loop's input and only the first item is processed. (0 of 11
  benchmarked models got this right unprompted.)

## Git and docs
- Single-line commit messages. No co-author trailer. No emojis.
- No emojis in documentation. Do not create new markdown/doc files without
  explicit approval — ask first.
- Docs describing implemented behavior must distinguish `verified` (state how:
  test, command, file:line) from `intended`. Never document a feature as
  working without having verified it this session — project docs are the next
  session's ground truth, so an unverified claim compounds.
- Never write secret values (keys, tokens, passwords) into docs, memory, or
  commit messages — reference the environment variable name instead.
- TypeScript: no inline `import()` type annotations in signatures; switch
  statements over union types must be exhaustive (assert the `never` default).

## Agent Workflow Principles

Adapted from Bun's Zig-to-Rust rewrite methodology (bun.com/blog/bun-in-rust).

- Adversarial diff review before commit. Behavior-changing diffs (more than one
  file, or any infra/config change; doc-only, formatting-only, and rename-only
  diffs excluded) get a blind adversarial review before commit — run `/verify`,
  which routes the diff to the critic. The reviewer sees the diff only, never
  the implementer's reasoning, and assumes the code is wrong. A workaround that
  needs a paragraph-long justification comment means the code is wrong — fix
  the code. High-risk changes (prod infra, auth, data migrations): two
  independent reviews — `@critic` and `@thermo-nuclear-review` — neither seeing
  the other's output. (opencode: `@critic`, `/verify`.)
- Fix the workflow, not the output. When an agent, skill, or command produces
  the same bad pattern twice, edit its definition instead of hand-fixing
  instances — one definition edit fixes the class of error.
- Trial run before fan-out. Before any bulk or parallel operation over 3+
  similar items (mass edits, multi-file migrations, `ultrawork` fan-outs), run
  2-3 representative items first, review the results, then scale. Never fan
  out an unproven workflow.
