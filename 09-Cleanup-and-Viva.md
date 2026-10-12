# 09 – Cleanup & Viva Questions

## Cleanup (5 min) – do this to stop charges

1. ADF Studio → Manage → **Triggers** → Stop every started trigger → **Publish all**.
2. Azure portal → **Resource groups** → `rg-adf-lab` → **Delete resource group** → type the name → **Delete**.
   This removes ADF, storage, SQL server/DB together.
3. (If you created Event Grid system topics, they are inside the RG and get deleted too.)

---

## Lab record – what you should be able to show

- [ ] Storage account with `input`, `output`, `archive` containers
- [ ] Linked services: `LS_BlobStorage` (+ `LS_AzureSqlDb`)
- [ ] Datasets: CSV, JSON, Binary folder, parameterized CSV (+ SQL)
- [ ] `PL_01` simple copy – Debug + Triggered run succeeded
- [ ] `PL_02` Get Metadata → Filter → ForEach → Copy – 3 files in archive
- [ ] `PL_03` Blob → SQL with success/failure logging
- [ ] `PL_04` execution-flow demo run with `p_ForceFail` true and false
- [ ] Screenshot of Monitor → Activity runs (Gantt view)

---

## Viva / Quiz questions (with answers)

1. **What is the difference between a linked service and a dataset?**
   Linked service = connection information (where + how to authenticate). Dataset = a named reference to specific data (file/table + format) inside that linked service.

2. **What is an Integration Runtime? Name the three types.**
   Compute infrastructure that executes activities/data movement. Azure IR, Self-hosted IR, Azure-SSIS IR.

3. **When would you need a Self-hosted IR?**
   When the source/sink is on-premises or in a private network not reachable from Azure's public endpoints.

4. **Difference between Debug and Trigger now?**
   Debug runs the current (possibly unpublished) canvas for testing; Trigger now runs the published version and appears as a triggered run.

5. **Pipeline parameter vs variable?**
   Parameter: supplied at run start, read-only. Variable: can be changed during the run with Set/Append variable.

6. **What are the four dependency conditions?**
   Upon Success, Upon Failure, Upon Completion, Upon Skip.

7. **Copy fails and the only failure-path activity succeeds – what is the pipeline status?**
   Succeeded (Try-Catch pattern). If there is also a success-path activity that got skipped, the pipeline is Failed (Do-If-Else).

8. **Why use a pre-copy script like TRUNCATE?**
   To make the load idempotent – reruns don't create duplicates.

9. **What does Get Metadata with "Child items" return?**
   An array of objects `{name, type}` for every file/folder inside the folder.

10. **What is `@item()`?**
    The current element in a ForEach (or Filter) iteration.

11. **What is a DIU?**
    Data Integration Unit – measure of compute power used by a Copy activity on Azure IR; affects speed and cost.

12. **Schedule vs Tumbling window trigger?**
    Schedule fires at clock times (many-to-many with pipelines). Tumbling window processes fixed contiguous time windows, supports backfill, retries and window dependencies; one-to-one with a pipeline.

13. **How do you trigger a pipeline when a file arrives?**
    Storage event trigger (Blob created) – requires the Microsoft.EventGrid resource provider.

14. **How long is run history kept and how to keep it longer?**
    45 days; send diagnostic logs to Log Analytics / Storage.

15. **Why is Managed Identity preferred over account keys?**
    No secrets to store/rotate; access controlled by Azure RBAC.

16. **What does "Wait on completion" in Execute Pipeline do?**
    Parent waits for the child run to finish and takes its result; otherwise the parent continues immediately.

17. **ETL vs ELT – where does ADF fit?**
    Both: Copy activity loads raw data (ELT), Mapping Data Flows transform on Spark (ETL), or it orchestrates transformations in SQL/Databricks/Synapse.

18. **What does "Publish all" do in live mode?**
    Saves and deploys all changes to the ADF service; triggers only run published pipelines.
