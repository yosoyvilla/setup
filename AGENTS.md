# Global Instructions

Portable engineering standards for all agent work. This file is shared
byte-for-byte between opencode (`~/.config/opencode/AGENTS.md`) and Zed
(`~/.config/zed/AGENTS.md`) — edit them together. Project-level instruction
files override these where they conflict.

## Models
- NaN is the only allowed provider. Use `nan/*` models exclusively:
  `nan/deepseek-v4-flash` (orchestration/planning), `nan/mimo-v2.5` (deep
  reasoning/review/multimodal), `nan/qwen3.6` (fast/cheap default),
  `nan/gemma4` (fallback). Never introduce another provider.
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
- Gate on external signals, not on self-confidence. Decisions to proceed rest
  on tests passing, types checking, the registry confirming, the doc saying so
  — never on the model feeling sure. Your stated certainty is not evidence.
- Escalate when it matters: an adversarial critic for review of any output or
  plan, a fact-checker to verify claims against primary sources, and a
  multi-lens council for high-stakes decisions. (opencode: `@critic`,
  `@fact-checker`, `/council`. Zed: the matching skills.)
- Vision needs a vision model. For browser screenshots or any image/visual
  verification, use a vision-capable model (`nan/mimo-v2.5`, `nan/gemma4`, or
  `nan/qwen3.6`); `nan/deepseek-v4-flash` is text-only and will fabricate image
  descriptions. Use `browser_snapshot` (accessibility text) for DOM interaction
  on any model.

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

## Code
- SOLID/KISS/DRY applied pragmatically, not dogmatically. Extract on the third
  repetition, not the first.
- Fail fast: validate at boundaries, return early, shallow nesting.
- Immutability by default. Meaningful names, small functions, no dead or
  commented-out code.

## Git and docs
- Single-line commit messages. No co-author trailer. No emojis.
- No emojis in documentation. Do not create new markdown/doc files without
  explicit approval — ask first.
