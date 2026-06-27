---
name: terraform-devops
description: Terraform review checklist and best practices for AWS and GCP. Use when writing, reviewing, or planning Terraform changes across any project — covers security, tagging, state safety, and backend patterns.
---

# Terraform DevOps Review

Apply this checklist before running any Terraform plan or opening a PR for infrastructure changes.

---

## Pre-Commit Checklist

```bash
terraform fmt -recursive       # format all files
terraform validate             # syntax + type check
tflint                         # lint rules (naming, deprecated args)
terraform plan                 # review before apply
```

All four must pass. Never push .tf files without `terraform fmt`.

---

## Security Review

**IAM**
- No `*` in `actions` or `resources` in production policies
- Service roles scoped to the minimum set of permissions
- No inline policies on users — use role + group attachments

**Network**
- No `0.0.0.0/0` ingress on sensitive ports (22, 3306, 5432, 6379)
- Security groups: explicit allow, default deny
- S3 buckets: `block_public_acls = true`, `block_public_policy = true`

**Encryption**
- RDS: `storage_encrypted = true`
- EBS: `encrypted = true`
- S3: `server_side_encryption_configuration` block required
- ElastiCache: `at_rest_encryption_enabled = true`, `transit_encryption_enabled = true`

**Secrets**
- Never hardcode secrets in `.tf` files
- Use AWS Secrets Manager, Parameter Store, or HashiCorp Vault
- Reference via `data "aws_secretsmanager_secret_version"` or env vars

---

## Required Tags (all resources)

```hcl
tags = {
  Name        = "<project>-<env>-<resource>"
  Environment = "prod" | "staging" | "tooling"
  Team        = "devops"
  ManagedBy   = "terraform"
}
```

Missing any of these → OPA policy failure on Scalr (Project-a) or manual flag elsewhere.

---

## Backend Patterns

| Project | Backend | Notes |
|---------|---------|-------|
| Project-a (tf-aws) | Scalr | Remote runs on Scalr; `terraform plan/apply` triggers remote execution |
| Project-c | S3 + DynamoDB | Bucket: `devops-terraform-project-c`, region: us-east-1 |
| Project-d | S3 + DynamoDB | Region: us-east-2, workspace per environment |
| project-b | GCS or S3 | Per-account bucket |

**Scalr (Project-a):** Never run `terraform apply` locally against Scalr-managed state. Push the branch and confirm apply in the Scalr UI. OPA policies enforce tagging and instance type allowlists.

---

## State Safety Rules

- Never edit state manually with `terraform state` unless you understand the full impact
- Use `terraform import` to bring existing resources under management
- Use `terraform state mv` for refactoring, not manual JSON edits
- Before any destructive operation: run `terraform plan`, read every `-/+` and `-` line
- `terraform destroy` requires explicit user confirmation — never automate it

---

## Destroy Review (RED FLAGS)

When `terraform plan` shows a destroy (`-` lines), stop and verify:
- Is this intentional?
- Will it cause downtime?
- Is there a safer way (e.g., `create_before_destroy = true`)?

Any `aws_rds_instance`, `aws_eks_cluster`, `aws_elasticache_cluster` destruction must be reviewed by a second engineer.

---

## Naming Convention

```
<project>-<env>-<resource-type>
Examples:
  project-c-prod-rds
  project-a-vtpr-eks
  project-d-staging-sg-web
```

Modules: `terraform-<provider>-<resource>` (e.g., `terraform-aws-eks-cluster`)

---

## Cost Awareness

- Prefer GP3 over GP2 for EBS (same IOPS, cheaper)
- Use Spot for non-critical workloads (dev, batch, CI)
- Review `aws_nat_gateway` count — one per AZ is usually enough
- Check `aws_cloudwatch_log_group` retention — set `retention_in_days`, not infinite
