#!/usr/bin/env bash
# =====================================================================
# 00_variables.sh  -- source this first in Azure Cloud Shell (Bash)
#   source ./00_variables.sh
# Change INITIALS + DIGITS so every learner gets globally-unique names.
# =====================================================================
export INITIALS="vp"                 # <-- your initials, lowercase, 2-4 chars
export DIGITS="2026"                 # <-- any 4 digits (storage names must be globally unique)
export LOCATION="centralindia"

export RG="rg-adf-prodsupport-lab"
export ADF="adf-ps-${INITIALS}"
export ST="stadfps${INITIALS}${DIGITS}"        # 3-24 chars, lowercase+digits only
export SQLSRV="sql-adf-ps-${INITIALS}"
export SQLDB="sqldb-retail"
export SQLADMIN="sqladminuser"
export KV="kv-adf-ps-${INITIALS}"
export LAW="law-adf-ps"
export AG="ag-adf-ps-oncall"
export ONCALL_EMAIL="you@example.com"           # <-- your email for alerts

export SUB_ID=$(az account show --query id -o tsv)
export ME_OID=$(az ad signed-in-user show --query id -o tsv)
echo "Subscription : $SUB_ID"
echo "RG=$RG ADF=$ADF ST=$ST SQL=$SQLSRV/$SQLDB KV=$KV LAW=$LAW"
