# Root Cause Analysis (RCA) Report

| Field | Value |
|---|---|
| **Incident ID** | INC-___ |
| **Title** | (one line, e.g. "3 Oct orders not loaded – source file name changed") |
| **Date of incident** | |
| **Severity** | Sev 1 / Sev 2 / Sev 3 / Sev 4 |
| **Status** | Resolved / Monitoring / Open |
| **Author** | |
| **Reviewed by** | |
| **Systems affected** | (pipeline, tables, reports) |

---

## 1. Summary
*3–4 sentences a non-technical manager can understand: what happened, the impact, and how it was fixed.*

## 2. Impact
| Dimension | Detail |
|---|---|
| Data affected | (which date / tables / how many rows) |
| Business impact | (which report, wrong by how much ₹ / %, who noticed) |
| Duration | (from first bad state to resolution) |
| Users / teams affected | |
| Data loss? | Yes / No |

## 3. Timeline (IST)
| Time | Event | Source of evidence |
|---|---|---|
| | Last known good run | Monitor Run ID … |
| | Change / trigger event (what changed?) | Activity log / vendor email |
| | Failure occurred | Monitor |
| | **Detected** (alert / user report) | Alert email / ticket |
| | Investigation started | |
| | Root cause identified | |
| | Fix applied | |
| | **Resolved** – verified | SQL validation |

**MTTD** (detect − occur): ____ min  **MTTR** (resolve − detect): ____ min

## 4. Detection
How was it detected? (Alert / user complaint / validation check.) Could it have been detected earlier?

## 5. Investigation & Evidence
| Step | What I checked | Finding | Evidence (Run ID / error code / query result) |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

**Error details:**
- Pipeline / Activity:
- Error code / Failure type:
- Error message:

## 6. Root Cause
**Category:** Missing file / Connectivity / Authentication / Trigger / Data mapping / Data quality / Other

**Immediate (technical) cause:**

**5 Whys:**
1. Why …? →
2. Why …? →
3. Why …? →
4. Why …? →
5. Why …? →

**Root cause (process / design):**

**Contributing factors:**

## 7. Resolution
What was done to restore service? How was it verified (queries + results)?

## 8. Corrective & Preventive Actions (CAPA)
| # | Action | Type (Corrective / Preventive / Detective) | Owner | Due date | Status |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

## 9. Lessons Learned
- What went well:
- What went badly:
- Where we got lucky:

---
*Blameless review: this document describes system and process failures, not individual fault.*
