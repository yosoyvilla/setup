---
name: incident-response
description: Use when investigating production outages, degraded performance, or unexpected behavior. Covers project-a (EKS + New Relic), project-c (EKS + ArgoCD + Loki), project-b (GKE + Traefik), and project-d (Dokploy).
user-invocable: true
---

Investigate incident: $ARGUMENTS

## 1. Triage
- Full outage vs degraded vs slow? Exact start time?
- SEV1 (full outage, 15 min) / SEV2 (degraded, 30 min) / SEV3 (minor, 4h) / SEV4 (low, next day)
- Identify which project/product is affected → go to correct section below

---

## 2. Gather Evidence

### project-a (EKS + New Relic + Traefik)
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

### project-c (EKS + ArgoCD + Loki/Grafana)
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

### project-b (GKE + Traefik)
```bash
gcloud container clusters get-credentials <cluster> --region <region> --project <gcp-project>
kubectl get pods -A | grep -Ev "Running|Completed"
kubectl get events --sort-by=.metadata.creationTimestamp | tail -20
kubectl logs -l app=<service> --tail=100 --since=30m
kubectl get ingressroute -A                   # Traefik IngressRoutes
kubectl get externalsecret -A                 # ExternalSecrets → GCP Secret Manager sync
kubectl describe externalsecret <name> -n <namespace>  # if secrets not syncing, pods won't start
```

### project-d (Dokploy on EC2)
```bash
ssh project-d_3p_services
docker ps                          # running containers
docker logs <container> --tail=100 --since 30m
docker stats --no-stream           # CPU/memory snapshot
```
Dokploy UI: check deployment status and recent deployment logs for the affected service.

---
- CloudWatch Logs Insights syntax that is REJECTED live even though docs list it: scientific-notation literals (`/1e9` -> write `/1000000000`), `sort` on an unaliased aggregate (`sort count() desc` -> `stats count() as c ... | sort c desc`), `strcontains()`/`startsWith()` (use `like`). A `filter` placed after `stats` filters the aggregated rows (volume guard: `| filter n > 100`). Execute every query once before handing it over.

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
   - ArgoCD (project-c): `argocd app rollback <app>`
   - Dokploy (project-d): redeploy previous image via Dokploy UI
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

## Converge, do not exhaust (added 2026-08-21, evidence-based)

State a hypothesis early, gather only evidence that DISCRIMINATES between hypotheses,
and stop. ITBench-AA measured agents on Kubernetes root-cause from alerts, traces,
metrics, logs and topology: **58 turns -> 37%, 83 turns -> 30%**. More turns made it
worse. The maxTurns cap should never be what stops you.

Calibrate confidence accordingly: frontier models score **11.4% on SRE scenarios**
(ITBench) and **under 50% on K8s root-cause** (ITBench-AA). Present a diagnosis as a
hypothesis to verify, never as a conclusion. Say what would falsify it.

Reproduce before fixing. Removing the reproduction step measurably degraded every model
tested (arXiv:2604.12147) — do not skip straight to a remedy.

## Step-change triage (added 2026-09-22, after a near-miss)

For a SHARP step in a metric (a rate that jumps at one minute and stays), the cause
happened at that minute. FIRST enumerate what changed around that time — config-file
mtimes (`ls -la`), deploy/rollout times, API/config writes — and bisect by time. Only
then chase "where does this message come from". On 2026-09-22 a single `ls -la` on
solrconfig.xml (mtime == the exact 500s step) closed a five-round hunt that had gone
Solr logs -> container log files -> repo greps -> dead-end concurrency tests.

## Never test with your own client and call it the system's behaviour (added 2026-09-22)

Before reporting a user-facing symptom, state what your test client is and whether it
is a valid probe. Check: (a) your egress COUNTRY vs the target's IP Access Rules — a
whitelisted country short-circuits the whole WAF (portal-4 whitelists CO, so a CO probe
proves nothing about portal-4's rules); (b) whether your client is AUTOMATED — a headless
browser is classified as a bot by SBFM and blocked where a real browser passes; (c)
whether the target's BIC/bot rules turn bare curl into a false 403. Prefer independent
telemetry (edge/CDN analytics) over your own request. Test-method validity is part of
the claim — on 2026-09-22 a self-blocked probe was reported as a site finding twice.

## Time-box diagnostics (added 2026-09-22)

After 3 attempts that fail to converge, consult Oracle — or stop and report the
hypothesis plus what would falsify it. Do not keep digging past the point where the
next attempt is unlikely to discriminate between hypotheses (see "Converge, do not
exhaust" above).
