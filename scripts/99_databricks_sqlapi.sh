RG="<<your resource group>>"
DBRWORKSPACE="<<your Databricks workspace>>"
# 1a. Get tenantID and resource id
tenantId=$(az account show --query tenantId -o tsv)
wsId=$(az resource show \
  --resource-type Microsoft.Databricks/workspaces \
  -g "$RG" \
  -n "$DBRWORKSPACE" \
  --query id -o tsv)
# 1b. Get two bearer tokens in Azure
token_response=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d)
token=$(jq .accessToken -r <<< "$token_response")
token_response=$(az account get-access-token --resource https://management.core.windows.net/)
azToken=$(jq .accessToken -r <<< "$token_response")
#
# 1c. Databricks variables
dbr_response=$(az databricks workspace show -g $RG -n $DBRWORKSPACE)
workspaceUrl_no_http=$(jq .workspaceUrl -r <<< "$dbr_response")
workspace_id_url="https://"$workspaceUrl_no_http"/"
#
# 2. Use SQL Warehouses APIs 2.0, create data warehouse
api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/sql/warehouses/ \
  -H "Authorization: Bearer $token" \
  -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
  -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
  -d "{\"name\": \"testAzureADSQL\",\"cluster_size\": \"Small\",\"min_num_clusters\": 1,\"max_num_clusters\": 10, \"enable_photon\": \"true\"}")
database_id=$(jq .database -r <<< "$dbr_response")
#
# 3. Use Queries and Dashboards API, find queries
api_response=$(curl -v -X GET ${workspace_id_url}api/2.0/preview/sql/queries \
  -H "Authorization: Bearer $token" \
  -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
  -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId")