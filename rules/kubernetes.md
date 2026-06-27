# Kubernetes Conventions

> Obsidian: ~/Documents/obsidian-vault/claude-code/kubernetes.md

## Resource Standards
- Always set resource requests AND limits
- PodDisruptionBudgets for production workloads
- Readiness and liveness probes required
- Labels: app.kubernetes.io/name, version, component

## Helm (Preferred over Kustomize)
- values.yaml for defaults, values-<env>.yaml for overrides
- Chart.lock committed to repo
- `helm template` for validation before apply

## ArgoCD
- Auto-sync + self-heal for non-prod
- Manual sync for prod
- Sync waves for ordering

## Security
- NetworkPolicies: default deny, explicit allow
- No root containers
- Read-only root filesystem where possible
- ServiceAccount per workload (no default)

## Troubleshooting
```bash
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl describe pod <pod>
kubectl logs <pod> --previous  # for crash loops
kubectl top pod               # resource usage
```
