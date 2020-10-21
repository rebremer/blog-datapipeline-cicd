if [ $ACCESS_STOR_AADDBR = 0 ]; then
    echo "Usage access key of storage account to authenticate"
    key_response=$(az storage account keys list -g $RG -n $STOR)
    stor_key=$(jq .[0].value -r <<< "$key_response")
    az keyvault secret set -n stor-key --vault-name $AKV --value $stor_key
else
    echo "Assging Azure AD SPN to Databricks for authentication to storage account"
    spn_response=$(az ad sp create-for-rbac -n $SPN --skip-assignment)
    spn_id=$(jq .appId -r <<< "$spn_response")
    spn_key=$(jq .password -r <<< "$spn_response")
    #
    az keyvault secret set -n spn-id --vault-name $AKV --value $spn_id
    az keyvault secret set -n spn-key --vault-name $AKV --value $spn_key
    #
    scope="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$STOR"
    az role assignment create --assignee-object-id $spn_id --role "Storage Blob Data Contributor" --scope $scope
    #
    # In case a Databricks secret scope is used and this script is run afterwards with elevated user rights,
    # also run script 4_configure_secret_scope_databricks.sh to add spn_id and spn_key to Databricks secret scope
fi
