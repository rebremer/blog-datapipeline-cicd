# Databricks notebook source
# MAGIC %md Azure Databricks notebooks by Rene Bremer
# MAGIC 
# MAGIC Copyright (c) Microsoft Corporation. All rights reserved.
# MAGIC 
# MAGIC Licensed under the MIT License.

# COMMAND ----------

par_cosmosdb_name = dbutils.widgets.get("cosmosdb_name")
par_stor_name = dbutils.widgets.get("stor_name")

# COMMAND ----------

# Databricks notebook source
# DBTITLE 1,Get parquet data from ADLSgen2
from pyspark.sql.functions import *
try:
  mnt_defineddata = dbutils.fs.ls('/mnt/defineddata')
  defineddata_mounted = 1
except:
  defineddata_mounted = 0
  spn_id = dbutils.secrets.get(scope="dbrkeys",key="spn-id")
 
if defineddata_mounted == 1:
  print ("try to get data from mounted storage")
  dfperson = spark.read.parquet("/mnt/defineddata/dboPerson.parquet").withColumn("entity", lit("person"))
  dfrelation = spark.read.parquet("/mnt/defineddata/dboRelation.parquet")
elif spn_id != "":
    print ("try to get data from using spn")    
    spark.conf.set("fs.azure.account.auth.type." + par_stor_name + ".dfs.core.windows.net", "OAuth")
    spark.conf.set("fs.azure.account.oauth.provider.type." + par_stor_name + ".dfs.core.windows.net", "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider")
    spark.conf.set("fs.azure.account.oauth2.client.id." + par_stor_name + ".dfs.core.windows.net", dbutils.secrets.get(scope="dbrkeys",key="spn-id"))
    spark.conf.set("fs.azure.account.oauth2.client.secret." + par_stor_name + ".dfs.core.windows.net", dbutils.secrets.get(scope="dbrkeys",key="spn-key"))
    spark.conf.set("fs.azure.account.oauth2.client.endpoint." + par_stor_name + ".dfs.core.windows.net", "https://login.microsoftonline.com/" + dbutils.secrets.get(scope="dbrkeys",key="tenant-id") + "/oauth2/token")
    dfperson = spark.read.parquet("abfss://defineddata@" + par_stor_name + ".dfs.core.windows.net/dboPerson.parquet").withColumn("entity", lit("person"))
    dfrelation = spark.read.parquet("abfss://defineddata@" + par_stor_name + ".dfs.core.windows.net/dboRelation.parquet")
else:
    print ("try to get data from using storage access key, not recommended in production")
    spark.conf.set("fs.azure.account.key." + par_stor_name + ".dfs.core.windows.net", dbutils.secrets.get(scope="dbrkeys",key="stor-key"))
    dfperson = spark.read.parquet("abfss://defineddata@" + par_stor_name + ".dfs.core.windows.net/dboPerson.parquet").withColumn("entity", lit("person"))
    dfrelation = spark.read.parquet("abfss://defineddata@" + par_stor_name + ".dfs.core.windows.net/dboRelation.parquet")
 
columns_new = [col.replace("fromid", "src") for col in dfrelation.columns]
dfrelation = dfrelation.toDF(*columns_new)
 
columns_new = [col.replace("toid", "dst") for col in dfrelation.columns]
dfrelation = dfrelation.toDF(*columns_new)

# COMMAND ----------

from graphframes import GraphFrame
g = GraphFrame(dfperson, dfrelation)

# COMMAND ----------

from pyspark.sql.types import StringType
from urllib.parse import quote

def urlencode(value):
  return quote(value, safe="")

udf_urlencode = udf(urlencode, StringType())

# COMMAND ----------

def to_cosmosdb_vertices(dfVertices, labelColumn, partitionKey = ""):
  dfVertices = dfVertices.withColumn("id", udf_urlencode("id"))
  dfVertices = dfVertices.withColumn("age", udf_urlencode("age"))
  dfVertices = dfVertices.withColumn("name", udf_urlencode("name"))
  
  columns = ["id", labelColumn]
  
  if partitionKey:
    columns.append(partitionKey)
  
  #columns.extend(['nvl2({x}, array(named_struct("id", uuid(), "_value", {x})), NULL) AS {x}'.format(x=x) \
#                for x in dfVertices.columns if x not in columns])
 
  return dfVertices.selectExpr(*columns).withColumnRenamed(labelColumn, "label")

# COMMAND ----------

cosmosDbVertices = dfperson
#display(dfperson)

# COMMAND ----------

from pyspark.sql.functions import concat_ws, col

def to_cosmosdb_edges(g, labelColumn, partitionKey = ""): 
  dfEdges = g.edges
  
  if partitionKey:
    dfEdges = dfEdges.alias("e") \
      .join(g.vertices.alias("sv"), col("e.src") == col("sv.id")) \
      .join(g.vertices.alias("dv"), col("e.dst") == col("dv.id")) \
      .selectExpr("e.*", "sv." + partitionKey, "dv." + partitionKey + " AS _sinkPartition")

  dfEdges = dfEdges \
    .withColumn("id", udf_urlencode(concat_ws("_", col("src"), col(labelColumn), col("dst")))) \
    .withColumn("_isEdge", lit(True)) \
    .withColumn("_vertexId", udf_urlencode("src")) \
    .withColumn("_sink", udf_urlencode("dst")) \
    .withColumnRenamed(labelColumn, "label") \
    .drop("src", "dst")
  
  return dfEdges

# COMMAND ----------

cosmosDbEdges = to_cosmosdb_edges(g, "relationtype")
display(cosmosDbEdges)

# COMMAND ----------

cfg = {
  "spark.cosmos.accountEndpoint" : "https://" + par_cosmosdb_name + ".documents.azure.com:443/",
  "spark.cosmos.accountKey" : dbutils.secrets.get(scope="dbrkeys",key="cosmosdb-key"),
  "spark.cosmos.database" : "peopledb",
  "spark.cosmos.container" : "peoplegraph"
}

cosmosDbFormat ="cosmos.oltp"

cosmosDbVertices.write.format("cosmos.oltp").options(**cfg).mode("APPEND").save()
cosmosDbEdges.write.format("cosmos.oltp").options(**cfg).mode("APPEND").save()

#cosmosDbConfig = {
#  "Endpoint" : "https://" + par_cosmosdb_name + ".documents.azure.com:443/",
#  "Masterkey" : dbutils.secrets.get(scope="dbrkeys",key="cosmosdb-key"),
#  "Database" : "peopledb",
#  "Collection" : "peoplegraph",
#  "Upsert" : "true"
#}

#cosmosDbFormat = "com.microsoft.azure.cosmosdb.spark"

#cosmosDbVertices.write.format(cosmosDbFormat).mode("append").options(**cosmosDbConfig).save()
#cosmosDbEdges.write.format(cosmosDbFormat).mode("append").options(**cosmosDbConfig).save()


# COMMAND ----------


