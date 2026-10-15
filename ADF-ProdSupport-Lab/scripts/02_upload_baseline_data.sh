#!/usr/bin/env bash
# Upload the GOOD baseline files to ADLS landing zone.
# Run from the lab package root in Cloud Shell (upload the zip to Cloud Shell first and unzip).
set -euo pipefail
source "$(dirname "$0")/00_variables.sh"
up () { az storage blob upload --account-name "$ST" --auth-mode login -c landing -n "$2" -f "$1" --overwrite -o none && echo "uploaded $2"; }

up data/good/customers_20261013.csv customers/customers_20261013.csv
up data/good/customers_20261014.csv customers/customers_20261014.csv
up data/good/sales_20261013.csv     sales/sales_20261013.csv
up data/good/sales_20261014.csv     sales/sales_20261014.csv
az storage blob list --account-name "$ST" --auth-mode login -c landing --query "[].name" -o tsv
