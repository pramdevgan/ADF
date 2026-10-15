# Cleanup & Cost Control

## Why cleanup is part of production-support training
Leftover lab resources = **cost incidents** and security exposure (public endpoints, stored passwords). Treat cleanup like a change: verify, execute, confirm.

## Steps (Portal)
1. ADF Studio → Manage → Triggers → **Stop** all triggers (prevents runs during deletion).
2. Portal → Monitor → Alerts → **Alert rules** → delete lab rules if they live outside the RG (they are normally in the RG).
3. Portal → Resource groups → `rg-adf-prodsupport-lab` → **Delete resource group** → type the name → Delete. (Deletes ADF, SQL, storage, KV, Log Analytics, action group, alert rules in that RG.)
4. Key Vault is **soft-deleted**: Key vaults → **Manage deleted vaults** → select → **Purge** (only if you need the name again; purge protection was disabled in setup).
5. Log Analytics workspace is soft-deleted for 14 days (recoverable) — no action needed.
6. Diagnostic setting for **subscription Activity Log** (if you created it) lives at subscription level: Monitor → Activity log → Export Activity Logs → delete it.
7. Service Health alert (if created in another RG) → delete.

CLI: `bash scripts/99_cleanup.sh`

## Cost notes (indicative; confirm with the Azure Pricing Calculator)
| Resource | Driver | Lab impact |
|---|---|---|
| Azure SQL Basic | hourly, always on | largest item; delete when done |
| ADF | per activity run + DIU-hours for Copy + pipeline orchestration | a few hundred runs ≈ very small |
| Storage | GB stored + transactions | negligible |
| Log Analytics | GB ingested | negligible at lab volume |
| Key Vault | per 10k operations | negligible |
