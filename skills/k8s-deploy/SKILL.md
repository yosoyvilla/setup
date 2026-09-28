---
name: k8s-deploy
description: Use when deploying, updating, or rolling back Kubernetes services. Covers the e-commerce platform (EKS + ArgoCD), the EdTech platform (EKS + Helm + Traefik), and the real-estate portals (GKE + Helm + Traefik).
user-invocable: true
disable-model-invocation: true
---

Deploy or update: $ARGUMENTS

## 0. Get Cluster Context (required first step)

**the e-commerce platform (EKS, ArgoCD):**
```bash
# Check project CLAUDE.md for AWS profile
kubectl config use-context <project-c-eks-context>
```

**the EdTech platform (EKS, Traefik):**
```bash
awsume vt-tooling
kubectl config use-context <vtpr|vtst>-eks
```

**the real-estate portals (GKE, Traefik):**
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

**the e-commerce platform — ArgoCD (GitHub App: the e-commerce platformbot):**
```bash
# Push Helm chart / values change to GitOps repo, then:
argocd app sync <app>
argocd app wait <app> --health
```

**the EdTech platform + the real-estate portals — Helm direct:**
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

**Traefik IngressRoute (the real-estate portals, the EdTech platform):**
```bash
kubectl get ingressroute -n <namespace>
kubectl describe ingressroute <name> -n <namespace>
```

**ExternalSecrets (the real-estate portals):**
```bash
kubectl get externalsecret -n <namespace>   # Ready=True means secrets synced from GCP Secret Manager
```

Run smoke test if the service exposes one. Check application logs for startup errors before declaring success.

---

## 5. Rollback

**the e-commerce platform (ArgoCD):**
```bash
argocd app rollback <app>  # rolls back to previous synced revision
```

**the EdTech platform + the real-estate portals (Helm):**
```bash
helm history <release> -n <namespace>            # find target revision
helm rollback <release> <revision> -n <namespace>
kubectl rollout undo deployment/<name> -n <namespace>  # emergency only, bypasses Helm
```
