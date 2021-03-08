if [ $MOUNT_STORAGE_DATABRICKS = 0 ]; then
    echo "Storage shall not be mounted"
    exit 0
fi
#
keyvault_response=$(az keyvault secret show -n spn-id --vault-name $AKV)
spn_id=$(jq .value -r <<< "$keyvault_response")
if ["$spn_id" = ""]; then

    echo "No spn present, storage cannot be mounted"
    exit 0
fi
# Databricks
dbr_response=$(az databricks workspace show -g $RG -n $DBRWORKSPACE)
workspaceUrl_no_http=$(jq .workspaceUrl -r <<< "$dbr_response")
workspace_id_url="https://"$workspaceUrl_no_http"/"
#
# 1. Create job
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
api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/jobs/create \
  -H "Authorization: Bearer $token" \
  -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
  -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
  -d "{\"name\": \"mount storage\", \"existing_cluster_id\": \"$cluster_id\", \"notebook_task\": {\"notebook_path\": \"/mount_ADLSgen2_rawdata.py\", \"base_parameters\": [{\"key\":\"stor_name\", \"value\":\"$STOR\"}]}}")
job_id=$(jq .job_id -r <<< "$api_response")
#
# 2. Run job to run notebook to mount storage
api_response=$(curl -v -X POST ${workspace_id_url}api/2.0/jobs/run-now \
  -H "Authorization: Bearer $token" \
  -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
  -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId" \
  -d "{\"job_id\": $job_id}")
run_id=$(jq .run_id -r <<< "$api_response")
#
# 3. Wait until jobs if finished (mainly dependent on step 9 to create cluster)
i=0
while [ $i -lt 10 ]
do
  echo "Time waited for job to finish: $i minutes"
  ((i++))
  api_response=$(curl -v -X GET ${workspace_id_url}api/2.0/jobs/runs/get\?run_id=$run_id \
    -H "Authorization: Bearer $token" \
    -H "X-Databricks-Azure-SP-Management-Token:$azToken" \
    -H "X-Databricks-Azure-Workspace-Resource-Id:$wsId"
  )
  state=$(jq .state.life_cycle_state -r <<< "$api_response")
  echo "job state: $state"
  if [[ "$state" == 'TERMINATED' || "$state" == 'SKIPPED' || "$state" == 'INTERNAL_ERROR' ]]; then
    break
  fi
  sleep 1m
done
