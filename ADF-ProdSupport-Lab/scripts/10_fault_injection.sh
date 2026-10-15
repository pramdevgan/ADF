#!/usr/bin/env bash
# =====================================================================
# 10_fault_injection.sh   (INSTRUCTOR / "chaos" script)
# Usage:  bash scripts/10_fault_injection.sh <scenario> [inject|fix]
#   S1  missing source file          (sales_20261016.csv never arrives)
#   S2  bad data types in file
#   S3  empty file
#   S4  ADF loses storage permission (RBAC removed)
#   S5  wrong SQL password in Key Vault (bad secret rotation)
#   S6  non-idempotent hotfix  -> run sql/90 (inject) / sql/91 (fix) in Query editor
#   S6b duplicate keys inside file
#   S7  trigger stopped (silent SLA breach)
#   E2E end-to-end exercise files for 20261015 (stage1|stage2|stage3)
# Everything an instructor does to "break" prod is reversible with 'fix'.
# =====================================================================
set -euo pipefail
source "$(dirname "$0")/00_variables.sh"
SC=${1:?scenario}; MODE=${2:-inject}
up () { az storage blob upload --account-name "$ST" --auth-mode login -c landing -n "$2" -f "$1" --overwrite -o none && echo "uploaded $1 -> landing/$2"; }
rm_blob () { az storage blob delete --account-name "$ST" --auth-mode login -c landing -n "$1" -o none 2>/dev/null && echo "deleted landing/$1" || echo "landing/$1 not present"; }
ST_ID=$(az storage account show -n "$ST" -g "$RG" --query id -o tsv)
ADF_MI=$(az datafactory show -g "$RG" -n "$ADF" --query identity.principalId -o tsv)

case "$SC:$MODE" in
  S1:inject) rm_blob sales/sales_20261016.csv; echo "Now run PL_Ingest_Sales with pRunDate=20261016";;
  S1:fix)    echo "Late files 'arrive':"; up data/fault_injection/S1_late_sales_20261016.csv sales/sales_20261016.csv; up data/fault_injection/S1_late_customers_20261016.csv customers/customers_20261016.csv;;

  S2:inject) up data/fault_injection/S2_sales_20261014_badtypes.csv sales/sales_20261014.csv;;
  S2:fix)    up data/corrected/sales_20261014.csv sales/sales_20261014.csv;;

  S3:inject) up data/fault_injection/S3_sales_20261014_empty.csv sales/sales_20261014.csv;;
  S3:fix)    up data/corrected/sales_20261014.csv sales/sales_20261014.csv;;

  S4:inject) az role assignment delete --assignee "$ADF_MI" --role "Storage Blob Data Contributor" --scope "$ST_ID" && echo "RBAC removed (allow up to ~5-10 min to take effect)";;
  S4:fix)    az role assignment create --assignee-object-id "$ADF_MI" --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope "$ST_ID" -o none && echo "RBAC restored (allow up to ~5-10 min)";;

  S5:inject) az keyvault secret set --vault-name "$KV" -n sql-adfloader-password --value "Wr0ng#Rotated!Pwd" -o none && echo "Secret rotated to WRONG value (new version created)";;
  S5:fix)    read -s -p "Enter the CORRECT adfloader password: " P; echo; az keyvault secret set --vault-name "$KV" -n sql-adfloader-password --value "$P" -o none && echo "Correct secret version created";;

  S6b:inject) up data/fault_injection/S6b_sales_20261014_duplicates.csv sales/sales_20261014.csv;;
  S6b:fix)    up data/corrected/sales_20261014.csv sales/sales_20261014.csv;;

  S7:inject) up data/fault_injection/S7_sales_20261017.csv sales/sales_20261017.csv; up data/fault_injection/S7_customers_20261017.csv customers/customers_20261017.csv
             az datafactory trigger stop -g "$RG" --factory-name "$ADF" -n TR_Daily_0200_IST && echo "Files for 20261017 arrived on time, but trigger STOPPED";;
  S7:fix)    az datafactory trigger start -g "$RG" --factory-name "$ADF" -n TR_Daily_0200_IST && echo "Trigger STARTED";;

  E2E:stage1) up data/e2e/sales_20261015.csv sales/sales_20261015.csv; up data/e2e/customers_20261015.csv customers/customers_20261015.csv;;
  E2E:stage2) up data/e2e/customers_20261015_resend1.csv customers/customers_20261015.csv;;
  E2E:stage3) up data/corrected/customers_20261015.csv customers/customers_20261015.csv;;

  *) echo "unknown combo $SC $MODE"; exit 1;;
esac
