# Databricks
az extension add --name databricks
dbr_response=$(az databricks workspace show -g $RG -n $DBRWORKSPACE)
workspaceUrl_no_http=$(jq .workspaceUrl -r <<< "$dbr_response")
workspace_id_url="https://"$workspaceUrl_no_http"/"
# Get two bearer tokens in Azure
tenantId=$(az account show --query tenantId -o tsv)
wsId=$(az resource show \
  --resource-type Microsoft.Databricks/workspaces \
  -g "$RG" \
  -n "$DBRWORKSPACE" \
  --query id -o tsv)
token_response=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d)
token=$(jq .accessToken -r <<< "$token_response")
token_response=$(az account get-access-token --resource https://management.core.windows.net/)
azToken=$(jq .accessToken -r <<< "$token_response")
#
if [ $SECRETSCOPE_KEYVAULT = 0 ]; then
  api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/secrets/scopes/create \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
    -d "{\"scope\": \"dbrkeys\"}")
  # 2a2. Move keys from key vault to Databricks backed secret scope
  keyvault_response=$(az keyvault secret show -n spn-id --vault-name $AKV)
  spn_id=$(jq .value -r <<< "$keyvault_response")
  keyvault_response=$(az keyvault secret show -n spn-key --vault-name $AKV)
  spn_key=$(jq .value -r <<< "$keyvault_response")
  keyvault_response=$(az keyvault secret show -n stor-key --vault-name $AKV)
  stor_key=$(jq .value -r <<< "$keyvault_response")
  keyvault_response=$(az keyvault secret show -n cosmosdb-key --vault-name $AKV)
  cosmosdb_key=$(jq .value -r <<< "$keyvault_response")
  keyvault_response=$(az keyvault secret show -n tenant-id --vault-name $AKV)
  tenant_id=$(jq .value -r <<< "$keyvault_response")
  api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/secrets/put \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
    -d "{\"scope\": \"dbrkeys\", \"key\": \"spn-id\", \"string_value\": \"$spn_id\"}")
  api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/secrets/put \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
    -d "{\"scope\": \"dbrkeys\", \"key\": \"spn-key\", \"string_value\": \"$spn_key\"}")
  api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/secrets/put \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
    -d "{\"scope\": \"dbrkeys\", \"key\": \"stor-key\", \"string_value\": \"$stor_key\"}")
  api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/secrets/put \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
    -d "{\"scope\": \"dbrkeys\", \"key\": \"cosmosdb-key\", \"string_value\": \"$cosmosdb_key\"}")
  api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/secrets/put \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
    -d "{\"scope\": \"dbrkeys\", \"key\": \"tenant-id\", \"string_value\": \"$tenant_id\"}")
else
  #2b. Create secret sope backed by Azure Key Vault, only works with Azure AD token
  #
  # 20201213: This does not work from Azure DevOps SPN (only when)
  # See https://github.com/databricks/databricks-cli/issues/338 for workaround
  #
  echo "Create secret sope backed by Azure Key Vault"
  #
  akv_url="https://"$AKV".vault.azure.net/"
  api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/secrets/scopes/create \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
    -d "{\"scope\": \"dbrkeys\", \"scope_backend_type\": \"AZURE_KEYVAULT\", \"backend_azure_keyvault\":{\"resource_id\": \"/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/$AKV\", \"dns_name\": \"$akv_url\"}}")
  error_code=$(jq .error_code -r <<< "$api_response")
  echo $error_code
  message=$(jq .message -r <<< "$api_response")
  echo $message
fi