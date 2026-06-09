# Required Secrets and Credentials

All secrets are stored as environment variables in `~/.zshrc`. None are hardcoded in config files.

Add each secret you use to `~/.zshrc`:

```zsh
export SECRET_NAME="value"
```

Then reload: `source ~/.zshrc`

---

## Secrets Reference

### NAN_API_KEY
- **Used by:** opencode (`oh-my-openagent`), Zed IDE
- **Purpose:** Access to NaN API — an OpenAI-compatible proxy for qwen3.6, deepseek-v4-flash, mimo-v2.5, and gemma4
- **Get it:** https://nan.builders — sign up and generate an API key from your account dashboard
- **Set it:**
  ```zsh
  export NAN_API_KEY="sk-..."
  ```

### SCALR_TOKEN
- **Used by:** `skills/scalr-deploy.md` skill (Varsity project only)
- **Purpose:** Authenticate with Scalr remote Terraform backend to trigger plans and check workspace status
- **Get it:** Scalr UI → `<your-account>` → User Settings → API Tokens → Create token
- **Set it:**
  ```zsh
  export SCALR_TOKEN="..."
  ```

### AIRBYTE_TOKEN
- **Used by:** `agents/airbyte.md` agent (CedarPlanters project)
- **Purpose:** Authenticate with Airbyte API (Cloud or self-hosted) to manage connectors and trigger syncs
- **Get it:**
  - Airbyte Cloud: Settings → Applications → Create Application token
  - Self-hosted: Settings → Authentication → API tokens
- **Set it:**
  ```zsh
  export AIRBYTE_TOKEN="..."
  ```

### NEW_RELIC_API_KEY
- **Used by:** New Relic CLI / direct API calls (Varsity project)
- **Purpose:** Query NRQL, manage dashboards and alert policies programmatically
- **Get it:** New Relic → User menu → API keys → Create key (User key type)
- **Set it:**
  ```zsh
  export NEW_RELIC_API_KEY="NRAK-..."
  ```

### AWS Credentials
- **Used by:** `aws` CLI, `awsume`, Terraform (Varsity, CedarPlanters, Kashport)
- **Purpose:** Access AWS accounts
- **Get it:** AWS Console → IAM → Users → Security credentials → Create access key
- **Set it:** Use `aws configure --profile <profile-name>` — do NOT export static keys directly
- **Note:** Use `awsume` for role assumption with MFA. Profile names: `vt-tooling`, `cedar-prod`, etc.

### GCP Credentials
- **Used by:** `gcloud`, Terraform GCP provider (360latam project)
- **Purpose:** Access GCP projects
- **Get it:** Run `gcloud auth login` and `gcloud auth application-default login`
- **Set it:** Managed by gcloud — no env var needed for most operations

### VAULT_ADDR
- **Used by:** HashiCorp Vault CLI (`vault` commands)
- **Purpose:** Connect to the Vault server
- **Not a secret** — it's the server URL, safe to commit
- **Set it:**
  ```zsh
  export VAULT_ADDR="https://vault.helmcode.com"
  ```
  Vault tokens are managed by `vault login` and stored in `~/.vault-token` (short-lived, not in `.zshrc`).

---

## Never Commit These

- `.env` files
- `terraform.tfstate` / `terraform.tfstate.backup`
- `*.pem` / `*.key` files
- Any file in `secrets/` directories
- `~/.aws/credentials` (already excluded by default .gitignore patterns)

The file protection hook in `~/.claude/settings.json` blocks Claude Code from editing these files automatically.
