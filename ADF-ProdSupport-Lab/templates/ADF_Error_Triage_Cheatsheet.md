# ADF Error Triage Cheat-sheet

> Exact error wording changes between connector versions — match on **key words**, and always paste the full text into the ticket.

## Where to find the error
| Place | Path | Best for |
|---|---|---|
| ADF Monitor | Monitor → Pipeline runs → run → activity → **Error** / **Output** icons | First look, Copy details (rows, throughput) |
| Execute Pipeline output | parent run → Exec activity → Output → `pipelineRunId` | jump to child run |
| Log Analytics | `ADFActivityRun` (K2, K3) | search across runs, history > 45 days |
| Our log | `ops.PipelineRunLog`, `ops.Incident` | business date, row counts, ticket |
| SQL errors | message text of SP activity | DQ_* business errors from THROW |

## Common errors
| Keyword(s) in message | Activity | Root-cause class | First action |
|---|---|---|---|
| `PathNotFound`, `does not exist`, `BlobNotFound` | Copy / Get Metadata | Missing/late file, wrong path/param | Check landing folder; check pRunDate |
| `AuthorizationPermissionMismatch`, `403`, `not authorized` | Copy, Get Metadata | RBAC / ACL / firewall | IAM role assignments; storage networking |
| `Login failed for user` | SP / Copy / Lookup to SQL | Wrong password / user dropped | Test connection; KV secret versions |
| `Cannot connect to SQL Database`, `firewall`, `Client with IP address` | SQL | Firewall/network | SQL server Networking: allow Azure services |
| `40613`, `not currently available`, `timeout` | SQL | Transient / scaling / serverless resume | Retry policy; rerun once |
| `TypeConversionFailure`, `cannot convert`, `Input string was not in a correct format` | Copy | Bad data values | Inspect rows; request clean file |
| column `not found` / mapping / `ColumnNameNotFound` | Copy | Source schema drift | Diff header vs yesterday |
| `String or binary data would be truncated` | Copy / SP | Value too long for column | Inspect data; schema change needs CHG |
| `Violation of PRIMARY KEY` / `UNIQUE KEY` | Copy / SP | Duplicate data / non-idempotent load | Check duplicates, idempotency |
| `DQ_*` (50001–50012) | SP | Our business validation | See runbook table |
| `Key Vault`, `Forbidden`, `secret` | Linked service resolution | KV RBAC / firewall / secret name | KV IAM; secret exists & enabled |
| `The integration runtime … is offline`/`unavailable` | Any via SHIR | Self-hosted IR down | Monitor → Integration runtimes; restart IR service/VM |
| `Operation on target … failed` (wrapper) | Execute Pipeline / If / ForEach | Inner activity failed | Drill into the inner/child run |
| `Activity failed because an inner activity failed` | ForEach/If/Until | Inner failure | Expand container activity |
| Fail activity code (`ERR_*`) | Fail | Raised on purpose by our handler | Read message → original activity error |

## FailureType (in Monitor & logs)
- **UserError** – config/data/permission issue on our side (most incidents).
- **SystemError** – service-side problem → check Service Health; retry; Microsoft support if persistent.
- **Cancelled** – someone/something cancelled the run (timeout or user).

## Info to collect before opening a Microsoft support case
Factory name, region, pipeline + activity name, **RunId / activity RunId**, timestamp **UTC**, full error, IR type, what changed, repro steps.
