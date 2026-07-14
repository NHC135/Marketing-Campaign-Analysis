/*
===============================================================================
DDL Script: Create Gold Views
===============================================================================
Script Purpose:
    This script creates views for the Gold layer in the data warehouse.
    The Gold layer represents the final business-level tables (analytics-ready),
    one set of views per Power BI dashboard page ("Market Campaign.pbix"):

        Dashboard page        Gold view(s)
        ─────────────────     ──────────────────────────────────────────
        Executive Summary  -> vw_executive_kpis, vw_campaign_summary,
                              vw_platform_summary
        Performance Trends -> vw_daily_kpi_trend, vw_monthly_spend,
                              vw_weekly_trend, vw_weekend_weekday_lift
        Audience Analysis  -> vw_audience_performance
        Creative & Format  -> vw_format_performance, vw_creative_fatigue
        Funnel Analysis    -> vw_funnel_stages, vw_funnel_pass_through
        Pacing Report      -> vw_pacing_report, vw_pacing_status_summary

    Each view performs transformations and combines data from the Silver layer
    to produce clean, enriched, and business-ready datasets.

Usage:
    These views can be queried directly for analytics and reporting.
    "Blended" ratios are always ratio-of-sums (sum(x)/sum(y)), matching the
    dashboard's KPI cards — never averages of row-level ratios.
===============================================================================
*/

-- =============================================================================
-- Create Base View: gold.vw_fact_enriched (fact joined to all dimensions)
-- =============================================================================
CREATE OR REPLACE VIEW gold.vw_fact_enriched AS
SELECT
    f.*,
    d.iso_week, d.week_label, d.month_start, d.month_name, d.year, d.quarter,
    d.day_of_week, d.is_weekend,
    b.brand_name,
    c.campaign_id, c.campaign_name, c.objective, c.days_active,
    p.platform_name,
    af.ad_format_name, af.is_video_format,
    a.audience_segment, a.targeting_type
FROM silver.fact_campaign_daily f
JOIN silver.dim_date      d  ON d.date_key       = f.date_key
JOIN silver.dim_campaign  c  ON c.campaign_key   = f.campaign_key
JOIN silver.dim_brand     b  ON b.brand_key      = c.brand_key
JOIN silver.dim_platform  p  ON p.platform_key   = f.platform_key
JOIN silver.dim_ad_format af ON af.ad_format_key = f.ad_format_key
JOIN silver.dim_audience  a  ON a.audience_key   = f.audience_key;

-- =============================================================================
-- PAGE 1: Executive Summary
-- =============================================================================

-- KPI cards: Revenue, Blended ROAS, Conversions, Spend, CTR, CPA, Impressions
CREATE OR REPLACE VIEW gold.vw_executive_kpis AS
SELECT
    round(sum(revenue), 2)                                            AS total_revenue,
    round(sum(revenue) / nullif(sum(spend), 0), 2)                    AS blended_roas,
    sum(conversions)                                                  AS total_conversions,
    round(sum(spend), 2)                                              AS total_spend,
    round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 2) AS blended_ctr_pct,
    round(sum(spend) / nullif(sum(conversions), 0), 2)                AS blended_cpa,
    sum(impressions)                                                  AS total_impressions,
    round(sum(conversions)::numeric * 100 / nullif(sum(clicks),0), 2) AS blended_cvr_pct
FROM silver.fact_campaign_daily;

-- Campaign table (replaces campaign_summary.csv)
CREATE OR REPLACE VIEW gold.vw_campaign_summary AS
SELECT
    brand_name, campaign_name, objective, platform_name,
    round(sum(spend), 2)                                              AS total_spend,
    sum(impressions)                                                  AS total_impressions,
    sum(reach)                                                        AS total_reach,
    sum(clicks)                                                       AS total_clicks,
    sum(conversions)                                                  AS total_conversions,
    round(sum(revenue), 2)                                            AS total_revenue,
    sum(engagements)                                                  AS total_engagements,
    count(DISTINCT date_key)                                          AS days_active,
    round(sum(spend) * 1000 / nullif(sum(impressions), 0), 2)         AS avg_cpm,
    round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 4) AS avg_ctr_pct,
    round(sum(spend) / nullif(sum(conversions), 0), 2)                AS avg_cpa,
    round(sum(revenue) / nullif(sum(spend), 0), 4)                    AS roas,
    round(sum(spend) / nullif(count(DISTINCT date_key), 0), 2)        AS daily_spend
FROM gold.vw_fact_enriched
GROUP BY brand_name, campaign_name, objective, platform_name;

-- ROAS-per-platform bar + platform table (replaces platform_summary.csv)
CREATE OR REPLACE VIEW gold.vw_platform_summary AS
SELECT
    platform_name,
    round(sum(spend), 2)                                              AS total_spend,
    sum(impressions)                                                  AS total_impressions,
    sum(reach)                                                        AS total_reach,
    sum(clicks)                                                       AS total_clicks,
    sum(engagements)                                                  AS total_engagements,
    sum(video_views)                                                  AS total_video_views,
    sum(conversions)                                                  AS total_conversions,
    round(sum(revenue), 2)                                            AS total_revenue,
    round(sum(spend) * 1000 / nullif(sum(impressions), 0), 2)         AS avg_cpm,
    round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 4) AS avg_ctr_pct,
    round(sum(conversions)::numeric * 100 / nullif(sum(clicks),0), 4) AS avg_cvr_pct,
    round(sum(spend) / nullif(sum(conversions), 0), 2)                AS avg_cpa,
    round(sum(revenue) / nullif(sum(spend), 0), 4)                    AS roas,
    round(sum(engagements)::numeric * 100 / nullif(sum(impressions),0), 4)
                                                                      AS engagement_rate_pct
FROM gold.vw_fact_enriched
GROUP BY platform_name;

-- =============================================================================
-- PAGE 2: Performance Trends
-- =============================================================================

CREATE OR REPLACE VIEW gold.vw_daily_kpi_trend AS
SELECT
    date_key, platform_name, brand_name, objective,
    round(sum(spend), 2)                                              AS spend,
    sum(impressions)                                                  AS impressions,
    round(sum(revenue) / nullif(sum(spend), 0), 4)                    AS blended_roas,
    round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 4) AS blended_ctr_pct,
    round(sum(conversions)::numeric * 100 / nullif(sum(clicks),0), 4) AS blended_cvr_pct,
    round(sum(spend) / nullif(sum(conversions), 0), 2)                AS blended_cpa
FROM gold.vw_fact_enriched
GROUP BY date_key, platform_name, brand_name, objective;

CREATE OR REPLACE VIEW gold.vw_monthly_spend AS
SELECT
    month_start, month_name, platform_name,
    round(sum(spend), 2)   AS total_spend,
    round(sum(revenue), 2) AS total_revenue
FROM gold.vw_fact_enriched
GROUP BY month_start, month_name, platform_name;

-- Weekly ROAS + spend (replaces weekly_trend.csv). week_label uses the source
-- exports' Sunday-start convention so it lines up with the dashboard axis.
CREATE OR REPLACE VIEW gold.vw_weekly_trend AS
SELECT
    week_label, platform_name, objective,
    round(sum(spend), 2)                                              AS spend,
    sum(impressions)                                                  AS impressions,
    sum(clicks)                                                       AS clicks,
    sum(conversions)                                                  AS conversions,
    round(sum(revenue), 2)                                            AS revenue,
    sum(engagements)                                                  AS engagements,
    sum(video_views)                                                  AS video_views,
    round(sum(spend) * 1000 / nullif(sum(impressions), 0), 2)         AS cpm,
    round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 4) AS ctr_pct,
    round(sum(revenue) / nullif(sum(spend), 0), 4)                    AS roas,
    round(sum(spend) / nullif(sum(conversions), 0), 2)                AS cpa
FROM gold.vw_fact_enriched
GROUP BY week_label, platform_name, objective;

-- Weekend vs Weekday lift table, recomputed in SQL (replaces the Python t-test
-- output weekend_weekday_lift.csv). Welch's two-sample t statistic on daily
-- row-level metric values; |t| > 1.96 ~ significant at p < 0.05.
-- CPA uses coalesce(cpa, 0): the source export writes cpa = 0 on days with no
-- conversions and the original t-test included those zeros, so we mirror that
-- methodology to stay reconcilable with the dashboard's lift table.
CREATE OR REPLACE VIEW gold.vw_weekend_weekday_lift AS
WITH daily_metrics AS (
    SELECT platform_name, is_weekend, m.metric, m.value
    FROM gold.vw_fact_enriched f
    CROSS JOIN LATERAL (VALUES
        ('ROAS', f.roas), ('CTR', f.ctr),
        ('CPA', coalesce(f.cpa, 0)), ('CVR', f.cvr)
    ) AS m(metric, value)
    WHERE m.value IS NOT NULL
),
stats AS (
    SELECT platform_name, metric,
        avg(value)      FILTER (WHERE NOT is_weekend) AS wd_avg,
        var_samp(value) FILTER (WHERE NOT is_weekend) AS wd_var,
        count(*)        FILTER (WHERE NOT is_weekend) AS wd_n,
        avg(value)      FILTER (WHERE is_weekend)     AS we_avg,
        var_samp(value) FILTER (WHERE is_weekend)     AS we_var,
        count(*)        FILTER (WHERE is_weekend)     AS we_n
    FROM daily_metrics
    GROUP BY platform_name, metric
)
SELECT
    platform_name, metric,
    round(wd_avg, 4)                                      AS weekday_avg,
    round(we_avg, 4)                                      AS weekend_avg,
    round((we_avg - wd_avg) * 100 / nullif(wd_avg, 0), 2) AS lift_pct,
    round((we_avg - wd_avg)
        / nullif(sqrt(we_var / we_n + wd_var / wd_n), 0), 3) AS welch_t,
    CASE WHEN abs((we_avg - wd_avg)
        / nullif(sqrt(we_var / we_n + wd_var / wd_n), 0)) > 1.96
        THEN 'Yes' ELSE 'No' END                          AS significant,
    CASE
        WHEN abs((we_avg - wd_avg)
            / nullif(sqrt(we_var / we_n + wd_var / wd_n), 0)) <= 1.96
            THEN 'no significance'
        WHEN (metric = 'CPA') = (we_avg < wd_avg)   -- CPA: lower is better
            THEN 'Weekend outperforms'
        ELSE 'Weekday outperforms'
    END                                                   AS interpretation
FROM stats;

-- =============================================================================
-- PAGE 3: Audience Analysis
-- =============================================================================
-- Scorecard + bubble chart (replaces audience_performance.csv).
-- composite_score: equal-weight min-max blend of ROAS, CTR, CVR and inverted
-- CPA, normalized across all brand × platform × segment rows.
CREATE OR REPLACE VIEW gold.vw_audience_performance AS
WITH agg AS (
    SELECT
        brand_name, platform_name, audience_segment, targeting_type,
        round(sum(spend), 2)                                              AS total_spend,
        sum(impressions)                                                  AS total_impressions,
        sum(clicks)                                                       AS total_clicks,
        sum(conversions)                                                  AS total_conversions,
        round(sum(revenue), 2)                                            AS total_revenue,
        sum(engagements)                                                  AS total_engagements,
        round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 4) AS avg_ctr_pct,
        round(sum(spend) / nullif(sum(conversions), 0), 2)                AS avg_cpa,
        round(sum(revenue) / nullif(sum(spend), 0), 4)                    AS roas,
        round(sum(conversions)::numeric * 100 / nullif(sum(clicks),0), 4) AS cvr_pct
    FROM gold.vw_fact_enriched
    GROUP BY brand_name, platform_name, audience_segment, targeting_type
),
norm AS (
    SELECT *,
        (roas        - min(roas)        OVER ()) / nullif(max(roas)        OVER () - min(roas)        OVER (), 0) AS n_roas,
        (avg_ctr_pct - min(avg_ctr_pct) OVER ()) / nullif(max(avg_ctr_pct) OVER () - min(avg_ctr_pct) OVER (), 0) AS n_ctr,
        (cvr_pct     - min(cvr_pct)     OVER ()) / nullif(max(cvr_pct)     OVER () - min(cvr_pct)     OVER (), 0) AS n_cvr,
        (avg_cpa     - min(avg_cpa)     OVER ()) / nullif(max(avg_cpa)     OVER () - min(avg_cpa)     OVER (), 0) AS n_cpa
    FROM agg
)
SELECT
    brand_name, platform_name, audience_segment, targeting_type,
    total_spend, total_impressions, total_clicks, total_conversions,
    total_revenue, total_engagements, avg_ctr_pct, avg_cpa, roas, cvr_pct,
    round((n_roas + n_ctr + n_cvr + (1 - n_cpa)) / 4, 2)         AS composite_score,
    round(roas - avg(roas) OVER (PARTITION BY platform_name), 4) AS roas_lift_vs_platform_avg
FROM norm;

-- =============================================================================
-- PAGE 4: Creative & Format
-- =============================================================================
-- Format scorecard (replaces format_performance.csv), with the dashboard's
-- format_score + performance tier.
CREATE OR REPLACE VIEW gold.vw_format_performance AS
WITH agg AS (
    SELECT
        platform_name, ad_format_name, is_video_format,
        round(sum(spend), 2)                                              AS total_spend,
        sum(impressions)                                                  AS total_impressions,
        sum(clicks)                                                       AS total_clicks,
        sum(conversions)                                                  AS total_conversions,
        round(sum(revenue), 2)                                            AS total_revenue,
        sum(engagements)                                                  AS total_engagements,
        sum(video_views)                                                  AS total_video_views,
        round(sum(spend) * 1000 / nullif(sum(impressions), 0), 2)         AS avg_cpm,
        round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 4) AS avg_ctr_pct,
        round(sum(spend) / nullif(sum(conversions), 0), 2)                AS avg_cpa,
        round(sum(revenue) / nullif(sum(spend), 0), 4)                    AS roas,
        round(sum(engagements)::numeric * 100 / nullif(sum(impressions),0), 4)
                                                                          AS engagement_rate_pct
    FROM gold.vw_fact_enriched
    GROUP BY platform_name, ad_format_name, is_video_format
),
norm AS (
    SELECT *,
        (roas    - min(roas)    OVER ()) / nullif(max(roas)    OVER () - min(roas)    OVER (), 0) AS n_roas,
        (avg_ctr_pct - min(avg_ctr_pct) OVER ()) / nullif(max(avg_ctr_pct) OVER () - min(avg_ctr_pct) OVER (), 0) AS n_ctr,
        (engagement_rate_pct - min(engagement_rate_pct) OVER ())
            / nullif(max(engagement_rate_pct) OVER () - min(engagement_rate_pct) OVER (), 0)      AS n_er,
        (avg_cpa - min(avg_cpa) OVER ()) / nullif(max(avg_cpa) OVER () - min(avg_cpa) OVER (), 0) AS n_cpa
    FROM agg
)
SELECT *,
    round((n_roas + n_ctr + n_er + (1 - n_cpa)) / 4, 2) AS format_score,
    CASE
        WHEN (n_roas + n_ctr + n_er + (1 - n_cpa)) / 4 >= 0.65 THEN 'Top Performer'
        WHEN (n_roas + n_ctr + n_er + (1 - n_cpa)) / 4 <  0.30 THEN 'Underperformer'
        ELSE 'Average'
    END AS performance_tier
FROM norm;

-- Creative fatigue: blended KPIs per frequency bin (replaces ad_fatigue.py)
CREATE OR REPLACE VIEW gold.vw_creative_fatigue AS
SELECT
    platform_name, frequency_bin,
    count(*)                                                          AS observations,
    round(sum(clicks)::numeric * 100 / nullif(sum(impressions),0), 4) AS blended_ctr_pct,
    round(sum(engagements)::numeric * 100 / nullif(sum(impressions),0), 4)
                                                                      AS blended_engagement_rate_pct,
    round(sum(revenue) / nullif(sum(spend), 0), 4)                    AS blended_roas
FROM gold.vw_fact_enriched
WHERE frequency_bin IS NOT NULL
GROUP BY platform_name, frequency_bin;

-- =============================================================================
-- PAGE 5: Funnel Analysis
-- =============================================================================

-- Funnel chart stages, overall and per brand × platform
CREATE OR REPLACE VIEW gold.vw_funnel_stages AS
WITH agg AS (
    SELECT
        brand_name, platform_name,
        sum(impressions) AS impressions, sum(reach) AS reach,
        sum(video_views) AS video_views, sum(engagements) AS engagements,
        sum(clicks) AS clicks, sum(conversions) AS conversions
    FROM gold.vw_fact_enriched
    GROUP BY GROUPING SETS ((brand_name, platform_name), ())
)
SELECT
    coalesce(brand_name, 'ALL')    AS brand_name,
    coalesce(platform_name, 'ALL') AS platform_name,
    s.stage, s.stage_order, s.volume,
    round(s.volume::numeric * 100 / nullif(agg.impressions, 0), 2) AS pct_of_impressions
FROM agg
CROSS JOIN LATERAL (VALUES
    ('impressions', 1, agg.impressions),
    ('reach',       2, agg.reach),
    ('video_views', 3, agg.video_views),
    ('engagements', 4, agg.engagements),
    ('clicks',      5, agg.clicks),
    ('conversions', 6, agg.conversions)
) AS s(stage, stage_order, volume);

-- Pass-through rate table (replaces funnel_analysis.csv):
--   awareness->consideration = clicks/impressions %,
--   consideration->intent    = engagements/clicks %,
--   intent->conversion       = conversions/engagements %.
CREATE OR REPLACE VIEW gold.vw_funnel_pass_through AS
SELECT
    brand_name, platform_name,
    sum(impressions)       AS impressions,
    sum(reach)             AS reach,
    sum(video_views)       AS video_views,
    sum(clicks)            AS clicks,
    sum(engagements)       AS engagements,
    sum(conversions)       AS conversions,
    round(sum(revenue), 2) AS revenue,
    round(sum(spend), 2)   AS spend,
    round(sum(clicks)::numeric      * 100 / nullif(sum(impressions), 0), 4) AS awareness_to_consideration_pct,
    round(sum(engagements)::numeric * 100 / nullif(sum(clicks), 0), 4)      AS consideration_to_intent_pct,
    round(sum(conversions)::numeric * 100 / nullif(sum(engagements), 0), 4) AS intent_to_conversion_pct,
    round(sum(conversions)::numeric * 100 / nullif(sum(impressions), 0), 6) AS overall_conversion_rate_pct,
    round(sum(spend) / nullif(sum(impressions), 0), 6)                      AS cost_per_impression,
    round(sum(revenue) / nullif(sum(spend), 0), 4)                          AS roas
FROM gold.vw_fact_enriched
GROUP BY brand_name, platform_name;

-- =============================================================================
-- PAGE 6: Pacing Report
-- =============================================================================
-- Actuals recomputed from the silver fact and joined to targets, so pacing can
-- never disagree with delivered numbers (fixes source rows where actuals were
-- zeroed but still labeled Overpacing).
CREATE OR REPLACE VIEW gold.vw_pacing_report AS
WITH monthly_actuals AS (
    SELECT campaign_key, platform_key, month_start,
        sum(spend) AS actual_spend, sum(impressions) AS actual_impressions,
        sum(conversions) AS actual_conversions, sum(revenue) AS actual_revenue
    FROM gold.vw_fact_enriched
    GROUP BY campaign_key, platform_key, month_start
)
SELECT
    b.brand_name,
    c.campaign_name,
    p.platform_name,
    t.month_start,
    t.budget_target, t.impression_target, t.conversion_target,
    round(coalesce(a.actual_spend, 0), 2)   AS actual_spend,
    coalesce(a.actual_impressions, 0)       AS actual_impressions,
    coalesce(a.actual_conversions, 0)       AS actual_conversions,
    round(coalesce(a.actual_revenue, 0), 2) AS actual_revenue,
    round(coalesce(a.actual_spend, 0)       * 100 / nullif(t.budget_target, 0), 2)     AS spend_pacing_pct,
    round(coalesce(a.actual_impressions, 0) * 100 / nullif(t.impression_target, 0), 2) AS impression_pacing_pct,
    round(coalesce(a.actual_conversions, 0) * 100 / nullif(t.conversion_target, 0), 2) AS conversion_pacing_pct,
    round(coalesce(a.actual_spend, 0) - t.budget_target, 2)                            AS spend_variance,
    CASE
        WHEN coalesce(a.actual_spend, 0) * 100 / nullif(t.budget_target, 0) > 110 THEN 'Overpacing'
        WHEN coalesce(a.actual_spend, 0) * 100 / nullif(t.budget_target, 0) < 90  THEN 'Underpacing'
        ELSE 'On Track'
    END AS pacing_status
FROM silver.fact_pacing_target t
JOIN silver.dim_campaign c ON c.campaign_key = t.campaign_key
JOIN silver.dim_brand    b ON b.brand_key    = c.brand_key
JOIN silver.dim_platform p ON p.platform_key = t.platform_key
LEFT JOIN monthly_actuals a
       ON  a.campaign_key = t.campaign_key
       AND a.platform_key = t.platform_key
       AND a.month_start  = t.month_start;

-- Donut + KPI cards on the pacing page
CREATE OR REPLACE VIEW gold.vw_pacing_status_summary AS
SELECT
    pacing_status,
    count(*)                                           AS campaign_month_rows,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 2) AS pct_of_rows,
    round(avg(spend_pacing_pct), 2)                    AS avg_spend_pacing_pct,
    round(sum(spend_variance), 2)                      AS total_spend_variance
FROM gold.vw_pacing_report
GROUP BY pacing_status;
