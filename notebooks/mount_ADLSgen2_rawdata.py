# Databricks notebook source
# MAGIC %md Azure Databricks notebooks by Rene Bremer
# MAGIC 
# MAGIC Copyright (c) Microsoft Corporation. All rights reserved.
# MAGIC 
# MAGIC Licensed under the MIT License.

# COMMAND ----------

par_stor_name = dbutils.widgets.get("stor_name")
par_tenant = dbutils.widgets.get("tenant_id")

# COMMAND ----------

# Databricks notebook source
# "fs.azure.account.oauth2.client.secret": dbutils.secrets.get(scope="<scope-name>",key="<service-credential-key-name>"),

configs = {"fs.azure.account.auth.type": "OAuth",
           "fs.azure.account.oauth.provider.type": "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider",
           "fs.azure.account.oauth2.client.id": dbutils.secrets.get(scope="dbrkeys",key="spn-id"),
           "fs.azure.account.oauth2.client.secret": dbutils.secrets.get(scope="dbrkeys",key="spn-key"),
           "fs.azure.account.oauth2.client.endpoint": "https://login.microsoftonline.com/" + dbutils.secrets.get(scope="dbrkeys",key="tenant-id") + "/oauth2/token"}

# Optionally, you can add <directory-name> to the source URI of your mount point.
dbutils.fs.mount(
  source = "abfss://defineddata@" + par_stor_name + ".dfs.core.windows.net/",
  mount_point = "/mnt/defineddata",
  extra_configs = configs)

# COMMAND ----------

%sh
ls -l /dbfs/mnt/defineddata

# COMMAND ----------