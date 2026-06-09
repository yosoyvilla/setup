---
name: scalr-deploy
description: Use when deploying Terraform changes for Varsity via Scalr. Scalr acts as the Terraform remote backend — plan and apply run remotely on Scalr, not locally.
user-invocable: true
---

Deploy Terraform via Scalr: $ARGUMENTS

## Context (Varsity only)
- **tf-aws monorepo**, multi-account: vtpr, vtst, bipr, bist, lppr, lpst, tooling
- Workspace naming: `<account>-<module>` (e.g., `vtpr-eks`, `vtst-rds`)
- Scalr = Terraform remote backend. `terraform plan/apply` run on Scalr's infrastructure.
- OPA policies in `scalr-opa-policies/` enforce tagging, naming, and security constraints.
- VCS push auto-triggers a Scalr run if workspace is VCS-connected.

## Before Starting — Write an Infra Spec
Use the `spec-driven-development` skill (Infra/Terraform template). Define current state, target state, resources affected, acceptance criteria, and rollback plan before running any plan. The spec is the basis for reviewing the Scalr plan output.

## Prerequisites
```bash
awsume vt-tooling      # required for post-apply AWS CLI verification

# Confirm sparse checkout includes your target account
git sparse-checkout list
git sparse-checkout add <account>   # add if missing (vtpr, vtst, tooling, etc.)
```

## Step 1 — Identify Workspace
Workspace = `<account>-<module>`. Confirm in Scalr UI or via API:

<!-- REQUIRES SECRET: export SCALR_TOKEN="..." in ~/.zshrc
     Get from: Scalr UI → <your-account> → User Settings → API Tokens → Create token -->
```bash
curl -H "Authorization: Bearer $SCALR_TOKEN" \
  "https://<scalr-account>.scalr.io/api/iacp/v3/workspaces?filter[name]=<workspace>"
```

## Step 2 — Pre-Plan Checks
```bash
cd <module-dir>
git status                  # confirm only intended files are changed
git log --oneline -5        # confirm you're on the right commit
terraform fmt -check
terraform validate
tflint                      # enforced in CI; run locally to catch early
```

## Step 3 — Trigger Plan

**Preferred — VCS push (Scalr auto-triggers):**
```bash
git push origin <branch>
```

**Alternative — local Terraform CLI against Scalr backend:**
```bash
terraform plan    # runs remotely on Scalr; output streams locally
```

Monitor the run in the Scalr UI.

## Step 4 — Review Plan + OPA
In Scalr UI, before confirming apply, check:
- **Destroy actions** → stop and investigate (RED FLAG unless intentional)
- OPA policy results — common failures:
  - Missing tags: `Name`, `Environment`, `Team`, `ManagedBy=terraform`
  - Instance type not in allowlist
  - Unencrypted resource or public-access S3 bucket

Fix in code → push → re-run until OPA passes.

## Step 5 — Apply
Confirm apply in Scalr UI (workspaces not set to auto-apply).

## Step 6 — Post-Apply Verification
```bash
# awsume vt-tooling must be active
aws eks describe-cluster --name <cluster> --region <region>
aws rds describe-db-instances --db-instance-identifier <id>
# Add service-specific checks as appropriate
```

## Rollback
```bash
git revert HEAD
git push origin <branch>
# Scalr auto-triggers plan on the revert commit; review and apply
```
Never manipulate `terraform state` directly against Scalr-managed state.
