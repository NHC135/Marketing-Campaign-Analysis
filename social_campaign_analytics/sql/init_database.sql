/*
===============================================================================
Create Database and Schemas
===============================================================================
Script Purpose:
    This script creates a new database named 'social_campaign_dw' after checking
    if it already exists. If it exists, it is dropped and recreated.
    Additionally, the script sets up three schemas within the database:
    'bronze', 'silver', and 'gold' (Medallion Architecture).

WARNING:
    Running this script will drop the entire 'social_campaign_dw' database if it
    exists. All data in the database will be permanently deleted. Proceed with
    caution and ensure you have proper backups before running this script.
===============================================================================
*/

DROP DATABASE IF EXISTS social_campaign_dw;
CREATE DATABASE social_campaign_dw;

connect social_campaign_dw

-- Create Schemas
CREATE SCHEMA bronze;
CREATE SCHEMA silver;
CREATE SCHEMA gold;

COMMENT ON SCHEMA bronze IS 'Ingest: raw, unprocessed data as-is from source CSVs (traceability & debugging)';
COMMENT ON SCHEMA silver IS 'Clean: standardized, normalized, derived and enriched data prepared for analysis';
COMMENT ON SCHEMA gold   IS 'Business: aggregated, analytics-ready views consumed by reporting (Power BI)';
