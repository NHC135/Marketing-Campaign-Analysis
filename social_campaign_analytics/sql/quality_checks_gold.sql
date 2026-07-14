/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Script Purpose:
    This script performs quality checks to validate the integrity, consistency,
    and accuracy of the Gold layer. These checks ensure:
    - Uniqueness of keys in the aggregated views.
    - Referential integrity between the fact and dimensions.
    - Reconciliation of gold recomputations against the pre-aggregated source
      CSVs the dashboard was originally fed from.
    - Reconciliation against the published Power BI dashboard PDF
      ("Market Campaign.pdf" — Executive Summary page), proving the warehouse
      backs the dashboard 1:1.

Usage Notes:
    - Run after creating the Gold views (ddl_gold.sql).
    - Investigate and resolve any discrepancies found during the checks.
    - Unless stated otherwise, Expectation: No Results.
===============================================================================
*/

-- ====================================================================
-- Checking 'gold.vw_fact_enriched'
-- ====================================================================
-- Check the enriched base view preserves the fact grain (no join fan-out)
-- Expectation: No Results
SELECT b.cnt AS fact_rows, g.cnt AS enriched_rows
FROM (SELECT count(*) AS cnt FROM silver.fact_campaign_daily) b,
     (SELECT count(*) AS cnt FROM gold.vw_fact_enriched) g
WHERE b.cnt != g.cnt;

-- ====================================================================
-- Reconciliation vs Pre-Aggregated Source CSVs
-- (gold views must be able to replace the CSV feeds 1:1)
-- ====================================================================

-- Platform totals vs platform_summary.csv (within $1 / 1 unit)
-- Expectation: No Results
SELECT g.platform_name, g.total_spend, b.total_spend AS src_spend,
       g.total_revenue, b.total_revenue AS src_revenue
FROM bronze.platform_summary b
JOIN gold.vw_platform_summary g ON g.platform_name = btrim(b.platform)
WHERE abs(g.total_spend       - b.total_spend::numeric)       > 1
   OR abs(g.total_revenue     - b.total_revenue::numeric)     > 1
   OR abs(g.total_conversions - b.total_conversions)          > 1
   OR abs(g.total_impressions - b.total_impressions)          > 1;

-- Campaign totals vs campaign_summary.csv
-- Expectation: No Results
SELECT g.campaign_name, g.platform_name, g.total_spend, b.total_spend AS src_spend,
       g.roas, b.roas AS src_roas
FROM bronze.campaign_summary b
JOIN gold.vw_campaign_summary g
  ON g.campaign_name = btrim(b.campaign_name)
 AND g.platform_name = btrim(b.platform)
WHERE abs(g.total_spend   - b.total_spend::numeric)   > 1
   OR abs(g.total_revenue - b.total_revenue::numeric) > 1
   OR abs(g.roas          - b.roas::numeric)          > 0.05;

-- Audience totals vs audience_performance.csv
-- Expectation: No Results
SELECT g.brand_name, g.platform_name, g.audience_segment
FROM bronze.audience_performance b
JOIN gold.vw_audience_performance g
  ON g.brand_name       = btrim(b.brand)
 AND g.platform_name    = btrim(b.platform)
 AND g.audience_segment = btrim(b.audience_segment)
WHERE abs(g.total_spend   - b.total_spend::numeric)   > 1
   OR abs(g.total_revenue - b.total_revenue::numeric) > 1;

-- Format totals vs format_performance.csv
-- Expectation: No Results
SELECT g.platform_name, g.ad_format_name
FROM bronze.format_performance b
JOIN gold.vw_format_performance g
  ON g.platform_name  = btrim(b.platform)
 AND g.ad_format_name = btrim(b.ad_format)
WHERE abs(g.total_spend   - b.total_spend::numeric)   > 1
   OR abs(g.total_revenue - b.total_revenue::numeric) > 1;

-- Funnel pass-through rates vs funnel_analysis.csv (within 0.01pp)
-- Expectation: No Results
SELECT g.brand_name, g.platform_name
FROM bronze.funnel_analysis b
JOIN gold.vw_funnel_pass_through g
  ON g.brand_name = btrim(b.brand) AND g.platform_name = btrim(b.platform)
WHERE abs(g.awareness_to_consideration_pct - b.awareness_to_consideration::numeric) > 0.01
   OR abs(g.consideration_to_intent_pct    - b.consideration_to_intent::numeric)    > 0.01
   OR abs(g.intent_to_conversion_pct       - b.intent_to_conversion::numeric)       > 0.01;

-- Weekly trend vs weekly_trend.csv (join on the source week convention)
-- Expectation: No Results
SELECT g.week_label, g.platform_name, g.objective,
       g.spend, b.spend AS src_spend, g.revenue, b.revenue AS src_revenue
FROM bronze.weekly_trend b
JOIN gold.vw_weekly_trend g
  ON g.week_label    = btrim(b.week)
 AND g.platform_name = btrim(b.platform)
 AND g.objective     = btrim(b.objective)
WHERE abs(g.spend   - b.spend::numeric)   > 1
   OR abs(g.revenue - b.revenue::numeric) > 1;

-- Weekend/weekday averages vs the Python t-test output (within 0.01)
-- Expectation: No Results
SELECT g.platform_name, g.metric,
       g.weekday_avg, b.weekday_avg AS py_weekday,
       g.weekend_avg, b.weekend_avg AS py_weekend
FROM bronze.weekend_weekday_lift b
JOIN gold.vw_weekend_weekday_lift g
  ON g.platform_name = btrim(b.platform) AND g.metric = btrim(b.metric)
WHERE abs(g.weekday_avg - b.weekday_avg::numeric) > 0.01
   OR abs(g.weekend_avg - b.weekend_avg::numeric) > 0.01;

-- ====================================================================
-- Reconciliation vs the Published Power BI Dashboard PDF
-- ("Market Campaign.pdf" — Executive Summary cards)
-- ====================================================================
-- Expectation: No Results
SELECT a.check_name, a.expected, a.actual
FROM gold.vw_executive_kpis k
CROSS JOIN LATERAL (VALUES
    ('pdf_total_revenue',     '6702764.38', k.total_revenue::text,
        abs(k.total_revenue - 6702764.38) < 1),
    ('pdf_total_spend',       '884981.87',  k.total_spend::text,
        abs(k.total_spend - 884981.87) < 1),
    ('pdf_blended_roas',      '7.57',       k.blended_roas::text,
        abs(k.blended_roas - 7.57) <= 0.01),
    ('pdf_blended_ctr',       '1.83',       k.blended_ctr_pct::text,
        abs(k.blended_ctr_pct - 1.83) <= 0.01),
    ('pdf_blended_cpa',       '16.96',      k.blended_cpa::text,
        abs(k.blended_cpa - 16.96) <= 0.01),
    ('pdf_total_impressions', '~102.63M',   k.total_impressions::text,
        abs(k.total_impressions - 102630000) < 500000),
    ('pdf_total_conversions', '~52K',       k.total_conversions::text,
        abs(k.total_conversions - 52000) < 1000)
) AS a(check_name, expected, actual, ok)
WHERE NOT a.ok;

-- Campaign-level ROAS anchors from the PDF campaign table (all-platform blended)
-- Expectation: No Results
SELECT x.name, x.pdf_roas, round(g.roas, 2) AS gold_roas
FROM (VALUES
    ('Black Friday Promo',   17.04),
    ('Summer Glow Launch',    1.33),
    ('Brand Awareness Push',  1.85),
    ('New Year New You',      8.25)
) AS x(name, pdf_roas)
JOIN LATERAL (
    SELECT sum(total_revenue) / nullif(sum(total_spend), 0) AS roas
    FROM gold.vw_campaign_summary
    WHERE campaign_name = x.name
) g ON true
WHERE abs(g.roas - x.pdf_roas) > 0.01;

-- Platform ROAS anchors from the PDF bar chart (TikTok 12.04, Meta 9.40, YouTube 1.56)
-- Expectation: No Results
SELECT x.platform, x.pdf_roas, round(g.roas, 2) AS gold_roas
FROM (VALUES
    ('TikTok', 12.04), ('Meta', 9.40), ('YouTube', 1.56)
) AS x(platform, pdf_roas)
JOIN gold.vw_platform_summary g ON g.platform_name = x.platform
WHERE abs(round(g.roas, 2) - x.pdf_roas) > 0.01;
