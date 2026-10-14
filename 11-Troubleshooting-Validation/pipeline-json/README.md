# Module 3 – reference JSON

Use only if stuck: open the object in ADF Studio → `{ }` (Code) → paste → OK → Publish all.
Create in this order: datasets → pipeline → trigger.
Requires existing linked services `LS_BlobStorage` and `LS_AzureSqlDb` (Module 1).

| File | Object |
|---|---|
| dataset_DS_Orders_Csv.json | Parameterized CSV in input/orders/ |
| dataset_DS_Sql_Stg_Orders.json | stg.Orders table |
| pipeline_PL_20_Daily_Orders_Load.json | The full daily load with validation gate |
| trigger_TR_Daily_Orders_BROKEN.json | Incident 4 – the faulty trigger (wrong date format, Stopped) |
| trigger_TR_Daily_Orders_FIXED.json | Incident 4 – corrected trigger |

Note: the trigger `startTime` is a sample — when you create it in the UI, set the start time to now.
