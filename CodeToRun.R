# =============================================================================
# Biliary Stent PLE — Feasibility Check
# 
# Version: 2026-08-21
# =============================================================================
#
# Execute all the R codes
# (QnA: Yiju Park / yijoo0320@yuhs.ac)
#
# Package: DatabaseConnector, SqlRender, CohortGenerator
#
# =============================================================================

# Library Setting
library(DatabaseConnector)
library(SqlRender)
library(CohortGenerator)

# -----------------------------------------------------------------------------
# Details for connecting to the sever: Modify connectionDetails according to your institution
# -----------------------------------------------------------------------------

connectionDetails <- DatabaseConnector::createConnectionDetails(dbms     = "pdw",                      # modify dbms (e.g., sql server)
                                                                server   = Sys.getenv("PDW_SERVER"),   # modify server address
                                                                user     = NULL,                       # modify user (server username)
                                                                password = NULL,                       # modify password
                                                                port     = Sys.getenv("PDW_PORT"),     # modify port
                                                                pathToDriver = "~/jdbc")

cdmDatabaseSchema     <- "DATABASE.SCHEMA"          # Modify Schema according to your institution
cohortDatabaseSchema  <- "DATABASE.SCHEMA"          # Modify Schema according to your institution
cohortTable           <- NULL                       # Modify Table
vocabularyDatabaseSchema <- cdmDatabaseSchema 

databaseId   <- "SITE_NAME"                         # Modify Site (e.g., YUHS)


# -----------------------------------------------------------------------------

outputFolder <- file.path(getwd(), "output", databaseId)

targetId     <- 851L   # Metal stent with Pancreatic cancer
comparatorId <- 852L   # Plastic stent with Pancreatic cancer
minCellCount <- 5L     

if (!dir.exists(outputFolder)) {
  dir.create(outputFolder, recursive = TRUE)
}


cohortSqlFiles <- list(
  list(cohortId = 851L, path = file.path("cohorts", "yjpark_Metal_stent_with_Pancreatic_cancer.sql")),
  list(cohortId = 852L, path = file.path("cohorts", "yjpark_Plastic_stent_with_Pancreatic_cancer.sql"))
)

cohortDefinitionSet <- do.call(rbind, lapply(cohortSqlFiles, function(x) {
  sql <- paste(readLines(x$path, warn = FALSE), collapse = "\n")
  data.frame(
    cohortId   = x$cohortId,
    cohortName = paste0("cohort_", x$cohortId),
    json       = "",
    sql        = sql,
    stringsAsFactors = FALSE
  )
}))

cohortTableNames <- CohortGenerator::getCohortTableNames(cohortTable = cohortTable)

CohortGenerator::createCohortTables(
  connectionDetails    = connectionDetails,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTableNames     = cohortTableNames
)

cohortsGenerated <- CohortGenerator::generateCohortSet(
  connectionDetails    = connectionDetails,
  cdmDatabaseSchema    = cdmDatabaseSchema,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTableNames     = cohortTableNames,
  cohortDefinitionSet  = cohortDefinitionSet
)
print(cohortsGenerated)

cohortCounts <- CohortGenerator::getCohortCounts(
  connectionDetails    = connectionDetails,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTable          = cohortTable,
  cohortIds            = c(targetId, comparatorId)
)
print(cohortCounts)


# -----------------------------------------------------------------------------

connection <- DatabaseConnector::connect(connectionDetails)
on.exit(DatabaseConnector::disconnect(connection), add = TRUE)

sqlCoverage <- SqlRender::readSql(file.path("sql", "MeasurementCoverage.sql"))
sqlCoverage <- SqlRender::render(
  sql                     = sqlCoverage,
  cdm_database_schema     = cdmDatabaseSchema,
  cohort_database_schema  = cohortDatabaseSchema,
  cohort_table            = cohortTable,
  target_id               = targetId,
  comparator_id           = comparatorId,
  min_cell_count          = minCellCount
)
sqlCoverage <- SqlRender::translate(sqlCoverage, targetDialect = connectionDetails$dbms)

coverage <- DatabaseConnector::querySql(connection, sqlCoverage)

write.csv(coverage, file.path(outputFolder, "measurement_coverage.csv"), row.names = FALSE)

# -----------------------------------------------------------------------------

sqlDist <- SqlRender::readSql(file.path("sql", "MeasurementValueDistribution.sql"))
sqlDist <- SqlRender::render(
  sql                     = sqlDist,
  cdm_database_schema     = cdmDatabaseSchema,
  cohort_database_schema  = cohortDatabaseSchema,
  cohort_table            = cohortTable,
  target_id               = targetId,
  comparator_id           = comparatorId
)
sqlDist <- SqlRender::translate(sqlDist, targetDialect = connectionDetails$dbms)

valueDist <- DatabaseConnector::querySql(connection, sqlDist)

write.csv(valueDist, file.path(outputFolder, "measurement_value_dist.csv"), row.names = FALSE)
