---
name: k8s-debug
description: Kubernetes troubleshooting workflow for EKS and GKE clusters with Helm and ArgoCD. Use when diagnosing pod failures, OOMKills, scheduling issues, ArgoCD sync failures, network problems, or HPA misbehavior.
---

# Kubernetes Debug Workflow

Follow in order. Events first — most failures are already described there.

---

## Step 1 — Start with Events

```bash
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp | tail -30
kubectl get events -A --sort-by=.metadata.creationTimestamp | grep -v Normal | tail -20
```

Events explain most failures (OOMKill, ImagePullBackOff, Unschedulable, BackOff).

---

## Step 2 — Pod Status

```bash
kubectl get pods -n <namespace>               # status overview
kubectl describe pod <pod> -n <namespace>     # full details: events, conditions, resource usage
kubectl logs <pod> -n <namespace> --previous  # logs from crashed container
kubectl logs <pod> -n <namespace> -c <container> --tail=100
```

**Common status meanings:**
| Status | Cause |
|--------|-------|
| `OOMKilled` | Memory limit too low — check `resources.limits.memory` |
| `CrashLoopBackOff` | App crashing on start — check logs with `--previous` |
| `ImagePullBackOff` | Wrong image tag or missing pull secret |
| `Pending` | Not enough resources or node selector mismatch |
| `Evicted` | Node under memory/disk pressure |

---

## Step 3 — Resource Issues

```bash
kubectl top pods -n <namespace>               # live CPU/memory usage
kubectl top nodes                             # node-level pressure
kubectl describe node <node>                  # Allocatable vs Requested
```

**HPA check:**
```bash
kubectl describe hpa <name> -n <namespace>    # current vs target metrics, min/max
kubectl get hpa -A
```

If HPA shows `<unknown>` for metrics: metrics-server is missing or pods lack CPU/memory requests.

---

## Step 4 — ArgoCD Sync Issues

```bash
argocd app list                               # all apps and sync status
argocd app get <app-name>                     # detailed status, OutOfSync resources
argocd app diff <app-name>                    # what's different
argocd app sync <app-name> --dry-run          # validate before sync
argocd app sync <app-name>                    # trigger sync
```

**Common causes:**
- `OutOfSync`: Helm values changed but not synced. Check if auto-sync is enabled for this environment.
- `Degraded`: One or more resources failed — check the app's resource tree in UI
- `Unknown`: API server unreachable or RBAC issue

**Sync waves:** Resources apply in wave order. If wave N is stuck, wave N+1 never starts.

---

## Step 5 — Network Debugging

```bash
# Test DNS resolution from inside a pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <service>.<namespace>.svc.cluster.local

# Test service connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -qO- http://<service>.<namespace>.svc.cluster.local:<port>

# Check endpoints behind a service
kubectl get endpoints <service> -n <namespace>   # empty = no matching pods

# NetworkPolicy — check what's allowed
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <name> -n <namespace>
```

---

## Step 6 — Scheduling Issues

```bash
kubectl describe node <node>     # Taints, Conditions, Allocatable
kubectl get nodes -o wide        # Ready status, OS, version
```

**If pods are Pending:**
- Check node taints vs pod tolerations
- Check nodeSelector / nodeAffinity
- Check if resource requests exceed any node's Allocatable

---

## Cluster Contexts

| Cluster | How to switch |
|---------|--------------|
| Project-a tooling | `kubectx usw2-tooling-eks-pr` |
| Project-a staging | `kubectx usw2-staging-eks-st` |
| Project-a prod | `kubectx usw2-prod-eks-pr` |
| Project-c | `AWS_PROFILE=project-c aws eks update-kubeconfig --name project-c-planters-eks --region us-east-1` |
| Project-d | `aws eks update-kubeconfig --name project-d-eks --region us-east-2` |
| project-b GKE staging | `gcloud container clusters get-credentials k8s-e24gcp-staging --zone us-central1-a --project e24gcp-staging` |
| project-b GKE prod | `gcloud container clusters get-credentials k8s-e24gcp-prod --zone us-central1-a --project e24gcp-prod` |

**Project-c note:** kubectl context drifts to GKE between sessions. Always re-run the update-kubeconfig command at the start of a Project-c session.
