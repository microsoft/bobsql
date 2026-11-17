#!/usr/bin/env bash
# Create a serverless Hyperscale named replica for the configured primary database.
#
# A named replica shares the primary's storage. No data is copied, the corpus stays in
# one place, and the replica is read-only and sized independently. Because storage is
# shared, the vector index the team builds on the primary shows up here automatically.

set -euo pipefail

: "${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"
: "${AZURE_RESOURCE_GROUP:?Set AZURE_RESOURCE_GROUP}"
: "${AZURE_SQL_SERVER_NAME:?Set AZURE_SQL_SERVER_NAME}"
: "${AZURE_SQL_PRIMARY_DATABASE:?Set AZURE_SQL_PRIMARY_DATABASE}"

AZURE_SQL_REPLICA_DATABASE="${AZURE_SQL_REPLICA_DATABASE:-${AZURE_SQL_PRIMARY_DATABASE}-replica}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"
REPLICA_CAPACITY="${REPLICA_CAPACITY:-8}"
REPLICA_MIN_CAPACITY="${REPLICA_MIN_CAPACITY:-1}"
payload_file="$(mktemp)"
trap 'rm -f "$payload_file"' EXIT

# az sql db replica create cannot make a serverless named replica: it demands -e for a
# serverless SKU and then rejects -e as an unrecognised argument. ARM takes it directly.
cat > "$payload_file" <<EOF
{
  "location": "${AZURE_LOCATION}",
  "sku": { "name": "HS_S_Gen5", "tier": "Hyperscale", "family": "Gen5", "capacity": ${REPLICA_CAPACITY} },
  "properties": {
    "createMode": "Secondary",
    "secondaryType": "Named",
    "sourceDatabaseId": "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Sql/servers/${AZURE_SQL_SERVER_NAME}/databases/${AZURE_SQL_PRIMARY_DATABASE}",
    "minCapacity": ${REPLICA_MIN_CAPACITY},
    "autoPauseDelay": 60
  }
}
EOF

az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Sql/servers/${AZURE_SQL_SERVER_NAME}/databases/${AZURE_SQL_REPLICA_DATABASE}?api-version=2023-08-01-preview" \
  --body "@${payload_file}" \
  --headers Content-Type=application/json -o json

az sql db show --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --server "$AZURE_SQL_SERVER_NAME" \
  --name "$AZURE_SQL_REPLICA_DATABASE" \
  --query '{name:name,status:status,objective:currentServiceObjectiveName,secondaryType:secondaryType,minCapacity:minCapacity,autoPauseDelay:autoPauseDelay}' -o json
