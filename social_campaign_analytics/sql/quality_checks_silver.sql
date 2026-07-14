/*
===============================================================================
Quality Checks: Silver Layer
===============================================================================
Script Purpose:
    This script performs various quality checks for data consistency, accuracy,
    and standardization across the 'silver' schema. It includes checks for:
    - Null or duplicate primary/natural keys.
    - Unwanted spaces in string fields.
    - Data standardization and consistency.
    - Invalid date ranges and funnel ordering.
    - Data consistency between related fields and the bronze source.

Usage Notes:
    - Run these checks after loading the Silver layer (CALL silver.load_silver()).
    - Investigate and resolve any discrepancies found during the checks.
    - Unless stated otherwise, Expectation: No Results.
===============================================================================
*/

-- ====================================================================
-- Checking 'silver.dim_campaign'
-- ====================================================================
-- Check for NULLs or Duplicates in Natural Key
-- Expectation: No Results
SELECT campaign_id, count(*)
FROM silver.dim_campaign
GROUP BY campaign_id
HAVING count(*) > 1 OR campaign_id IS NULL;

-- Check for Unwanted Spaces
-- Expectation: No Results
SELECT campaign_name
FROM silver.dim_campaign
WHERE campaign_name != btrim(campaign_name);

-- Data Standardization & Consistency: objective domain
-- Expectation: exactly Awareness / Consideration / Conversion / Engagement
SELECT DISTINCT objective FROM silver.dim_campaign ORDER BY 1;

-- ====================================================================
-- Checking 'silver.dim_audience'
-- ====================================================================
-- Check for Unwanted Spaces
-- Expectation: No Results
SELECT audience_segment
FROM silver.dim_audience
WHERE audience_segment != btrim(audience_segment);

-- Data Standardization & Consistency: targeting_type domain
-- Expectation: Retargeting / Interest / Lookalike / Demographic only
SELECT DISTINCT targeting_type FROM silver.dim_audience ORDER BY 1;

-- ====================================================================
-- Checking 'silver.dim_date'
-- ====================================================================
-- Check for Calendar Gaps (gap-free date spine)
-- Expectation: No Results
SELECT d.date_key + 1 AS missing_from
FROM silver.dim_date d
LEFT JOIN silver.dim_date nxt ON nxt.date_key = d.date_key + 1
WHERE nxt.date_key IS NULL
  AND d.date_key < (SELECT max(date_key) FROM silver.dim_date);

-- Check week_label matches the source export's week convention (Python %U)
-- Expectation: No Results
SELECT DISTINCT b.date, b.week AS source_week, d.week_label
FROM bronze.fact_campaign_daily b
JOIN silver.dim_date d ON d.date_key = b.date
WHERE d.week_label != b.week;

-- ====================================================================
-- Checking 'silver.fact_campaign_daily'
-- ====================================================================
-- Check for Duplicate Grain Keys
-- (date × campaign × platform × ad_format × audience must be unique)
-- Expectation: No Results
SELECT date_key, campaign_key, platform_key, ad_format_key, audience_key, count(*)
FROM silver.fact_campaign_daily
GROUP BY date_key, campaign_key, platform_key, ad_format_key, audience_key
HAVING count(*) > 1;

-- Row Completeness: bronze row count must equal silver row count (1:1 load)
-- Expectation: No Results
SELECT b.cnt AS bronze_rows, s.cnt AS silver_rows
FROM (SELECT count(*) AS cnt FROM bronze.fact_campaign_daily) b,
     (SELECT count(*) AS cnt FROM silver.fact_campaign_daily) s
WHERE b.cnt != s.cnt;

-- Check for Invalid Date Ranges (campaign window is Jul–Dec 2024)
-- Expectation: No Results
SELECT date_key
FROM silver.fact_campaign_daily
WHERE date_key < DATE '2024-07-01' OR date_key > DATE '2024-12-31';

-- Check Funnel Ordering & Video Completion Consistency
-- (reach <= impressions, clicks <= impressions, conversions <= clicks,
--  video completions <= video views)
-- Expectation: No Results
SELECT fact_key, impressions, reach, clicks, conversions,
       video_views, video_views_100pct
FROM silver.fact_campaign_daily
WHERE reach > impressions
   OR clicks > impressions
   OR conversions > clicks
   OR video_views_100pct > video_views;

-- Check for Negative Measures
-- Expectation: No Results
SELECT fact_key
FROM silver.fact_campaign_daily
WHERE impressions < 0 OR reach < 0 OR spend < 0 OR clicks < 0
   OR engagements < 0 OR conversions < 0 OR revenue < 0;

-- Check Implausible Metric Ranges (marketing sanity)
-- Expectation: No Results
SELECT fact_key, ctr, frequency, roas, engagement_rate, cvr, vtr
FROM silver.fact_campaign_daily
WHERE ctr > 25 OR frequency > 20 OR roas > 200
   OR engagement_rate > 100 OR cvr > 100 OR vtr > 100;

-- Data Consistency: recomputed derived metrics vs source export
-- (tolerance for rounding in the export: ctr 0.01pp, roas 0.01x, cpa $0.05)
-- Expectation: No Results
SELECT s.fact_key, s.ctr, b.ctr AS src_ctr, s.roas, b.roas AS src_roas
FROM bronze.fact_campaign_daily b
JOIN silver.dim_campaign  c  ON c.campaign_id      = b.campaign_id
JOIN silver.dim_platform  p  ON p.platform_name    = btrim(b.platform)
JOIN silver.dim_ad_format af ON af.platform_key    = p.platform_key
                            AND af.ad_format_name  = btrim(b.ad_format)
JOIN silver.dim_audience  a  ON a.audience_segment = btrim(b.audience_segment)
JOIN silver.fact_campaign_daily s
  ON (s.date_key, s.campaign_key, s.platform_key, s.ad_format_key, s.audience_key)
   = (b.date, c.campaign_key, p.platform_key, af.ad_format_key, a.audience_key)
WHERE abs(coalesce(s.ctr, 0)  - b.ctr::numeric)  > 0.01
   OR abs(coalesce(s.roas, 0) - b.roas::numeric) > 0.01
   OR (b.conversions > 0 AND abs(coalesce(s.cpa, 0) - b.cpa::numeric) > 0.05);

-- Check for Orphaned Foreign Keys (belt-and-braces on top of FK constraints)
-- Expectation: No Results
SELECT f.fact_key
FROM silver.fact_campaign_daily f
LEFT JOIN silver.dim_date     d ON d.date_key     = f.date_key
LEFT JOIN silver.dim_campaign c ON c.campaign_key = f.campaign_key
LEFT JOIN silver.dim_audience a ON a.audience_key = f.audience_key
WHERE d.date_key IS NULL OR c.campaign_key IS NULL OR a.audience_key IS NULL;

-- ====================================================================
-- Checking 'silver.fact_pacing_target'
-- ====================================================================
-- Known Source Defect (surfaced, not hidden): duplicate rows in the bronze
-- pacing export. Silver deduplicates them on load.
-- Expectation: one row showing the duplicate count (27 in the current export)
SELECT count(*) - count(DISTINCT (brand, campaign_name, platform, month,
       budget_target, impression_target, conversion_target, actual_spend))
       AS duplicate_rows_in_bronze_pacing_report
FROM bronze.pacing_report;

-- Dedup Effectiveness: silver must hold exactly the distinct target set
-- Expectation: No Results
SELECT b.cnt AS distinct_bronze_targets, s.cnt AS silver_targets
FROM (SELECT count(DISTINCT (campaign_name, platform, month)) AS cnt
      FROM bronze.pacing_report) b,
     (SELECT count(*) AS cnt FROM silver.fact_pacing_target) s
WHERE b.cnt != s.cnt;

-- ====================================================================
-- Checking Dimension Cardinalities
-- ====================================================================
-- Expectation: brands=3, platforms=3, campaigns=9, audiences=10, formats=13
SELECT (SELECT count(*) FROM silver.dim_brand)     AS brands,
       (SELECT count(*) FROM silver.dim_platform)  AS platforms,
       (SELECT count(*) FROM silver.dim_campaign)  AS campaigns,
       (SELECT count(*) FROM silver.dim_audience)  AS audiences,
       (SELECT count(*) FROM silver.dim_ad_format) AS ad_formats;
