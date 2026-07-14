/*
===============================================================================
DDL Script: Create Bronze Tables
===============================================================================
Script Purpose:
    This script creates tables in the 'bronze' schema, dropping existing tables
    if they already exist.
    Run this script to re-define the DDL structure of 'bronze' tables.

Note (PostgreSQL translation of the original MSSQL pattern):
    IF OBJECT_ID('...', 'U') IS NOT NULL DROP TABLE ...  ->  DROP TABLE IF EXISTS
    NVARCHAR(n)  ->  VARCHAR(n)
    FLOAT (8-byte in MSSQL)  ->  DOUBLE PRECISION
        (do NOT use REAL: it is 4-byte / ~7 significant digits and drops cents,
         which breaks penny-level reconciliation when summing thousands of rows)
===============================================================================
*/

DROP TABLE IF EXISTS bronze.fact_campaign_daily;
CREATE TABLE bronze.fact_campaign_daily (
    campaign_id        INT,
    brand              VARCHAR(50),
    campaign_name      VARCHAR(50),
    platform           VARCHAR(50),
    ad_format          VARCHAR(50),
    objective          VARCHAR(50),
    audience_segment   VARCHAR(50),
    date               DATE,             -- RAW FORMAT: "2024-08-08"
    month              VARCHAR(10),      -- RAW FORMAT: "2024-08"
    week               VARCHAR(10),      -- RAW FORMAT: "2024-W31" (Python %U weeks)
    day_of_week        VARCHAR(9),
    is_weekend         BOOLEAN,
    impressions        INT,
    reach              INT,
    frequency          DOUBLE PRECISION, -- decimal in source (e.g. 1.43), not INT
    spend              DOUBLE PRECISION,
    cpm                DOUBLE PRECISION,
    clicks             INT,
    ctr                DOUBLE PRECISION,
    engagements        INT,
    likes              INT,
    comments           INT,
    shares             INT,
    saves              INT,
    engagement_rate    DOUBLE PRECISION,
    video_views        INT,
    video_views_25pct  INT,
    video_views_50pct  INT,
    video_views_75pct  INT,
    video_views_100pct INT,
    vtr                DOUBLE PRECISION,
    conversions        INT,
    revenue            DOUBLE PRECISION,
    cpc                DOUBLE PRECISION,
    cpa                DOUBLE PRECISION,
    cvr                DOUBLE PRECISION,
    roas               DOUBLE PRECISION
);

DROP TABLE IF EXISTS bronze.campaign_summary;
CREATE TABLE bronze.campaign_summary (
    brand             VARCHAR(50),
    campaign_name     VARCHAR(50),
    objective         VARCHAR(50),
    platform          VARCHAR(50),
    total_spend       DOUBLE PRECISION, -- decimal in source (e.g. 74999.37), not INT
    total_impressions BIGINT,
    total_reach       BIGINT,
    total_clicks      INT,
    total_conversions INT,
    total_revenue     DOUBLE PRECISION,
    total_engagements INT,
    days_active       INT,
    avg_cpm           DOUBLE PRECISION,
    avg_ctr           DOUBLE PRECISION,
    avg_cpa           DOUBLE PRECISION,
    roas              DOUBLE PRECISION,
    daily_spend       DOUBLE PRECISION
);

DROP TABLE IF EXISTS bronze.platform_summary;
CREATE TABLE bronze.platform_summary (
    platform          VARCHAR(50),
    total_spend       DOUBLE PRECISION,
    total_impressions BIGINT,
    total_reach       BIGINT,
    total_clicks      INT,
    total_engagements INT,
    total_video_views BIGINT,
    total_conversions INT,
    total_revenue     DOUBLE PRECISION,
    avg_cpm           DOUBLE PRECISION,
    avg_ctr           DOUBLE PRECISION,
    avg_cvr           DOUBLE PRECISION,
    avg_cpa           DOUBLE PRECISION,
    roas              DOUBLE PRECISION,
    engagement_rate   DOUBLE PRECISION
);

DROP TABLE IF EXISTS bronze.weekly_trend;
CREATE TABLE bronze.weekly_trend (
    week         VARCHAR(10),
    platform     VARCHAR(50),
    objective    VARCHAR(50),
    spend        DOUBLE PRECISION,
    impressions  BIGINT,
    clicks       INT,
    conversions  INT,
    revenue      DOUBLE PRECISION,
    engagements  INT,
    video_views  BIGINT,
    cpm          DOUBLE PRECISION,
    ctr          DOUBLE PRECISION,
    roas         DOUBLE PRECISION,
    cpa          DOUBLE PRECISION
);

DROP TABLE IF EXISTS bronze.format_performance;
CREATE TABLE bronze.format_performance (
    platform          VARCHAR(50),
    ad_format         VARCHAR(50),
    total_spend       DOUBLE PRECISION,
    total_impressions BIGINT,
    total_clicks      INT,
    total_conversions INT,
    total_revenue     DOUBLE PRECISION,
    total_engagements INT,
    total_video_views BIGINT,
    avg_cpm           DOUBLE PRECISION,
    avg_ctr           DOUBLE PRECISION,
    avg_cpa           DOUBLE PRECISION,
    roas              DOUBLE PRECISION,
    engagement_rate   DOUBLE PRECISION
);

DROP TABLE IF EXISTS bronze.audience_performance;
CREATE TABLE bronze.audience_performance (
    brand             VARCHAR(50),
    platform          VARCHAR(50),
    audience_segment  VARCHAR(50),
    total_spend       DOUBLE PRECISION,
    total_impressions BIGINT,
    total_clicks      INT,
    total_conversions INT,
    total_revenue     DOUBLE PRECISION,
    total_engagements INT,
    avg_ctr           DOUBLE PRECISION,
    avg_cpa           DOUBLE PRECISION,
    roas              DOUBLE PRECISION,
    cvr               DOUBLE PRECISION
);

DROP TABLE IF EXISTS bronze.funnel_analysis;
CREATE TABLE bronze.funnel_analysis (
    brand                      VARCHAR(50),
    platform                   VARCHAR(50),
    impressions                BIGINT,
    reach                      BIGINT,
    video_views                BIGINT,
    clicks                     INT,
    engagements                INT,
    conversions                INT,
    revenue                    DOUBLE PRECISION,
    spend                      DOUBLE PRECISION,
    awareness_to_consideration DOUBLE PRECISION,
    consideration_to_intent    DOUBLE PRECISION,
    intent_to_conversion       DOUBLE PRECISION,
    overall_conversion_rate    DOUBLE PRECISION,
    cost_per_impression        DOUBLE PRECISION,
    roas                       DOUBLE PRECISION
);

-- NOTE: the source export contains exact duplicate rows — kept as-is here
-- (bronze = as-is), deduplicated in silver, surfaced by quality_checks_silver.
DROP TABLE IF EXISTS bronze.pacing_report;
CREATE TABLE bronze.pacing_report (
    brand                  VARCHAR(50),
    campaign_name          VARCHAR(50),
    platform               VARCHAR(50),
    month                  VARCHAR(10),      -- RAW FORMAT: "2024-07"
    budget_target          DOUBLE PRECISION,
    impression_target      BIGINT,
    conversion_target      INT,
    actual_spend           DOUBLE PRECISION,
    actual_impressions     DOUBLE PRECISION, -- RAW FORMAT: float-styled ("1413512.0")
    actual_conversions     DOUBLE PRECISION, -- RAW FORMAT: float-styled ("318.0")
    actual_revenue         DOUBLE PRECISION,
    spend_pacing_pct       DOUBLE PRECISION,
    impression_pacing_pct  DOUBLE PRECISION,
    conversion_pacing_pct  DOUBLE PRECISION,
    spend_variance         DOUBLE PRECISION,
    pacing_status          VARCHAR(20)
);

DROP TABLE IF EXISTS bronze.weekend_weekday_lift;
CREATE TABLE bronze.weekend_weekday_lift (
    row_id         INT,                -- unnamed pandas index column in the CSV
    platform       VARCHAR(50),
    metric         VARCHAR(10),
    weekday_avg    DOUBLE PRECISION,
    weekend_avg    DOUBLE PRECISION,
    lift_pct       DOUBLE PRECISION,
    significant    VARCHAR(10),
    interpretation VARCHAR(50)
);
