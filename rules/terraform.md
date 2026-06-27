# Terraform Conventions

> Obsidian: ~/Documents/obsidian-vault/claude-code/terraform.md

## Naming
- Resources: `<project>-<env>-<resource>` (e.g., `project-c-prod-rds`)
- Modules: `terraform-<provider>-<resource>` (e.g., `terraform-aws-eks-cluster`)
- Variables: snake_case, descriptive
- Outputs: snake_case, prefix with resource type

## Structure
- Remote state with locking (S3 + DynamoDB or Scalr)
- Data sources over hardcoded IDs
- Variables over magic values
- Modules for reuse (3+ repetitions)

## Tagging
All resources must have: Name, Environment, Team, ManagedBy=terraform

## Validation
- `terraform fmt` before commit
- `terraform validate` in CI
- `tflint` for linting
- `terraform test` for module testing

## State
- Never modify state manually
- Use `terraform import` for existing resources
- Use `terraform state mv` for refactoring
- Lock state before manual operations
