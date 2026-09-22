---
name: kubernetes-conventions
description: Kubernetes and Helm conventions for this org — resource requests/limits, PodDisruptionBudgets, probes, label scheme, Helm-over-Kustomize, ArgoCD sync policy, NetworkPolicy defaults, and kubectl troubleshooting. Use when writing or reviewing K8s manifests, Helm charts, ArgoCD Applications, or debugging pods.
---

# Kubernetes Conventions


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
- Traefik v3 `basicAuth` middleware: the referenced Secret must contain EXACTLY one key, named `users`. A second key (e.g. `auth` for nginx) makes Traefik log "found N elements for secret, must be single element exactly" and SILENTLY allow all traffic. nginx basic auth needs its own Secret. (Verified live 2026-05-28; 11/11 benchmarked models got this wrong.)

## Troubleshooting
```bash
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl describe pod <pod>
kubectl logs <pod> --previous  # for crash loops
kubectl top pod               # resource usage
```
