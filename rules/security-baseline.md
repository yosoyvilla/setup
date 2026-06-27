# Security Baseline

> Obsidian: ~/Documents/obsidian-vault/claude-code/security-baseline.md

## Secrets
- Never in code, never in env vars if Vault is available
- Rotate on schedule, document rotation procedures
- Use short-lived credentials where possible (OIDC, dynamic secrets)

## IAM
- Least privilege always
- No wildcards in production IAM policies
- Review permissions quarterly
- Service accounts: one per service, scoped to minimum

## Encryption
- At rest: always (S3, RDS, EBS, etc.)
- In transit: TLS 1.2+ everywhere, no exceptions
- Certificate management: cert-manager + Let's Encrypt for K8s

## Containers
- Minimal base images (distroless preferred)
- No root user
- Read-only filesystem
- Scan images in CI (Trivy, Grype, or equivalent)

## Access
- SSO for all internal tools
- MFA required
- VPN for infrastructure access
- Audit logging enabled on all services
