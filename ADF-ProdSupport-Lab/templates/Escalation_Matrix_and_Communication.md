# Escalation Matrix & Communication Templates

## 1. Severity definitions & SLA (also in `ops.EscalationMatrix`)

| Sev | Definition | Example (RetailMart) | Acknowledge | Resolve/restore | Update cadence | Hours |
|---|---|---|---|---|---|---|
| **P1** | Critical business outage, no workaround, regulatory/financial risk | CFO report + regulatory feed down at 08:30 | 15 min | 4 h | 30 min | 24×7 |
| **P2** | Major degradation, SLA at risk, workaround possible | Master failed at 02:07; health check shows wrong revenue | 30 min | 8 h | 60 min | 24×7 |
| **P3** | Single non-critical failure, within SLA | Child pipeline failed, retry likely fixes | 2 h | 24 h | 4 h | business hours |
| **P4** | Minor/cosmetic/informational | Duration warning, typo in log | 8 h | 72 h | daily | business hours |

**Priority = Impact × Urgency.** Re-evaluate severity at every update — urgency increases as the SLA deadline approaches.

## 2. Who to escalate to (functional)

| Tier | Team | Handles | Contact (lab) |
|---|---|---|---|
| L1 | DataOps on-call | Alerts, tickets, runbooks, reruns, comms | rota / Teams `#dataops-oncall` |
| L2 | Data Engineering | Pipeline logic, data fixes, credentials, code changes | DE on-call |
| L3 | Platform / Cloud | IAM, networking, IR, Key Vault, Azure platform, Microsoft support case | Platform on-call |
| L3 | Upstream owners | POS team (sales), CRM vendor (customers) | vendor desk |
| Vendor | Microsoft Azure Support | Product bugs, regional outages (open case with RunIds, region, timestamps UTC) | Portal → Help + support |

## 3. Hierarchical escalation (management)

| Trigger | Inform |
|---|---|
| Any P1 at creation | Support Manager + Delivery Head |
| P2 at 75 % of resolve SLA without clear fix | Support Manager |
| Any SLA breach | Support Manager; business owner |
| Suspected security/data leak | Security team immediately (any severity) |

## 4. Escalation timing rules (lab policy)
- Runbook exhausted → escalate immediately.
- 50 % of resolve SLA elapsed without root cause → functional escalation.
- 75 % → hierarchical escalation.
- Never "silent" escalation: always a ticket entry with `EntryType='Escalation'`.

## 5. SBAR escalation message
```
[ESCALATION] INC000123 – P2 – PL_Master_Daily failed for 20261015
S: Daily sales load failed 02:07 IST; CFO 09:00 report at risk.
B: Copy_Customers_To_Stg fails "column customer_id not found". No ADF changes in 48h (Activity log).
A: Vendor customer file header changed (cust_id). Pipeline config is correct.
R: L2 please confirm option B (vendor resend) / approve emergency mapping change if vendor can't resend by 06:00.
Ticket: INC000123 · RunIds: master 8c1f..., child a42d...
```

## 6. Stakeholder communication templates

**Initial (within ack SLA)**
> Subject: [P2][Investigating] Daily sales report for 15-Oct delayed
> We are investigating a failure in the overnight sales data load (INC000123). The 15-Oct figures in the CFO dashboard are not yet updated. Next update by 03:30 IST.

**Update**
> [P2][Identified] Cause: the customer file received from <vendor> is in an unexpected format. We have requested a corrected file (ETA 04:00). Next update 04:30 IST.

**Resolved**
> [P2][Resolved] The 15-Oct data was loaded and validated at 04:22 IST (60 orders, ₹186,667.30). The dashboard is up to date. A root-cause review will follow by <date>.

Rules: plain language, no blame, impact + ETA + next update time, one owner of comms (incident manager), comms logged as `EntryType='Communication'`.
