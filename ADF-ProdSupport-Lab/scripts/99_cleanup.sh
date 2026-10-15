#!/usr/bin/env bash
# Deletes EVERYTHING created by the lab (stops all cost).
source "$(dirname "$0")/00_variables.sh"
read -p "Delete resource group $RG and ALL resources in it? (yes/no) " a
[ "$a" = "yes" ] || exit 0
az group delete -n "$RG" --yes --no-wait
echo "Deletion started. Key Vault goes to soft-delete; purge if you want to reuse the name:"
echo "  az keyvault purge -n $KV -l $LOCATION"
