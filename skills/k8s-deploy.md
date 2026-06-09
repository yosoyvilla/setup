---
name: k8s-deploy
description: Use when deploying, updating, or rolling back Kubernetes services. Covers CedarPlanters (EKS + ArgoCD), Varsity (EKS + Helm + Traefik), and 360latam (GKE + Helm + Traefik).
user-invocable: true
disable-model-invocation: true
---

Deploy or update: $ARGUMENTS

## 0. Get Cluster Context (required first step)

**CedarPlanters (EKS, ArgoCD):**
```bash
# Check project CLAUDE.md for AWS profile
kubectl config use-context <cedar-eks-context>
```

**Varsity (EKS, Traefik):**
```bash
awsume vt-tooling
kubectl config use-context <vtpr|vtst>-eks
```

**360latam (GKE, Traefik):**
```bash
gcloud container clusters get-credentials <cluster> --region <region> --project <gcp-project>
```

Verify before proceeding:
```bash
kubectl config current-context
kubectl config view --minify -o jsonpath='{..namespace}'  # confirm target namespace
```

---

## 1. Write a Deployment Spec
Use the `spec-driven-development` skill (Deployment Spec template). Define what's changing, the acceptance criteria, and the rollback trigger before touching any manifests or values files.

## 2. Pre-Deploy Checklist (Helm validation)

Review `values-<env>.yaml` for the target environment. Verify:
- Resource requests AND limits set on every container
- Readiness + liveness probes defined
- PodDisruptionBudget present (production only)
- No privileged containers, no `hostNetwork: true`
- Named ServiceAccount (not `default`)
- NetworkPolicy present

Preview rendered manifests:
```bash
helm template <release> <chart> -f values-<env>.yaml
```

---

## 3. Deploy

**CedarPlanters — ArgoCD (GitHub App: cedarplantersbot):**
```bash
# Push Helm chart / values change to GitOps repo, then:
argocd app sync <app>
argocd app wait <app> --health
```

**Varsity + 360latam — Helm direct:**
```bash
helm upgrade --install <release> <chart> -f values-<env>.yaml -n <namespace>
kubectl rollout status deployment/<name> -n <namespace>
```

---

## 4. Post-Deploy Verification
```bash
kubectl get pods -l app=<service> -n <namespace>
kubectl logs -l app=<service> -n <namespace> --tail=50
kubectl get endpoints <service> -n <namespace>
```

**Traefik IngressRoute (360latam, Varsity):**
```bash
kubectl get ingressroute -n <namespace>
kubectl describe ingressroute <name> -n <namespace>
```

**ExternalSecrets (360latam):**
```bash
kubectl get externalsecret -n <namespace>   # Ready=True means secrets synced from GCP Secret Manager
```

Run smoke test if the service exposes one. Check application logs for startup errors before declaring success.

---

## 5. Rollback

**CedarPlanters (ArgoCD):**
```bash
argocd app rollback <app>  # rolls back to previous synced revision
```

**Varsity + 360latam (Helm):**
```bash
helm history <release> -n <namespace>            # find target revision
helm rollback <release> <revision> -n <namespace>
kubectl rollout undo deployment/<name> -n <namespace>  # emergency only, bypasses Helm
```
