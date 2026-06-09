---
name: incident-triage
description: Systematic incident triage for production issues. Use when investigating service outages, elevated error rates, performance degradation, security alerts, or any unexpected production behavior.
---

# Incident Triage

**Prime directive:** Mitigate impact first. Root cause second. Never guess — gather evidence.

---

## First 5 Minutes — Scope, Not Cause

Answer these before touching anything:

1. **What is broken?** Exact service, endpoint, or feature affected.
2. **Who is affected?** All users? A region? A specific integration?
3. **Since when?** Correlate with recent deployments or changes.
4. **What is the impact?** Error rate, latency, data loss, security breach?

```bash
# Kubernetes: quick overview
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl get events -A --sort-by=.metadata.creationTimestamp | grep -v Normal | tail -20

# AWS: check CloudWatch alarms in the account
aws cloudwatch describe-alarms --state-value ALARM --region <region>
```

---

## Evidence Gathering

Gather before changing anything. Evidence disappears after restarts or rollbacks.

**Application logs:**
```bash
kubectl logs <pod> -n <namespace> --previous --tail=200
kubectl logs -l app=<name> -n <namespace> --tail=100 --all-containers
```

**Metrics:** Check New Relic (Varsity), CloudWatch, or Uptime Kuma dashboards before assuming.

**Recent changes:**
```bash
git log --oneline -10           # recent commits
kubectl rollout history deployment/<name> -n <namespace>   # recent deploys
argocd app history <app>        # ArgoCD deploy history
```

**For AWS incidents:**
```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=<suspicious-action> --start-time <ISO> --region <region>
```

---

## Mitigation — Before Root Cause

If impact is active, mitigate first:

**Rollback a deployment:**
```bash
kubectl rollout undo deployment/<name> -n <namespace>
# or via ArgoCD:
argocd app rollback <app> <revision>
```

**Scale up to absorb load:**
```bash
kubectl scale deployment/<name> --replicas=<N> -n <namespace>
```

**Disable a feature flag** (if applicable) or route traffic away from the affected service.

Document what you did and when — this becomes the incident timeline.

---

## Timeline Reconstruction

After mitigation, reconstruct the sequence:

1. When did the first anomaly appear? (check metrics, not just alerts)
2. What changed just before? (deploy, config, external API, traffic spike)
3. What was the blast radius at each point?
4. When was mitigation applied and when did symptoms resolve?

---

## Communication Template

For Slack/status updates during an active incident:

```
[INCIDENT] <service> — <short description>
Status: Investigating | Mitigating | Resolved
Impact: <who/what is affected>
Started: ~<time>
Last update: <time>
Next update: in <N> minutes
```

---

## Post-Incident

After resolution, document:
- Timeline (start → root cause → mitigation → resolution)
- Root cause (not guess — confirmed)
- What detection missed and why
- Action items to prevent recurrence

Do NOT file Jira tickets with PII, token names, credential paths, or exposed secret details. Frame findings as proactive security improvements, not incident response.
