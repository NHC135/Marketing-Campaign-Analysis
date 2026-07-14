/*
===============================================================================
DDL Script: Create Silver Tables
===============================================================================
Script Purpose:
    This script creates tables in the 'silver' schema, dropping existing tables
    if they already exist.
    Run this script to re-define the DDL structure of 'silver' tables.

Data Model (Snowflake Schema):
    dim_brand ──< dim_campaign ──────<┐
    dim_platform ──< dim_ad_format ──< fact_campaign_daily >── dim_date
    dim_audience ────────────────────<┘
    fact_pacing_target (campaign × platform × month budget/KPI targets)

Note (PostgreSQL translation of the original MSSQL pattern):
    IF OBJECT_ID(...) DROP TABLE  ->  DROP TABLE IF EXISTS
    NVARCHAR(n)                   ->  VARCHAR(n)
    dwh_create_date DATETIME2 DEFAULT GETDATE()
                                  ->  dwh_create_date TIMESTAMP DEFAULT now()
===============================================================================
*/

DROP TABLE IF EXISTS silver.fact_campaign_daily;
DROP TABLE IF EXISTS silver.fact_pacing_target;
DROP TABLE IF EXISTS silver.dim_campaign;
DROP TABLE IF EXISTS silver.dim_ad_format;
DROP TABLE IF EXISTS silver.dim_audience;
DROP TABLE IF EXISTS silver.dim_brand;
DROP TABLE IF EXISTS silver.dim_platform;
DROP TABLE IF EXISTS silver.dim_date;

CREATE TABLE silver.dim_brand (
    brand_key       SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    brand_name      VARCHAR(50) NOT NULL UNIQUE,
    dwh_create_date TIMESTAMP   NOT NULL DEFAULT now()
);

CREATE TABLE silver.dim_platform (
    platform_key    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    platform_name   VARCHAR(50) NOT NULL UNIQUE,
    dwh_create_date TIMESTAMP   NOT NULL DEFAULT now()
);

-- snowflaked off dim_platform (ad formats are platform-specific)
CREATE TABLE silver.dim_ad_format (
    ad_format_key   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    platform_key    SMALLINT    NOT NULL REFERENCES silver.dim_platform,
    ad_format_name  VARCHAR(50) NOT NULL,
    is_video_format BOOLEAN     NOT NULL,   -- enrichment for VTR analysis
    dwh_create_date TIMESTAMP   NOT NULL DEFAULT now(),
    UNIQUE (platform_key, ad_format_name)
);

CREATE TABLE silver.dim_audience (
    audience_key     SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    audience_segment VARCHAR(50) NOT NULL UNIQUE,
    targeting_type   VARCHAR(20) NOT NULL CHECK (targeting_type IN
                     ('Retargeting','Interest','Lookalike','Demographic')), -- enrichment
    dwh_create_date  TIMESTAMP   NOT NULL DEFAULT now()
);

-- snowflaked off dim_brand
CREATE TABLE silver.dim_campaign (
    campaign_key    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_id     INT         NOT NULL UNIQUE,   -- natural key from source
    campaign_name   VARCHAR(50) NOT NULL,
    brand_key       SMALLINT    NOT NULL REFERENCES silver.dim_brand,
    objective       VARCHAR(20) NOT NULL CHECK (objective IN
                    ('Awareness','Consideration','Conversion','Engagement')),
    start_date      DATE        NOT NULL,
    end_date        DATE        NOT NULL,
    days_active     INT         NOT NULL,
    dwh_create_date TIMESTAMP   NOT NULL DEFAULT now(),
    CHECK (end_date >= start_date)
);

CREATE TABLE silver.dim_date (
    date_key        DATE PRIMARY KEY,
    year            SMALLINT    NOT NULL,
    quarter         SMALLINT    NOT NULL,
    month_num       SMALLINT    NOT NULL,
    month_start     DATE        NOT NULL,
    month_name      VARCHAR(9)  NOT NULL,
    iso_week        VARCHAR(10) NOT NULL,  -- ISO 8601, e.g. 2024-W32
    week_label      VARCHAR(10) NOT NULL,  -- source convention: Python
                                           -- strftime('%Y-W%U'), Sunday-start —
                                           -- matches the CSVs and the dashboard
    week_start      DATE        NOT NULL,  -- Monday
    day_of_week     VARCHAR(9)  NOT NULL,
    day_num_iso     SMALLINT    NOT NULL,  -- 1=Mon .. 7=Sun
    is_weekend      BOOLEAN     NOT NULL,
    dwh_create_date TIMESTAMP   NOT NULL DEFAULT now()
);

CREATE TABLE silver.fact_campaign_daily (
    fact_key       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key       DATE     NOT NULL REFERENCES silver.dim_date,
    campaign_key   SMALLINT NOT NULL REFERENCES silver.dim_campaign,
    platform_key   SMALLINT NOT NULL REFERENCES silver.dim_platform,
    ad_format_key  SMALLINT NOT NULL REFERENCES silver.dim_ad_format,
    audience_key   SMALLINT NOT NULL REFERENCES silver.dim_audience,
    -- additive measures (raw counts / money)
    impressions        BIGINT        NOT NULL CHECK (impressions >= 0),
    reach              BIGINT        NOT NULL CHECK (reach >= 0),
    spend              NUMERIC(14,2) NOT NULL CHECK (spend >= 0),
    clicks             BIGINT        NOT NULL CHECK (clicks >= 0),
    engagements        BIGINT        NOT NULL CHECK (engagements >= 0),
    likes              BIGINT        NOT NULL,
    comments           BIGINT        NOT NULL,
    shares             BIGINT        NOT NULL,
    saves              BIGINT        NOT NULL,
    video_views        BIGINT        NOT NULL,
    video_views_25pct  BIGINT        NOT NULL,
    video_views_50pct  BIGINT        NOT NULL,
    video_views_75pct  BIGINT        NOT NULL,
    video_views_100pct BIGINT        NOT NULL,
    conversions        BIGINT        NOT NULL CHECK (conversions >= 0),
    revenue            NUMERIC(14,2) NOT NULL CHECK (revenue >= 0),
    -- derived columns (recomputed from counts, never copied from the export)
    frequency        NUMERIC(8,2),
    cpm              NUMERIC(10,2),
    ctr              NUMERIC(10,4),
    cpc              NUMERIC(10,2),
    cpa              NUMERIC(10,2),
    cvr              NUMERIC(10,4),
    roas             NUMERIC(10,4),
    engagement_rate  NUMERIC(10,4),
    vtr              NUMERIC(10,4),
    net_revenue      NUMERIC(14,2) GENERATED ALWAYS AS (revenue - spend) STORED,
    -- enrichments
    days_into_campaign INT NOT NULL,
    frequency_bin      VARCHAR(10),
    dwh_create_date    TIMESTAMP NOT NULL DEFAULT now(),
    -- sanity constraints at write time
    CHECK (reach <= impressions),
    CHECK (clicks <= impressions),
    UNIQUE (date_key, campaign_key, platform_key, ad_format_key, audience_key)
);

-- Targets are true source data (not derivable from the fact) -> own silver table
CREATE TABLE silver.fact_pacing_target (
    pacing_key        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campaign_key      SMALLINT      NOT NULL REFERENCES silver.dim_campaign,
    platform_key      SMALLINT      NOT NULL REFERENCES silver.dim_platform,
    month_start       DATE          NOT NULL,
    budget_target     NUMERIC(14,2) NOT NULL CHECK (budget_target >= 0),
    impression_target BIGINT        NOT NULL CHECK (impression_target >= 0),
    conversion_target BIGINT        NOT NULL CHECK (conversion_target >= 0),
    dwh_create_date   TIMESTAMP     NOT NULL DEFAULT now(),
    UNIQUE (campaign_key, platform_key, month_start)
);

-- Indexes for analytics access paths
CREATE INDEX idx_fact_daily_date     ON silver.fact_campaign_daily (date_key);
CREATE INDEX idx_fact_daily_campaign ON silver.fact_campaign_daily (campaign_key);
CREATE INDEX idx_fact_daily_platform ON silver.fact_campaign_daily (platform_key);
CREATE INDEX idx_fact_daily_format   ON silver.fact_campaign_daily (ad_format_key);
CREATE INDEX idx_fact_daily_audience ON silver.fact_campaign_daily (audience_key);
