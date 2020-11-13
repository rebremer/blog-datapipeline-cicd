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
#
# 1. Create job
keyvault_response=$(az keyvault secret show -n pattoken --vault-name $AKV)
pat_token=$(jq .value -r <<< "$keyvault_response")
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/jobs/create \
  -H "Authorization: Bearer $pat_token" \
  -d "{\"name\": \"mount storage\", \"existing_cluster_id\": \"$cluster_id\", \"notebook_task\": {\"notebook_path\": \"/mount_ADLSgen2_rawdata\", \"base_parameters\": [{\"key\":\"stor_name\", \"value\":\"$STOR\"}]}}")
job_id=$(jq .job_id -r <<< "$api_response")
#
# 2. Run job to run notebook to mount storage
api_response=$(curl -v -X POST https://$LOC.azuredatabricks.net/api/2.0/jobs/run-now \
  -H "Authorization: Bearer $pat_token" \
  -d "{\"job_id\": $job_id}")
run_id=$(jq .run_id -r <<< "$api_response")
#
# 3. Wait until jobs if finished (mainly dependent on step 9 to create cluster)
i=0
while [ $i -lt 10 ]
do
  echo "Time waited for job to finish: $i minutes"
  ((i++))
  api_response=$(curl -v -X GET https://$LOC.azuredatabricks.net/api/2.0/jobs/runs/get\?run_id=$run_id \
    -H "Authorization: Bearer $pat_token" )
  state=$(jq .state.life_cycle_state -r <<< "$api_response")
  echo "job state: $state"
  if [[ "$state" == 'TERMINATED' || "$state" == 'SKIPPED' || "$state" == 'INTERNAL_ERROR' ]]; then
    break
  fi
  sleep 1m
done