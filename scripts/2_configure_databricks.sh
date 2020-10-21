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
# 1c. Use bearer tokens to create PAT token
dbr_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/token/create \
  -H "Authorization: Bearer $token" \
  -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
  -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
  -d '{ "lifetime_seconds": 360000, "comment": "this is an example token - Azure DevOPS" }')
pat_token=$(jq .token_value -r <<< "$dbr_response")
# 1d. Add pat token to key vault
az keyvault secret set -n pattoken --vault-name $AKV --value $pat_token
#
# 2. Upload notebook to Databricks Workspace
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/workspace/import \
  -H "Authorization: Bearer $pat_token" \
  -F path="/mount_ADLSgen2_rawdata.py" -F format=SOURCE -F language=PYTHON -F overwrite=true -F content=@../notebooks/mount_ADLSgen2_rawdata.py)
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/workspace/import \
  -H "Authorization: Bearer $pat_token" \
  -F path="/insert_data_CosmosDB_Gremlin.py" -F format=SOURCE -F language=PYTHON -F overwrite=true -F content=@../notebooks/insert_data_CosmosDB_Gremlin.py)
#
# 3. Upload libraries to Databricks DBFS
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/dbfs/put \
  -H "Authorization: Bearer $pat_token" \
  -F path="/azure-cosmosdb-spark_2.4.0_2.11-2.1.2-uber.jar" -F contents=@../libraries/azure-cosmosdb-spark_2.4.0_2.11-2.1.2-uber.jar -F overwrite=true)
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/dbfs/put \
  -H "Authorization: Bearer $pat_token" \
  -F path="/graphframes-0.8.1-spark2.4-s_2.11.jar" -F contents=@../libraries/graphframes-0.8.1-spark2.4-s_2.11.jar -F overwrite=true)
#
# 4. Create Databricks cluster
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/clusters/create \
  -H "Authorization: Bearer $pat_token" \
  -d "{\"cluster_name\": \"clusterPAT6\",\"spark_version\": \"6.6.x-scala2.11\",\"node_type_id\": \"Standard_D3_v2\", \"autotermination_minutes\":60, \"num_workers\" : 1}")
cluster_id=$(jq .cluster_id -r <<< "$api_response")
echo "##vso[task.setvariable variable=cluster_id]$cluster_id"
sleep 1m
#
# 5. Add libraries to cluster
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/libraries/install \
  -H "Authorization: Bearer $pat_token" \
  -d "{\"cluster_id\": \"$cluster_id\", \"libraries\": [{\"jar\": \"dbfs:/azure-cosmosdb-spark_2.4.0_2.11-2.1.2-uber.jar\"},{\"jar\": \"dbfs:/graphframes-0.8.1-spark2.4-s_2.11.jar\"}]}")