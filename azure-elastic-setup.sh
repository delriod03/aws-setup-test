#!/bin/bash

# ================================
# CyberMaxx Azure EventHub Setup
# One-liner compatible
# ================================

set -e

# ===== INPUT =====
CUSTOMER="$1"
LOCATION="${2:-eastus}"

if [ -z "$CUSTOMER" ]; then
  echo "Usage: bash setup.sh <customer-name> [location]"
  exit 1
fi

# ===== AZ LOGIN CHECK =====
if ! az account show &>/dev/null; then
  echo "Logging into Azure..."
  az login
fi

echo "Using subscription:"
az account show --query name -o tsv
echo ""

# ===== NAMING =====
RESOURCE_GROUP="rg-cybermaxx-$CUSTOMER"
NAMESPACE_NAME="cmx-${CUSTOMER}-ehns"
EVENTHUB_NAME="cmx-${CUSTOMER}-logs"
STORAGE_ACCOUNT_NAME="cmx${CUSTOMER}st$(date +%s | tail -c 5)"
CONSUMER_GROUP="\$Default"

# ===== RESOURCE GROUP =====
echo "Creating resource group..."
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --output none

# ===== EVENT HUB NAMESPACE =====
echo "Creating Event Hub namespace..."
az eventhubs namespace create \
  --name $NAMESPACE_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Basic \
  --capacity 1 \
  --output none

# ===== EVENT HUB =====
echo "Creating Event Hub..."
az eventhubs eventhub create \
  --name $EVENTHUB_NAME \
  --namespace-name $NAMESPACE_NAME \
  --resource-group $RESOURCE_GROUP \
  --partition-count 4 \
  --message-retention 7 \
  --output none

# ===== SAS POLICIES =====
echo "Creating access policies..."
az eventhubs namespace authorization-rule create \
  --resource-group $RESOURCE_GROUP \
  --namespace-name $NAMESPACE_NAME \
  --name "cmx-send" \
  --rights Send \
  --output none || true

az eventhubs namespace authorization-rule create \
  --resource-group $RESOURCE_GROUP \
  --namespace-name $NAMESPACE_NAME \
  --name "cmx-listen" \
  --rights Listen \
  --output none || true

# ===== CONNECTION STRING =====
EVENTHUB_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
  --resource-group $RESOURCE_GROUP \
  --namespace-name $NAMESPACE_NAME \
  --name "cmx-listen" \
  --query "primaryConnectionString" \
  --output tsv)

# ===== STORAGE ACCOUNT =====
echo "Creating storage account..."
az storage account create \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --output none

STORAGE_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query "[0].value" \
  --output tsv)

# ===== OPTIONAL: ENTRA DIAGNOSTICS =====
echo "Attempting to enable Entra ID logs (may fail on non-premium tenants)..."

EVENTHUB_AUTH_RULE_ID=$(az eventhubs namespace authorization-rule show \
  --resource-group $RESOURCE_GROUP \
  --namespace-name $NAMESPACE_NAME \
  --name "cmx-send" \
  --query "id" \
  --output tsv)

az monitor diagnostic-settings create \
  --name "cmx-entra-to-eventhub" \
  --resource "/providers/Microsoft.aadiam/diagnosticSettings" \
  --event-hub $EVENTHUB_NAME \
  --event-hub-rule $EVENTHUB_AUTH_RULE_ID \
  --logs '[
    {"category": "AuditLogs", "enabled": true},
    {"category": "SignInLogs", "enabled": true},
    {"category": "NonInteractiveUserSignInLogs", "enabled": true},
    {"category": "ServicePrincipalSignInLogs", "enabled": true},
    {"category": "ProvisioningLogs", "enabled": true}
  ]' \
  --output none || echo "Skipping Entra diagnostic settings"

# ===== OUTPUT =====
echo ""
echo "================ OUTPUT ================"
echo "eventhub_name: $EVENTHUB_NAME"
echo "connection_string: $EVENTHUB_CONNECTION_STRING"
echo "consumer_group: $CONSUMER_GROUP"
echo "storage_account: $STORAGE_ACCOUNT_NAME"
echo "storage_key: $STORAGE_KEY"
echo "========================================"
