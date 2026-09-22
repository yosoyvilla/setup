---
name: release
description: Use when creating a project release across any project — generates changelog, bumps version, tags, and publishes a GitHub or Bitbucket release. Covers Node/pnpm (project-c), Go (project-a), PHP/Python (project-b), and Terraform modules.
user-invocable: true
---

Create release for: $ARGUMENTS

## Step 1 — Determine Version Bump
```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
git describe --tags --abbrev=0 2>/dev/null || echo "No tags — start at v0.1.0"
```
Semantic versioning rules:
- `fix:` or patch-only → PATCH (1.2.3 → 1.2.4)
- `feat:` or new behavior → MINOR (1.2.3 → 1.3.0)
- `BREAKING CHANGE` or `!` suffix → MAJOR (1.2.3 → 2.0.0)
- Infra/config/chore only → PATCH

## Step 2 — Generate Changelog
```bash
git log $(git describe --tags --abbrev=0)..HEAD \
  --pretty=format:"- %s (%h)" --no-merges
```
Organize into sections: **Features / Bug Fixes / Infrastructure / Breaking Changes**.
Skip: merge commits, automated commits, trivial dependency bumps.

## Step 3 — Update Version File

**project-c (pnpm monorepo, TypeScript):**
Update `package.json` version field. If changesets are configured: use `pnpm changeset version` instead of editing manually.

**project-a (Go services):**
`go.mod` does not change between releases — the git tag is the version. Check for a `version.go` file with a `Version` var; if build uses `-ldflags "-X main.Version=vX.Y.Z"`, no file to update. Tag is the source of truth.

**project-b (PHP/Python):**
Check `setup.py`, `pyproject.toml`, or project-specific version constant. Bitbucket repos may not have a version file — tag only.

**project-a tf-aws (Terraform modules):**
No version file. Tag format: `<module-name>/vX.Y.Z` (e.g., `terraform-aws-eks-cluster/v1.2.0`).

## Step 4 — Commit + Tag
```bash
git add <version-file>    # skip if no file to update
git commit -m "chore: bump version to vX.Y.Z"
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

## Step 5 — Create Release

**GitHub (project-a, project-c, Personal — yosoyvilla or crewgent account):**
```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z" \
  --notes "<changelog>" \
  --latest
# Add --prerelease for RC/beta
```

**Bitbucket (project-b — Bitbucket Pipelines):**
`gh` does not support Bitbucket. Create release via Bitbucket UI (Repository → Tags → Create tag) or Bitbucket API. A Bitbucket Pipeline on the tag may auto-deploy — verify pipeline config first.

## Step 6 — Verify
```bash
gh release view vX.Y.Z    # GitHub only
```
Check that CI/CD pipelines triggered correctly on the new tag.
Announce in relevant Slack channel if production release.

**Safety rule: never delete or move a published tag.** If a tag was pushed incorrectly, create a new patch release instead. Deleting tags breaks Go module resolution, Terraform module pinning, and any downstream that has already pulled the tag.
