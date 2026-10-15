# Root Cause Analysis / Post-Incident Review (blameless)

| Field | Value |
|---|---|
| Incident(s) | INC______ (parent), INC______ (children) |
| Severity | |
| Service | |
| Date of incident | |
| Author / reviewers | |
| Detection → Ack → Resolve (IST) | |
| MTTD / MTTA / MTTR | |

## 1. Summary (3–4 lines, business language)
What happened, who was affected, for how long, how it was fixed.

## 2. Impact
- Business: (e.g. CFO report for 15-Oct delayed by Xh; between hh:mm and hh:mm report showed ₹ X under "Unknown")
- Data: rows/tables/dates affected
- SLA: met / breached by X min

## 3. Timeline (IST)
| Time | Event |
|---|---|
| 02:00 | Trigger fired … |
| | |

## 4. Root cause — 5 Whys
1. Why did the report not update? →
2. Why …? →
3. Why …? →
4. Why …? →
5. Why …? → **root cause**

Contributing factors (detection gaps, process gaps):

## 5. What went well / what didn't
| Went well | Didn't go well |
|---|---|
| | |

## 6. Corrective & Preventive Actions (CAPA)
| # | Action | Type (Detect / Prevent / Process / Recover) | Owner | Due | Ticket |
|---|---|---|---|---|---|
| 1 | | Detect | | | |
| 2 | | Prevent | | | |
| 3 | | Process | | | |

## 7. Lessons learned / runbook updates

> Blameless: describe systems and decisions, not people. "The process allowed an unreviewed change" — not "Ravi broke it".
