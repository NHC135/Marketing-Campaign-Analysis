/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process
    to populate the 'silver' schema tables from the 'bronze' schema.
    Actions Performed:
    - Truncates the silver tables (Full Load).
    - Inserts transformed and cleansed data from bronze into silver tables:
        Standardization : TRIM + whitespace collapse on all label columns;
                          'YYYY-MM' month strings -> first-of-month DATE
        Normalization   : brand / platform / format / audience / campaign
                          broken out into conformed dimensions (snowflake)
        Deduplication   : pacing target rows deduped (source has exact dups)
        Derived Columns : ctr, cpm, cpc, cpa, cvr, roas, engagement_rate, vtr,
                          frequency RECOMPUTED from raw counts
        Enrichment      : gap-free calendar; targeting_type; is_video_format;
                          days_into_campaign; creative-fatigue frequency bins

Usage Example:
    CALL silver.load_silver();

Note (PostgreSQL translation of the original MSSQL pattern):
    PRINT -> RAISE NOTICE ; BEGIN TRY/CATCH -> EXCEPTION WHEN OTHERS
===============================================================================
*/

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    start_time       TIMESTAMP;
    end_time         TIMESTAMP;
    batch_start_time TIMESTAMP;
    batch_end_time   TIMESTAMP;
BEGIN
    batch_start_time := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Silver Layer';
    RAISE NOTICE '================================================';

    RAISE NOTICE '>> Truncating Silver Tables (Full Load)';
    TRUNCATE TABLE silver.fact_campaign_daily,
                   silver.fact_pacing_target,
                   silver.dim_campaign,
                   silver.dim_ad_format,
                   silver.dim_audience,
                   silver.dim_brand,
                   silver.dim_platform,
                   silver.dim_date
        RESTART IDENTITY CASCADE;

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading Dimension Tables';
    RAISE NOTICE '------------------------------------------------';

    -- ------------------------------------------------------------------
    start_time := clock_timestamp();
    RAISE NOTICE '>> Inserting Data Into: silver.dim_platform';
    INSERT INTO silver.dim_platform (platform_name)
    SELECT DISTINCT btrim(regexp_replace(platform, '\s+', ' ', 'g'))
    FROM bronze.fact_campaign_daily
    ORDER BY 1;

    RAISE NOTICE '>> Inserting Data Into: silver.dim_brand';
    INSERT INTO silver.dim_brand (brand_name)
    SELECT DISTINCT btrim(regexp_replace(brand, '\s+', ' ', 'g'))
    FROM bronze.fact_campaign_daily
    ORDER BY 1;

    RAISE NOTICE '>> Inserting Data Into: silver.dim_ad_format';
    INSERT INTO silver.dim_ad_format (platform_key, ad_format_name, is_video_format)
    SELECT DISTINCT
        p.platform_key,
        btrim(regexp_replace(f.ad_format, '\s+', ' ', 'g')),
        -- enrichment: format ever delivers video views -> video format
        max(f.video_views) OVER (PARTITION BY f.platform, f.ad_format) > 0
    FROM bronze.fact_campaign_daily f
    JOIN silver.dim_platform p ON p.platform_name = btrim(f.platform)
    ORDER BY 1, 2;

    RAISE NOTICE '>> Inserting Data Into: silver.dim_audience';
    INSERT INTO silver.dim_audience (audience_segment, targeting_type)
    SELECT DISTINCT
        btrim(regexp_replace(audience_segment, '\s+', ' ', 'g')),
        CASE
            WHEN audience_segment ILIKE 'Retargeting%' THEN 'Retargeting'
            WHEN audience_segment ILIKE 'Interest%'    THEN 'Interest'
            WHEN audience_segment ILIKE 'Lookalike%'   THEN 'Lookalike'
            ELSE 'Demographic'
        END
    FROM bronze.fact_campaign_daily
    ORDER BY 1;

    RAISE NOTICE '>> Inserting Data Into: silver.dim_campaign';
    INSERT INTO silver.dim_campaign
        (campaign_id, campaign_name, brand_key, objective,
         start_date, end_date, days_active)
    SELECT
        f.campaign_id,
        btrim(regexp_replace(min(f.campaign_name), '\s+', ' ', 'g')),
        min(b.brand_key),
        min(btrim(f.objective)),
        min(f.date),
        max(f.date),
        max(f.date) - min(f.date) + 1
    FROM bronze.fact_campaign_daily f
    JOIN silver.dim_brand b ON b.brand_name = btrim(f.brand)
    GROUP BY f.campaign_id
    ORDER BY 1;

    RAISE NOTICE '>> Inserting Data Into: silver.dim_date (gap-free calendar)';
    INSERT INTO silver.dim_date
        (date_key, year, quarter, month_num, month_start, month_name,
         iso_week, week_label, week_start, day_of_week, day_num_iso, is_weekend)
    SELECT
        d::date,
        extract(year FROM d)::smallint,
        extract(quarter FROM d)::smallint,
        extract(month FROM d)::smallint,
        date_trunc('month', d)::date,
        to_char(d, 'FMMonth'),
        to_char(d, 'IYYY') || '-W' || to_char(d, 'IW'),
        -- Python %U: Sunday-start week-of-year; days before first Sunday = W00
        to_char(d, 'YYYY') || '-W' ||
            lpad(floor((extract(doy FROM d) - 1 - extract(dow FROM d) + 7) / 7)::text, 2, '0'),
        date_trunc('week', d)::date,
        to_char(d, 'FMDay'),
        extract(isodow FROM d)::smallint,
        extract(isodow FROM d) IN (6, 7)
    FROM generate_series(
            (SELECT min(date) FROM bronze.fact_campaign_daily),
            (SELECT max(date) FROM bronze.fact_campaign_daily),
            interval '1 day') AS d;

    end_time := clock_timestamp();
    RAISE NOTICE '>> Load Duration: % seconds',
                 round(extract(epoch FROM end_time - start_time)::numeric, 2);
    RAISE NOTICE '>> -------------';

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading Fact Tables';
    RAISE NOTICE '------------------------------------------------';

    -- ------------------------------------------------------------------
    start_time := clock_timestamp();
    RAISE NOTICE '>> Inserting Data Into: silver.fact_campaign_daily';
    INSERT INTO silver.fact_campaign_daily (
        date_key, campaign_key, platform_key, ad_format_key, audience_key,
        impressions, reach, spend, clicks, engagements,
        likes, comments, shares, saves,
        video_views, video_views_25pct, video_views_50pct,
        video_views_75pct, video_views_100pct,
        conversions, revenue,
        frequency, cpm, ctr, cpc, cpa, cvr, roas, engagement_rate, vtr,
        days_into_campaign, frequency_bin)
    SELECT
        f.date,
        c.campaign_key,
        p.platform_key,
        af.ad_format_key,
        a.audience_key,
        f.impressions,
        f.reach,
        round(f.spend::numeric, 2),
        f.clicks,
        f.engagements,
        f.likes, f.comments, f.shares, f.saves,
        f.video_views,
        f.video_views_25pct, f.video_views_50pct,
        f.video_views_75pct, f.video_views_100pct,
        f.conversions,
        round(f.revenue::numeric, 2),
        -- derived metrics recomputed from counts (NULL when denominator = 0)
        round(f.impressions::numeric / nullif(f.reach, 0), 2),
        round(f.spend::numeric * 1000 / nullif(f.impressions, 0), 2),
        round(f.clicks::numeric * 100 / nullif(f.impressions, 0), 4),
        round(f.spend::numeric / nullif(f.clicks, 0), 2),
        round(f.spend::numeric / nullif(f.conversions, 0), 2),
        round(f.conversions::numeric * 100 / nullif(f.clicks, 0), 4),
        round(f.revenue::numeric / nullif(f.spend, 0)::numeric, 4),
        round(f.engagements::numeric * 100 / nullif(f.impressions, 0), 4),
        round(f.video_views_100pct::numeric * 100 / nullif(f.video_views, 0), 4),
        -- enrichments
        f.date - c.start_date + 1,
        CASE
            WHEN f.reach = 0 THEN NULL
            WHEN f.impressions::numeric / f.reach < 1.5 THEN '1.0-1.5'
            WHEN f.impressions::numeric / f.reach < 2.0 THEN '1.5-2.0'
            WHEN f.impressions::numeric / f.reach < 2.5 THEN '2.0-2.5'
            WHEN f.impressions::numeric / f.reach < 3.0 THEN '2.5-3.0'
            WHEN f.impressions::numeric / f.reach < 3.5 THEN '3.0-3.5'
            ELSE '3.5+'
        END
    FROM bronze.fact_campaign_daily f
    JOIN silver.dim_campaign  c  ON c.campaign_id      = f.campaign_id
    JOIN silver.dim_platform  p  ON p.platform_name    = btrim(f.platform)
    JOIN silver.dim_ad_format af ON af.platform_key    = p.platform_key
                                AND af.ad_format_name  = btrim(f.ad_format)
    JOIN silver.dim_audience  a  ON a.audience_segment = btrim(f.audience_segment);

    RAISE NOTICE '>> Inserting Data Into: silver.fact_pacing_target (deduplicated)';
    -- Targets only; actuals are recomputed in gold from the daily fact so
    -- pacing can never disagree with delivered numbers.
    INSERT INTO silver.fact_pacing_target
        (campaign_key, platform_key, month_start,
         budget_target, impression_target, conversion_target)
    SELECT DISTINCT
        c.campaign_key,
        p.platform_key,
        to_date(btrim(pr.month) || '-01', 'YYYY-MM-DD'),
        round(pr.budget_target::numeric, 2),
        pr.impression_target,
        pr.conversion_target
    FROM bronze.pacing_report pr
    JOIN silver.dim_campaign c ON c.campaign_name = btrim(pr.campaign_name)
    JOIN silver.dim_platform p ON p.platform_name = btrim(pr.platform);

    end_time := clock_timestamp();
    RAISE NOTICE '>> Load Duration: % seconds',
                 round(extract(epoch FROM end_time - start_time)::numeric, 2);
    RAISE NOTICE '>> -------------';

    batch_end_time := clock_timestamp();
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Loading Silver Layer is Completed';
    RAISE NOTICE '   - Total Load Duration: % seconds',
                 round(extract(epoch FROM batch_end_time - batch_start_time)::numeric, 2);
    RAISE NOTICE '==========================================';

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'ERROR OCCURRED DURING LOADING SILVER LAYER';
    RAISE NOTICE 'Error Message: %', SQLERRM;
    RAISE NOTICE 'Error State  : %', SQLSTATE;
    RAISE NOTICE '==========================================';
    RAISE;
END;
$$;
