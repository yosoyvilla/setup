---
name: validating-packages
description: >-
  Use before adding, installing, or importing any third-party dependency (npm,
  PyPI, cargo, Go module, gem, etc.) or when code references a package not
  already in the project's manifest. Confirms the package actually exists in its
  real registry before install, to defend against hallucinated-package
  ("slopsquatting") supply-chain risk.
---

# Validating packages

Open models fabricate plausible-looking package names roughly four times more
often than frontier models, and the same fabrications recur across runs — so
attackers pre-register them. Never install a dependency on the model's say-so.
Confirm it exists, in the right registry, with the right name, first.

## Before any install or new import

1. **Confirm it exists in the real registry** (read-only check, no install):
   - npm: `npm view <pkg> version` (errors if it does not exist)
   - PyPI: `pip index versions <pkg>` or fetch `https://pypi.org/pypi/<pkg>/json`
   - cargo: `cargo search <pkg>` or check `https://crates.io/api/v1/crates/<pkg>`
   - Go: `go list -m <module>@latest`
   - gem: `gem list -r -e <pkg>`
2. **Check it is the intended package, not a typo/lookalike.** Verify the exact
   name, the publisher/repo, recent maintenance, and download counts. A brand-new
   package with no history that the model "remembered" is a red flag.
3. **Prefer what is already there.** If the project or stdlib already covers the
   need, do not add a dependency at all.
4. **Only then install**, pinned to a confirmed version, and let
   `verifying-changes` run the build/tests.

## Hard rules

- If a package cannot be confirmed in its registry, do NOT install it. Report it
  as unverified and stop — do not guess an alternative name.
- Never run an install command sourced directly from model output without the
  existence check above.
- Surface every newly added dependency in your summary so it can be reviewed.
