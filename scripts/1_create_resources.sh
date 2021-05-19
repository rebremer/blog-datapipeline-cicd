# Resource group
az group create -n $RG -l $LOC
# Key vault
az keyvault create -l $LOC -n $AKV -g $RG --enable-soft-delete false
tenantId=$(az account show --query tenantId -o tsv)
az keyvault secret set -n tenant-id --vault-name $AKV --value $tenantId
# Storage account
az storage account create -n $STOR -g $RG -l $LOC --sku Standard_LRS --kind StorageV2 --enable-hierarchical-namespace true
az storage container create --account-name $STOR -n "rawdata"
az storage container create --account-name $STOR -n "defineddata"
az storage blob upload -f "../data/dboPerson.txt" -c "rawdata" -n "dboPerson.txt" --account-name $STOR 
az storage blob upload -f "../data/dboRelation.txt" -c "rawdata" -n "dboRelation.txt" --account-name $STOR
# Databricks
az extension add --name databricks
dbr_response=$(az databricks workspace show -g $RG -n $DBRWORKSPACE)
if ["$dbr_response" = ""]; then
   vnetaddressrange="10.210.0.0"
   subnet1addressrange="10.210.0.0"
   subnet2addressrange="10.210.1.0"
   az network vnet create -g $RG -n $VNET --address-prefix $vnetaddressrange/16 -l $LOC  
   az network nsg create -g $RG -n "public-subnet-nsg"
   az network nsg create -g $RG -n "private-subnet-nsg"
   az network vnet subnet create -g $RG --vnet-name $VNET -n "public-subnet" --address-prefixes $subnet1addressrange/24 --network-security-group "public-subnet-nsg"
   az network vnet subnet create -g $RG --vnet-name $VNET -n "private-subnet" --address-prefixes $subnet2addressrange/24 --network-security-group "private-subnet-nsg"
   az network vnet subnet update --resource-group $RG --name "public-subnet" --vnet-name $VNET --delegations Microsoft.Databricks/workspaces
   az network vnet subnet update --resource-group $RG --name "private-subnet" --vnet-name $VNET --delegations Microsoft.Databricks/workspaces
   dbr_response=$(az databricks workspace create -l $LOC -n $DBRWORKSPACE -g $RG --sku premium --vnet $VNET --public-subnet "public-subnet" --private-subnet "private-subnet")
fi
# Variables
dbr_resource_id=$(jq .id -r <<< "$dbr_response")
workspaceUrl_no_http=$(jq .workspaceUrl -r <<< "$dbr_response")
workspace_id_url="https://"$workspaceUrl_no_http"/"
akv_url="https://"$AKV".vault.azure.net/"
stor_url="https://"$STOR".dfs.core.windows.net/"
echo "##vso[task.setvariable variable=dbr_resource_id]$dbr_resource_id"
echo "##vso[task.setvariable variable=workspace_id_url]$workspace_id_url"
echo "##vso[task.setvariable variable=akv_url]$akv_url"
echo "##vso[task.setvariable variable=stor_url]$stor_url"
# Cosmos DB graph API
cosmosdbdatabase="peopledb"
cosmosdbgraph="peoplegraph"
az cosmosdb create -n $COSMOSDBNAME -g $RG --capabilities EnableGremlin
az cosmosdb gremlin database create -a $COSMOSDBNAME -n $cosmosdbdatabase -g $RG
az cosmosdb gremlin graph create -g $RG -a $COSMOSDBNAME -d $cosmosdbdatabase -n $cosmosdbgraph --partition-key-path "/name"
cosmosdb_response=$(az cosmosdb keys list -n $COSMOSDBNAME -g $RG)
cosmosdb_key=$(jq .primaryMasterKey -r <<< "$cosmosdb_response")
az keyvault secret set -n cosmosdb-key --vault-name $AKV --value $cosmosdb_key
# Datafactory
az extension add --name datafactory
api_response=$(az datafactory show -n $ADFV2 -g $RG)
adfv2_id=$(jq .identity.principalId -r <<< "$api_response")
az keyvault set-policy -n $AKV --secret-permissions set get list --object-id $adfv2_id
# Assign RBAC rights ADFv2 MI on storage account. 
# Service connection SPN needs to have owner rights on account
scope="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$STOR"
az role assignment create --assignee-object-id $adfv2_id --role "Storage Blob Data Contributor" --scope $scope
# Assign RBAC rights ADFv2 MI on Databricks 
# Service connection SPN needs to have owner rights on account
az role assignment create --assignee-object-id $adfv2_id --role "Contributor" --scope $dbr_resource_id
