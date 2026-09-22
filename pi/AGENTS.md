# Global Instructions

Portable engineering standards for all agent work in pi
(`~/.pi/agent/AGENTS.md`). Project-level instruction files override these
where they conflict. gentle-pi supplies the orchestration workflow (ODD, optional
SDD, native review); these rules sit underneath it.

## Models
- NaN is the default provider. Use `nan/deepseek-v4-flash` at thinking `low`
  for orchestration, planning, execution and search (benchmark 2026-09-21: best
  accuracy and latency of every reachable model); `nan/glm5.3-flash` is the
  only fallback (second model family, 1M context) and runs the second judge at
  thinking `high`; `nan/mimo-v2.5` is for images only (pi cannot pass audio).
  Thinking levels map directly to NaN `reasoning_effort` via `models.json`; do
  not raise them above `low` for routine work.
- Claude is allowed on exactly four review seats and nowhere else: the
  gentle-pi review lenses `review-risk`, `review-reliability`,
  `review-resilience` and `review-readability` on `anthropic/claude-sonnet-5`
  at thinking `low`. Every Claude model is capped at 8192 output tokens
  (thinking included) in `models.json`; only `claude-sonnet-5` and
  `claude-opus-5` are enabled. Never switch the orchestrator or a worker to
  Anthropic: the harness-guards extension switches any non-review session back
  to the NaN default before the request is sent. One Claude review at a time:
  capture lenses one slot at a time with `gentle_review_capture`;
  `gentle_review_capture_group` is blocked because it runs every lens
  concurrently.
- Do not delegate questions, diagnosis, research or fact lookups to a review
  seat: answer them yourself on NaN. Review seats review artifacts only.
- These are open models. They hallucinate APIs, packages, and config far more
  than frontier models, are overconfident, and have flat confidence
  calibration. Treat every unverified factual claim as suspect, including your
  own. The rules below exist because of this.

## Language
- Answer in the language the user's message is written in. Prompts written in
  English get English answers, even when a persona or workflow text mentions
  Spanish. Never switch language mid-task.

## Anti-hallucination (non-negotiable)
- Tests are the terminal proof of done. Never claim a change works, is fixed,
  or is complete until the relevant tests/build/lint have actually run and
  passed. Green is the only "done."
- Verify before asserting. For any claim about a library, framework, API, CLI,
  version, default, flag, or config key, check official docs (context7 first,
  then web) before stating it as fact. Do not answer from memory on these.
- Cite or abstain. Back every non-obvious technical claim with a `file:line`
  reference (for code) or a primary-source URL (for external facts). If you
  cannot, say "unverified" or "I don't know". Absence of contradiction is not
  confirmation.
- Never invent or auto-install dependencies. Before adding any package, confirm
  it exists in its real registry and is the intended one. The same bar applies
  to what you recommend as an alternative.
- Lead with nonexistence. When a queried API, hook, flag, or package cannot be
  found in official docs or its registry, say it does not exist first.
- Gate on external signals, not on self-confidence: tests passing, types
  checking, the registry confirming, the doc saying so.
- Escalate when it matters: gentle-pi's native review (`/gentle:review-mode`,
  `gentle_review`) for any output or plan that touches production, auth, data
  or multiple accounts; the review lenses are the adversarial critics.
- Vision needs a vision model. For screenshots or any visual verification use
  `nan/mimo-v2.5`, `nan/gemma4` or `nan/qwen3.6`; `nan/deepseek-v4-flash` will
  fabricate image descriptions.

## Memory (Engram)
Persistent cross-session memory is available through Engram (`mem_*` tools when
loaded). Recall first for non-trivial tasks and treat results as prior context
that may be outdated. Save only learnings backed by an external signal (test
passed, doc confirmed, command or file:line verified, user confirmed) and put
that evidence in the entry. Never save secrets.

## Changes
- Write a short spec before any non-trivial change (more than one file, or any
  infra/config change): what, chosen approach vs alternatives, how it is
  verified, how to roll back. Implementation starts after the spec.
- Run tests after every change. If there is no suite, verify manually and say
  how. Report failures honestly.
- Keep changes small and reviewable. Read a file before you edit it.
- Tests must be falsifiable: an assertion that passes on both success and
  failure is not a test. For a bugfix, show the test failing before the fix.
- UI changes are verified in a real browser with a vision-capable model, not by
  reading code.
- Version control is the floor: no git repository means `git init`, a
  `.gitignore` and an initial commit before substantive work.
- Any dependency installed during a session is added to the project manifest in
  the same change and the build re-run from the manifest.
- Fallbacks must be loud: log at ERROR, mark output degraded, never persist
  placeholder output as real data.
- A task is completed only with verification evidence: the command that proved
  it and its observed result.

## Code
- SOLID/KISS/DRY applied pragmatically. Extract on the third repetition.
- Fail fast: validate at boundaries, return early, shallow nesting.
- Immutability by default. Meaningful names, small functions, no dead code.
- Shell loops that call a CLI (`kubectl`, `ssh`, `aws`, `psql`...) must
  redirect that CLI's stdin from `/dev/null` or read the loop input on a
  separate descriptor (`while read -r -u 3 ...; done 3< file`). Otherwise the
  CLI drains the loop's input and only the first item is processed.
- The harness-guards extension blocks catastrophic commands (recursive delete of
  `/` or the home directory, force push, `git reset --hard`, `git clean -fd`,
  `terraform destroy`, `kubectl delete namespace`) and writes to secret/state
  files (`.env`, `*.tfstate`, `*.pem`, `*.key`, `id_rsa*`, `secrets/`). A
  blocked call is the answer: report it, do not work around it.

## Git and docs
- Single-line commit messages. No co-author trailer. No emojis.
- No emojis in documentation. Do not create new markdown/doc files without
  explicit approval.
- Docs describing implemented behavior must distinguish `verified` (state how)
  from `intended`.
- Never write secret values into docs, memory, or commit messages; reference
  the environment variable name instead.

## Agent Workflow Principles
- Adversarial review before commit for behavior-changing diffs (more than one
  file, or any infra/config change). The reviewer sees the diff only, never the
  implementer's reasoning, and assumes the code is wrong. High-risk changes
  (prod infra, auth, data migrations) get two independent lenses, neither
  seeing the other's output.
- Fix the workflow, not the output: when an agent or skill produces the same
  bad pattern twice, edit its definition instead of hand-fixing instances.
- Trial run before fan-out: before any bulk or parallel operation over 3+
  similar items, run 2-3 representative items first, review, then scale.
