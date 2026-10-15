#!/usr/bin/env bash
# =====================================================================
# 01_provision_cli_OPTIONAL.sh
# OPTIONAL fast path. The lab guide (02_Lab_Environment_Setup.md) does every
# step in the Azure PORTAL so you learn what each blade does. Use this script
# only if you are short on time or re-building the lab.
# Run in Azure Cloud Shell (Bash):  source ./00_variables.sh && bash ./01_provision_cli_OPTIONAL.sh
# =====================================================================
set -euo pipefail
source "$(dirname "$0")/00_variables.sh"

read -s -p "Choose SQL ADMIN password (server admin): " SQLADMINPWD; echo
read -s -p "Choose password for SQL user 'adfloader' (goes to Key Vault): " ADFLOADERPWD; echo

echo "== 1. Resource group"
az group create -n "$RG" -l "$LOCATION" -o none

echo "== 2. ADLS Gen2 storage (hierarchical namespace ON)"
az storage account create -n "$ST" -g "$RG" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 \
  --hns true --min-tls-version TLS1_2 --allow-blob-public-access false -o none
ST_ID=$(az storage account show -n "$ST" -g "$RG" --query id -o tsv)
# you (the learner) need data-plane rights to upload files with --auth-mode login
az role assignment create --assignee "$ME_OID" --role "Storage Blob Data Contributor" --scope "$ST_ID" -o none || true
sleep 30   # RBAC propagation
for c in landing archive rejected; do
  az storage container create --account-name "$ST" -n "$c" --auth-mode login -o none
done

echo "== 3. Azure SQL server + database"
az sql server create -n "$SQLSRV" -g "$RG" -l "$LOCATION" -u "$SQLADMIN" -p "$SQLADMINPWD" -o none
az sql server firewall-rule create -g "$RG" -s "$SQLSRV" -n AllowAzureServices \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none
MYIP=$(curl -s https://api.ipify.org || true)
[ -n "$MYIP" ] && az sql server firewall-rule create -g "$RG" -s "$SQLSRV" -n ClientIP \
  --start-ip-address "$MYIP" --end-ip-address "$MYIP" -o none || true
az sql db create -g "$RG" -s "$SQLSRV" -n "$SQLDB" --service-objective Basic --backup-storage-redundancy Local -o none

echo "== 4. Key Vault (RBAC permission model)"
az keyvault create -n "$KV" -g "$RG" -l "$LOCATION" --enable-rbac-authorization true -o none
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)
az role assignment create --assignee "$ME_OID" --role "Key Vault Secrets Officer" --scope "$KV_ID" -o none || true
sleep 30
az keyvault secret set --vault-name "$KV" -n sql-adfloader-password --value "$ADFLOADERPWD" -o none

echo "== 5. Log Analytics workspace"
az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOCATION" -o none
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)

echo "== 6. Data Factory with system-assigned managed identity"
az extension add --name datafactory --upgrade -y -o none
az datafactory create -g "$RG" -n "$ADF" -l "$LOCATION" -o none
ADF_ID=$(az datafactory show -g "$RG" -n "$ADF" --query id -o tsv)
ADF_MI=$(az datafactory show -g "$RG" -n "$ADF" --query identity.principalId -o tsv)

echo "== 7. RBAC for ADF managed identity"
az role assignment create --assignee-object-id "$ADF_MI" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$ST_ID" -o none
az role assignment create --assignee-object-id "$ADF_MI" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$KV_ID" -o none

echo "== 8. Diagnostic settings -> Log Analytics (resource-specific tables)"
az monitor diagnostic-settings create -n diag-adf-to-law --resource "$ADF_ID" --workspace "$LAW_ID" \
  --export-to-resource-specific true \
  --logs '[{"category":"PipelineRuns","enabled":true},{"category":"ActivityRuns","enabled":true},{"category":"TriggerRuns","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' -o none
az monitor diagnostic-settings create -n diag-kv-to-law --resource "$KV_ID" --workspace "$LAW_ID" \
  --logs '[{"category":"AuditEvent","enabled":true}]' -o none

echo "== 9. Action group + metric alert on failed pipeline runs"
az monitor action-group create -g "$RG" -n "$AG" --short-name adfoncall \
  --action email oncall "$ONCALL_EMAIL" -o none
az monitor metrics alert create -g "$RG" -n "alert-adf-pipeline-failed" --scopes "$ADF_ID" \
  --condition "total PipelineFailedRuns > 0" --window-size 5m --evaluation-frequency 1m \
  --severity 2 --action "$AG" --description "Any ADF pipeline run failed" -o none

echo
echo "DONE. Next (manual, see guide):"
echo " a) Query editor: run sql/00 (use the SAME adfloader password), then 01..04"
echo " b) ADF Studio: create linked services/datasets/pipelines (or paste JSON from adf/)"
echo " c) Upload data with 02_upload_baseline_data.sh"
