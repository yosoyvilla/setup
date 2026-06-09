---
name: terraform-review
description: Reviews Terraform code for best practices, security, and cost. Use when reviewing .tf files, planning infrastructure changes, or checking Terraform plans.
---

Systematically check the following. Apply the AWS sections to Varsity/CedarPlanters/Kashport, the GCP section to 360latam.

## Security — AWS (Varsity, CedarPlanters, Kashport)
- No hardcoded secrets, API keys, or passwords in `.tf` files
- IAM: least privilege — no `*` actions on `*` resources in prod
- Encryption at rest: S3, RDS, EBS, EFS
- Encryption in transit: TLS/HTTPS endpoints only
- Security groups: no `0.0.0.0/0` ingress on non-HTTP(S) ports
- KMS keys for sensitive data

## Security — GCP (360latam)
- No `allUsers` or `allAuthenticatedUsers` on storage buckets or APIs
- Use predefined `roles/` — custom roles only when predefined don't fit
- Cloud SQL: `require_ssl = true`, `ipv4_enabled = false` (private-only unless justified)
- Cloud SQL: automated backups enabled, point-in-time recovery enabled
- GKE: Workload Identity enabled — no service account key files mounted as secrets
- GKE: shielded nodes, auto-upgrade enabled on node pools
- Secrets in GCP Secret Manager, not hardcoded in Terraform
- Artifact Registry (`pkg.dev`) — not legacy GCR (`gcr.io`)

## Cost
- Right-sized instances (flag obvious over-provisioning)
- S3/GCS/ECR lifecycle policies present
- Auto-scaling configured for variable workloads
- Spot/preemptible instances for non-critical or batch workloads

## Best Practices
- Remote state with locking (S3+DynamoDB for AWS; Scalr for Varsity tf-aws)
- Data sources over hardcoded resource IDs
- Module versions pinned — not `source = "module?ref=main"`
- All resources tagged: `Name`, `Environment`, `Team`, `ManagedBy=terraform`
- `terraform fmt` applied, `terraform validate` clean
- `tflint` passes (enforced in Varsity CI via GitHub Actions)

## Reliability
- Multi-AZ for production databases and critical services
- Backup retention set appropriately per environment
- Health checks configured on load balancer target groups

Report findings grouped by severity: **Critical / High / Medium / Low**.
