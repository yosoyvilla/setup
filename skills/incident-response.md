---
name: incident-response
description: Use when investigating production outages, degraded performance, or unexpected behavior. Covers Varsity (EKS + New Relic), CedarPlanters (EKS + ArgoCD + Loki), 360latam (GKE + Traefik), and Kashport (Dokploy).
user-invocable: true
disable-model-invocation: true
---

Investigate incident: $ARGUMENTS

## 1. Triage
- Full outage vs degraded vs slow? Exact start time?
- SEV1 (full outage, 15 min) / SEV2 (degraded, 30 min) / SEV3 (minor, 4h) / SEV4 (low, next day)
- Identify which project/product is affected → go to correct section below

---

## 2. Gather Evidence

### Varsity (EKS + New Relic + Traefik)
```bash
awsume vt-tooling
kubectl config use-context <vtpr|vtst>-eks
kubectl get pods -A | grep -Ev "Running|Completed"
kubectl get events --sort-by=.metadata.creationTimestamp -A | tail -20
kubectl logs -l app=<service> --tail=100 --since=30m
kubectl get ingressroute -A  # Traefik routing health
```
New Relic (one.newrelic.com → APM → [service]):
```nrql
SELECT count(*) FROM TransactionError WHERE appName='<svc>' SINCE 30 minutes ago FACET error.class
SELECT average(duration) FROM Transaction WHERE appName='<svc>' SINCE 1 hour ago TIMESERIES
SELECT * FROM Log WHERE service='<svc>' AND level='ERROR' SINCE 30 minutes ago
```

### CedarPlanters (EKS + ArgoCD + Loki/Grafana)
```bash
# ArgoCD — check sync/health before touching pods
argocd app list | grep -Ev "Synced|Healthy"
argocd app get <app> | grep -E "Health|Sync|Operation"
# K8s
kubectl get pods -n <namespace> | grep -Ev "Running|Completed"
kubectl logs -l app=<service> -n <namespace> --tail=100 --since=30m
# Celery workers / queues (if task-processing incident)
kubectl get pods -l app=celery-worker -n <namespace>
kubectl exec -n <namespace> deploy/rabbitmq -- rabbitmqctl list_queues name messages consumers
```
Grafana/Loki: check cluster Grafana for error spikes and recent log tail for the affected service.

### 360latam (GKE + Traefik)
```bash
gcloud container clusters get-credentials <cluster> --region <region> --project <gcp-project>
kubectl get pods -A | grep -Ev "Running|Completed"
kubectl get events --sort-by=.metadata.creationTimestamp | tail -20
kubectl logs -l app=<service> --tail=100 --since=30m
kubectl get ingressroute -A                   # Traefik IngressRoutes
kubectl get externalsecret -A                 # ExternalSecrets → GCP Secret Manager sync
kubectl describe externalsecret <name> -n <namespace>  # if secrets not syncing, pods won't start
```

### Kashport (Dokploy on EC2)
```bash
ssh kashport_3p_services
docker ps                          # running containers
docker logs <container> --tail=100 --since 30m
docker stats --no-stream           # CPU/memory snapshot
```
Dokploy UI: check deployment status and recent deployment logs for the affected service.

---

## 3. Correlate
```bash
gh pr list --state merged --limit 5   # recent merged PRs across any GitHub repo
```
- What changed just before the incident? (deploy, Terraform apply, config change)
- Isolated to one service or systemic? (blast radius)
- External dependency? (Cloudflare, third-party API, DNS)

---

## 4. Mitigate (fastest first)
1. **Rollback deploy**
   - K8s: `kubectl rollout undo deployment/<name>`
   - ArgoCD (CedarPlanters): `argocd app rollback <app>`
   - Dokploy (Kashport): redeploy previous image via Dokploy UI
2. **Scale up** — `kubectl scale deployment/<name> --replicas=<n>`
3. **Failover** — switch traffic to healthy region/cluster
4. **Hotfix** — only if rollback would reintroduce a worse problem

---

## 5. Communicate
```
INCIDENT: [SEV] - [Brief description]
IMPACT: [What is broken, estimated user count]
STATUS: [Investigating / Mitigating / Resolved]
NEXT UPDATE: [Time]
```

---

## 6. Postmortem
- Timeline (minute-by-minute)
- Root cause
- What worked / what didn't
- Action items with owners and due dates
