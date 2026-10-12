# 08 – Troubleshooting Guide

| Symptom / Error | Likely cause | Fix |
|---|---|---|
| Storage account / ADF name "already taken" | Names are global | Add digits to your initials |
| Linked service test: **"Key based authentication is not permitted on this storage account"** | *Allow storage account key access* disabled (org policy or setting) | Storage → Settings → Configuration → enable key access, **or** use Managed Identity + *Storage Blob Data Contributor* role |
| Test connection **403 AuthorizationPermissionMismatch** (managed identity) | RBAC role missing / not propagated | Assign *Storage Blob Data Contributor* to the factory; wait 5 min |
| SQL: **"Client with IP address … is not allowed to access the server"** | Firewall | SQL server → Networking → *Allow Azure services and resources to access this server* = Yes; add client IP for Query editor |
| SQL: **Login failed for user** | Wrong password / DB name | Re-enter credentials; database name is `sqldb-adflab`, server is just the name (ADF adds `.database.windows.net`) |
| Dataset **Preview data** fails "path does not exist" | Typo in container/folder/file, case-sensitive | Use the 📁 browse button |
| Copy error **ErrorCode=UserErrorInvalidColumnName / column not found** | Mapping refers to a column not in source | Mapping tab → **Clear** → **Import schemas** again |
| Copy error **"Failed to convert value 'ABC' to type Int32"** | Bad data in a typed sink | Fix data, or enable *Fault tolerance → Skip incompatible rows* |
| Duplicates in SQL after rerun | No pre-copy script | Add `TRUNCATE TABLE …` pre-copy script, or use Upsert |
| Expression error **"The expression … cannot be evaluated because property 'childItems' doesn't exist"** | *Child items* not added to Get Metadata field list, or activity name mismatch | Add field; names in `activity('…')` are case-sensitive and must match exactly |
| ForEach "Items must be an array" | Passed the whole output object | Use `.output.Value` (Filter) or `.output.childItems` (Get Metadata) |
| Execute Pipeline fails in triggered run "pipeline not found" | Child not published | Publish all |
| Trigger doesn't fire | Not published / not started / start time in past with no recurrence | Publish; Manage → Triggers → Start |
| Storage event trigger can't be created | Event Grid provider not registered | Subscription → Resource providers → Microsoft.EventGrid → Register |
| Work disappeared after closing browser | Live mode without Publish | Always **Publish all**; consider Git integration |
| Debug run pops "Parameter value required" | Parameter without default | Provide value in the dialog or set a default |
| Copy is slow | Small DIU / many tiny files | Settings → DIU; merge small files; increase parallel copies |

### Where to look for details
1. Monitor → run → activity → **Error** icon (message + error code + failure type: UserError / SystemError).
2. Activity **Input** – confirm expressions resolved to the values you expected.
3. Activity **Output** / **Details** (copy) – rows read/copied/skipped, throughput, which stage was slow.
