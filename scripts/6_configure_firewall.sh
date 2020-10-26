if [ $ENABLE_FIREWALL = 0 ]; then
    echo "Firewall will not be enabled"
    exit 0
fi
#
# 0. Service endpoints
az network vnet subnet update --resource-group $RG --vnet-name $VNET --name "public-subnet" --service-endpoints "Microsoft.KeyVault" "Microsoft.Storage" "Microsoft.AzureCosmosDB"
cli_response=$(az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET" --name "public-subnet")
subnet_id=$(jq .id -r <<< "$cli_response")
#
# 1. Cosmos DB
#az cosmosdb account update --resource-group "$RG" --name "$COSMOSDBNAME" --enable-public-network false
# Databricks
az cosmosdb update -g $RG -n $COSMOSDBNAME --enable-virtual-network true
az cosmosdb network-rule add -g $RG -n $COSMOSDBNAME --subnet $subnet_id
#
# 2. Key vault
az keyvault update --resource-group "$RG" --name "$AKV" --default-action Deny
# Databricks
az keyvault network-rule add -g "$RG" -n "$AKV" --subnet $subnet_id
# Azure Data Factory
az keyvault update --resource-group "$RG" --name "$AKV" --bypass AzureServices
#
# 3. Storage account
az storage account update --resource-group "$RG" --name "$STOR" --default-action Deny
# Databricks
az storage account network-rule add -g $RG --account-name $STOR --subnet $subnet_id
# Azure Data Factory
az storage account update -g "$RG" -n "$STOR" --bypass AzureServices
#
sleep 1m # avoid raise conditions