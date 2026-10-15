import json, os
# Regenerates all ADF JSON in ../adf  ->  run: python scripts/generate_adf_json.py
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "adf"))
def save(folder, obj):
    with open(f"{folder}/{obj['name']}.json","w") as f: json.dump(obj,f,indent=4)
E = lambda v: {"value": v, "type": "Expression"}
def spparam(v, t="String", expr=True): return {"value": E(v) if expr else v, "type": t}
LS_SQL = {"referenceName":"LS_AzureSql","type":"LinkedServiceReference"}
def dep(a, cond="Succeeded"): return {"activity": a, "dependencyConditions": cond if isinstance(cond,list) else [cond]}
def pol(timeout="0.00:10:00", retry=2, interval=60):
    return {"timeout":timeout,"retry":retry,"retryIntervalInSeconds":interval,"secureOutput":False,"secureInput":False}

# ---------------- Linked services ----------------
save("linkedService", {"name":"LS_KeyVault","properties":{"type":"AzureKeyVault","description":"Secrets store. ADF system-assigned managed identity needs 'Key Vault Secrets User' role.","typeProperties":{"baseUrl":"https://kv-adf-ps-<initials>.vault.azure.net/"}}})
save("linkedService", {"name":"LS_ADLS","properties":{"type":"AzureBlobFS","description":"ADLS Gen2 landing zone. Auth = system-assigned managed identity (no URL credential = MI). Needs 'Storage Blob Data Contributor' on the storage account.","typeProperties":{"url":"https://stadfps<initials><digits>.dfs.core.windows.net/"},"connectVia":{"referenceName":"AutoResolveIntegrationRuntime","type":"IntegrationRuntimeReference"}}})
save("linkedService", {"name":"LS_AzureSql","properties":{"type":"AzureSqlDatabase","description":"Azure SQL DB. SQL auth user 'adfloader'; password pulled at runtime from Key Vault.","typeProperties":{
    "server":"sql-adf-ps-<initials>.database.windows.net","database":"sqldb-retail","encrypt":"mandatory","trustServerCertificate":False,
    "authenticationType":"SQL","userName":"adfloader",
    "password":{"type":"AzureKeyVaultSecret","store":{"referenceName":"LS_KeyVault","type":"LinkedServiceReference"},"secretName":"sql-adfloader-password"}},
    "connectVia":{"referenceName":"AutoResolveIntegrationRuntime","type":"IntegrationRuntimeReference"}}})

# ---------------- Datasets ----------------
save("dataset", {"name":"DS_ADLS_Csv","properties":{"description":"Generic parameterised CSV on ADLS Gen2","linkedServiceName":{"referenceName":"LS_ADLS","type":"LinkedServiceReference"},
  "parameters":{"pContainer":{"type":"string"},"pFolder":{"type":"string"},"pFileName":{"type":"string"}},
  "type":"DelimitedText","typeProperties":{"location":{"type":"AzureBlobFSLocation","fileName":E("@dataset().pFileName"),"folderPath":E("@dataset().pFolder"),"fileSystem":E("@dataset().pContainer")},
  "columnDelimiter":",","escapeChar":"\\","firstRowAsHeader":True,"quoteChar":"\""},"schema":[]}})
save("dataset", {"name":"DS_AzureSql_Table","properties":{"description":"Generic parameterised Azure SQL table","linkedServiceName":LS_SQL,
  "parameters":{"pSchema":{"type":"string"},"pTable":{"type":"string"}},
  "type":"AzureSqlTable","typeProperties":{"schema":E("@dataset().pSchema"),"table":E("@dataset().pTable")},"schema":[]}})

# ---------------- helpers ----------------
def sp(name, proc, params, deps=None, policy=None):
    return {"name":name,"type":"SqlServerStoredProcedure","dependsOn":deps or [],"policy":policy or pol(),"userProperties":[],
            "linkedServiceName":LS_SQL,"typeProperties":{"storedProcedureName":proc,"storedProcedureParameters":params}}
def log_start(): return sp("SP_LogStart","[ops].[usp_LogRunStart]",{
    "RunId":spparam("@pipeline().RunId"),"PipelineName":spparam("@pipeline().Pipeline"),
    "TriggerName":spparam("@pipeline().TriggerName"),"RunDate":spparam("@pipeline().parameters.pRunDate")})
def log_fail(name, failed_act, code, deps, msg_expr):
    return sp(name,"[ops].[usp_LogRunEnd]",{
        "RunId":spparam("@pipeline().RunId"),"Status":{"value":"Failed","type":"String"},
        "FailedActivity":{"value":failed_act,"type":"String"},"ErrorCode":{"value":code,"type":"String"},
        "ErrorMessage":spparam(msg_expr),
        "PipelineName":spparam("@pipeline().Pipeline"),"RunDate":spparam("@pipeline().parameters.pRunDate")}, deps)
def fail(name, msg_expr, code, deps):
    return {"name":name,"type":"Fail","dependsOn":deps,"userProperties":[],"typeProperties":{"message":E(msg_expr),"errorCode":code}}
def copy(name, folder, fileprefix, table, mappings, deps):
    return {"name":name,"type":"Copy","dependsOn":deps,"policy":pol("0.01:00:00",0,30),"userProperties":[],
      "typeProperties":{
        "source":{"type":"DelimitedTextSource","storeSettings":{"type":"AzureBlobFSReadSettings","recursive":False,"enablePartitionDiscovery":False},
                  "formatSettings":{"type":"DelimitedTextReadSettings"}},
        "sink":{"type":"AzureSqlSink","preCopyScript":f"TRUNCATE TABLE stg.{table}","writeBehavior":"insert","sqlWriterUseTableLock":False,"disableMetricsCollection":False},
        "enableStaging":False,
        "translator":{"type":"TabularTranslator","mappings":[{"source":{"name":s},"sink":{"name":t}} for s,t in mappings],
                      "typeConversion":True,"typeConversionSettings":{"allowDataTruncation":False,"treatBooleanAsNumber":False}}},
      "inputs":[{"referenceName":"DS_ADLS_Csv","type":"DatasetReference","parameters":{"pContainer":"landing","pFolder":folder,
                 "pFileName":E(f"@concat('{fileprefix}_', pipeline().parameters.pRunDate, '.csv')")}}],
      "outputs":[{"referenceName":"DS_AzureSql_Table","type":"DatasetReference","parameters":{"pSchema":"stg","pTable":table}}]}

# ---------------- PL_Ingest_Sales ----------------
sales_map=[("order_id","OrderId"),("order_date","OrderDate"),("customer_id","CustomerId"),("product_id","ProductId"),
           ("quantity","Quantity"),("unit_price","UnitPrice"),("amount","Amount"),("store_code","StoreCode")]
acts=[log_start(),
 copy("Copy_Sales_To_Stg","sales","sales","Sales",sales_map,[dep("SP_LogStart")]),
 sp("SP_Load_FactSales","[dbo].[usp_Load_Sales]",{"RunDate":spparam("@pipeline().parameters.pRunDate"),"RunId":spparam("@pipeline().RunId")},[dep("Copy_Sales_To_Stg")]),
 sp("SP_LogSuccess","[ops].[usp_LogRunEnd]",{"RunId":spparam("@pipeline().RunId"),"Status":{"value":"Succeeded","type":"String"},"PipelineName":spparam("@pipeline().Pipeline"),"RunDate":spparam("@pipeline().parameters.pRunDate"),
     "RowsRead":spparam("@activity('Copy_Sales_To_Stg').output.rowsRead","Int64"),
     "RowsWritten":spparam("@activity('Copy_Sales_To_Stg').output.rowsCopied","Int64")},[dep("SP_Load_FactSales")]),
 log_fail("SP_LogFailure_Copy","Copy_Sales_To_Stg","ERR_COPY_SALES",[dep("Copy_Sales_To_Stg","Failed")],"@activity('Copy_Sales_To_Stg').error.message"),
 fail("Fail_Copy","@concat('Copy_Sales_To_Stg failed: ', activity('Copy_Sales_To_Stg').error.message)","ERR_COPY_SALES",[dep("SP_LogFailure_Copy",["Succeeded","Failed"])]),
 log_fail("SP_LogFailure_Load","SP_Load_FactSales","ERR_LOAD_SALES",[dep("SP_Load_FactSales","Failed")],"@activity('SP_Load_FactSales').error.message"),
 fail("Fail_Load","@concat('SP_Load_FactSales failed: ', activity('SP_Load_FactSales').error.message)","ERR_LOAD_SALES",[dep("SP_LogFailure_Load",["Succeeded","Failed"])]),
]
save("pipeline",{"name":"PL_Ingest_Sales","properties":{"description":"Child: landing/sales/sales_<pRunDate>.csv -> stg.Sales -> dbo.FactSales (idempotent). Logs start/end and raises incident on failure.",
  "activities":acts,"parameters":{"pRunDate":{"type":"string","defaultValue":"20261014"}},"folder":{"name":"Ingest"},"annotations":["prod-support-lab"]}})

# ---------------- PL_Ingest_Customers ----------------
cust_map=[("customer_id","CustomerId"),("customer_name","CustomerName"),("city","City"),("segment","Segment"),("signup_date","SignupDate")]
acts=[log_start(),
 copy("Copy_Customers_To_Stg","customers","customers","Customers",cust_map,[dep("SP_LogStart")]),
 sp("SP_Load_DimCustomer","[dbo].[usp_Load_Customers]",{"RunId":spparam("@pipeline().RunId")},[dep("Copy_Customers_To_Stg")]),
 sp("SP_LogSuccess","[ops].[usp_LogRunEnd]",{"RunId":spparam("@pipeline().RunId"),"Status":{"value":"Succeeded","type":"String"},"PipelineName":spparam("@pipeline().Pipeline"),"RunDate":spparam("@pipeline().parameters.pRunDate"),
     "RowsRead":spparam("@activity('Copy_Customers_To_Stg').output.rowsRead","Int64"),
     "RowsWritten":spparam("@activity('Copy_Customers_To_Stg').output.rowsCopied","Int64")},[dep("SP_Load_DimCustomer")]),
 log_fail("SP_LogFailure_Copy","Copy_Customers_To_Stg","ERR_COPY_CUSTOMERS",[dep("Copy_Customers_To_Stg","Failed")],"@activity('Copy_Customers_To_Stg').error.message"),
 fail("Fail_Copy","@concat('Copy_Customers_To_Stg failed: ', activity('Copy_Customers_To_Stg').error.message)","ERR_COPY_CUSTOMERS",[dep("SP_LogFailure_Copy",["Succeeded","Failed"])]),
 log_fail("SP_LogFailure_Load","SP_Load_DimCustomer","ERR_LOAD_CUSTOMERS",[dep("SP_Load_DimCustomer","Failed")],"@activity('SP_Load_DimCustomer').error.message"),
 fail("Fail_Load","@concat('SP_Load_DimCustomer failed: ', activity('SP_Load_DimCustomer').error.message)","ERR_LOAD_CUSTOMERS",[dep("SP_LogFailure_Load",["Succeeded","Failed"])]),
]
save("pipeline",{"name":"PL_Ingest_Customers","properties":{"description":"Child: landing/customers/customers_<pRunDate>.csv -> stg.Customers -> dbo.DimCustomer (MERGE).",
  "activities":acts,"parameters":{"pRunDate":{"type":"string","defaultValue":"20261014"}},"folder":{"name":"Ingest"},"annotations":["prod-support-lab"]}})

# ---------------- PL_Master_Daily ----------------
def execp(name, child, deps):
    return {"name":name,"type":"ExecutePipeline","dependsOn":deps,"policy":{"secureInput":False},"userProperties":[],
            "typeProperties":{"pipeline":{"referenceName":child,"type":"PipelineReference"},"waitOnCompletion":True,
                              "parameters":{"pRunDate":E("@pipeline().parameters.pRunDate")}}}
acts=[log_start(),
 execp("Exec_Ingest_Customers","PL_Ingest_Customers",[dep("SP_LogStart")]),
 execp("Exec_Ingest_Sales","PL_Ingest_Sales",[dep("Exec_Ingest_Customers")]),
 sp("SP_Build_Report","[rpt].[usp_Build_DailySalesSummary]",{"RunDate":spparam("@pipeline().parameters.pRunDate"),"RunId":spparam("@pipeline().RunId")},[dep("Exec_Ingest_Sales")]),
 sp("SP_LogSuccess","[ops].[usp_LogRunEnd]",{"RunId":spparam("@pipeline().RunId"),"Status":{"value":"Succeeded","type":"String"},"PipelineName":spparam("@pipeline().Pipeline"),"RunDate":spparam("@pipeline().parameters.pRunDate")},[dep("SP_Build_Report")]),
 # generic error handler: Upon Failure OR Upon Skip of the LAST step catches a failure anywhere in the chain
 log_fail("SP_LogFailure_Master","see child run / Monitor","ERR_MASTER",[dep("SP_Build_Report",["Failed","Skipped"])],
          "@concat('Daily master load failed for business date ', pipeline().parameters.pRunDate, '. Drill into child pipeline runs in ADF Monitor. Master RunId=', pipeline().RunId)"),
 fail("Fail_Master","@concat('PL_Master_Daily failed for ', pipeline().parameters.pRunDate, ' - see child run')","ERR_MASTER",[dep("SP_LogFailure_Master",["Succeeded","Failed"])]),
]
save("pipeline",{"name":"PL_Master_Daily","properties":{"description":"Orchestrator: customers -> sales -> report. Generic error handler (Upon Failure + Upon Skip on last activity).",
  "activities":acts,"parameters":{"pRunDate":{"type":"string","defaultValue":"20261014"}},"folder":{"name":"Orchestration"},"annotations":["prod-support-lab"]}})

# ---------------- PL_HealthCheck ----------------
acts=[
 {"name":"Lookup_RunHealthChecks","type":"Lookup","dependsOn":[],"policy":pol("0.00:10:00",2,60),"userProperties":[],
  "typeProperties":{"source":{"type":"AzureSqlSource","sqlReaderStoredProcedureName":"[ops].[usp_RunHealthChecks]",
     "storedProcedureParameters":{"RunDate":{"type":"String","value":E("@pipeline().parameters.pRunDate")}},
     "queryTimeout":"00:10:00","partitionOption":"None"},
   "dataset":{"referenceName":"DS_AzureSql_Table","type":"DatasetReference","parameters":{"pSchema":"ops","pTable":"HealthCheckResult"}},
   "firstRowOnly":True}},
 {"name":"If_AnyCheckFailed","type":"IfCondition","dependsOn":[dep("Lookup_RunHealthChecks")],"userProperties":[],
  "typeProperties":{"expression":E("@greater(int(activity('Lookup_RunHealthChecks').output.firstRow.FailCount), 0)"),
   "ifTrueActivities":[fail("Fail_HealthCheck",
      "@concat('Health check FAILED for ', pipeline().parameters.pRunDate, ': ', string(activity('Lookup_RunHealthChecks').output.firstRow.FailCount), ' check(s) failed. CheckRunId=', activity('Lookup_RunHealthChecks').output.firstRow.CheckRunId, '. Query ops.HealthCheckResult.')",
      "ERR_HEALTHCHECK",[])]}}
]
save("pipeline",{"name":"PL_HealthCheck","properties":{"description":"Runs ops.usp_RunHealthChecks; fails (=> Azure Monitor alert) when any check FAILs.",
  "activities":acts,"parameters":{"pRunDate":{"type":"string","defaultValue":"20261014"}},"folder":{"name":"Operations"},"annotations":["prod-support-lab"]}})

# ---------------- Triggers ----------------
yday="@formatDateTime(addDays(convertFromUtc(trigger().scheduledTime, 'India Standard Time'), -1), 'yyyyMMdd')"
save("trigger",{"name":"TR_Daily_0200_IST","properties":{"description":"Runs master load daily 02:00 IST for previous business date.","annotations":[],
  "pipelines":[{"pipelineReference":{"referenceName":"PL_Master_Daily","type":"PipelineReference"},"parameters":{"pRunDate":yday}}],
  "type":"ScheduleTrigger","typeProperties":{"recurrence":{"frequency":"Day","interval":1,"startTime":"2026-12-01T02:00:00","timeZone":"India Standard Time",
   "schedule":{"hours":[2],"minutes":[0]}}}}})
save("trigger",{"name":"TR_Hourly_HealthCheck","properties":{"description":"Hourly health check of previous business date.","annotations":[],
  "pipelines":[{"pipelineReference":{"referenceName":"PL_HealthCheck","type":"PipelineReference"},"parameters":{"pRunDate":yday}}],
  "type":"ScheduleTrigger","typeProperties":{"recurrence":{"frequency":"Hour","interval":1,"startTime":"2026-12-01T03:15:00","timeZone":"India Standard Time"}}}})
print("ok")
