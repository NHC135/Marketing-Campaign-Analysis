/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
===============================================================================
Script Purpose:
    This stored procedure loads data into the 'bronze' schema from external
    CSV files. It performs the following actions:
    - Truncates the bronze tables before loading data (Full Load).
    - Uses the COPY command to load data from CSV files to bronze tables.

Parameters:
    p_path : absolute path of the folder containing the source CSV files
             (the project root — weekend_weekday_lift.csv lives there, the
              rest under social_campaign_analytics_raw_data/).

Usage Example:
    CALL bronze.load_bronze('/path/to/social_campaign_analytics');

Note (PostgreSQL translation of the original MSSQL pattern):
    CREATE OR ALTER PROCEDURE  ->  CREATE OR REPLACE PROCEDURE
    BULK INSERT ... WITH (FIRSTROW=2, FIELDTERMINATOR=',')
                               ->  COPY ... WITH (FORMAT csv, HEADER true)
    PRINT                      ->  RAISE NOTICE
    BEGIN TRY / BEGIN CATCH    ->  BEGIN ... EXCEPTION WHEN OTHERS
    Server-side COPY requires the Postgres server to read p_path; from a
    restricted client use psql \copy with the same column lists instead.
===============================================================================
*/

-- Helper: truncate one bronze table and COPY one CSV into it, with timing
CREATE OR REPLACE PROCEDURE bronze.load_table(p_tbl TEXT, p_cols TEXT, p_csv TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    start_time TIMESTAMP;
    end_time   TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating Table: bronze.%', p_tbl;
    EXECUTE format('TRUNCATE TABLE bronze.%I', p_tbl);
    RAISE NOTICE '>> Inserting Data Into: bronze.%', p_tbl;
    EXECUTE format('COPY bronze.%I (%s) FROM %L WITH (FORMAT csv, HEADER true)',
                   p_tbl, p_cols, p_csv);
    end_time := clock_timestamp();
    RAISE NOTICE '>> Load Duration: % seconds',
                 round(extract(epoch FROM end_time - start_time)::numeric, 2);
    RAISE NOTICE '>> -------------';
END;
$$;

CREATE OR REPLACE PROCEDURE bronze.load_bronze(p_path TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    batch_start_time TIMESTAMP;
    batch_end_time   TIMESTAMP;
    raw              TEXT := p_path || '/social_campaign_analytics_raw_data';
BEGIN
    batch_start_time := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Bronze Layer';
    RAISE NOTICE '================================================';

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading Daily Fact Export';
    RAISE NOTICE '------------------------------------------------';

    CALL bronze.load_table('fact_campaign_daily',
        'campaign_id,brand,campaign_name,platform,ad_format,objective,audience_segment,'
     || 'date,month,week,day_of_week,is_weekend,impressions,reach,frequency,spend,cpm,'
     || 'clicks,ctr,engagements,likes,comments,shares,saves,engagement_rate,video_views,'
     || 'video_views_25pct,video_views_50pct,video_views_75pct,video_views_100pct,vtr,'
     || 'conversions,revenue,cpc,cpa,cvr,roas',
        raw || '/fact_campaign_daily.csv');

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading Pre-Aggregated Exports';
    RAISE NOTICE '------------------------------------------------';

    CALL bronze.load_table('campaign_summary',
        'brand,campaign_name,objective,platform,total_spend,total_impressions,total_reach,'
     || 'total_clicks,total_conversions,total_revenue,total_engagements,days_active,'
     || 'avg_cpm,avg_ctr,avg_cpa,roas,daily_spend',
        raw || '/campaign_summary.csv');

    CALL bronze.load_table('platform_summary',
        'platform,total_spend,total_impressions,total_reach,total_clicks,total_engagements,'
     || 'total_video_views,total_conversions,total_revenue,avg_cpm,avg_ctr,avg_cvr,avg_cpa,'
     || 'roas,engagement_rate',
        raw || '/platform_summary.csv');

    CALL bronze.load_table('weekly_trend',
        'week,platform,objective,spend,impressions,clicks,conversions,revenue,engagements,'
     || 'video_views,cpm,ctr,roas,cpa',
        raw || '/weekly_trend.csv');

    CALL bronze.load_table('format_performance',
        'platform,ad_format,total_spend,total_impressions,total_clicks,total_conversions,'
     || 'total_revenue,total_engagements,total_video_views,avg_cpm,avg_ctr,avg_cpa,roas,'
     || 'engagement_rate',
        raw || '/format_performance.csv');

    CALL bronze.load_table('audience_performance',
        'brand,platform,audience_segment,total_spend,total_impressions,total_clicks,'
     || 'total_conversions,total_revenue,total_engagements,avg_ctr,avg_cpa,roas,cvr',
        raw || '/audience_performance.csv');

    CALL bronze.load_table('funnel_analysis',
        'brand,platform,impressions,reach,video_views,clicks,engagements,conversions,'
     || 'revenue,spend,awareness_to_consideration,consideration_to_intent,'
     || 'intent_to_conversion,overall_conversion_rate,cost_per_impression,roas',
        raw || '/funnel_analysis.csv');

    CALL bronze.load_table('pacing_report',
        'brand,campaign_name,platform,month,budget_target,impression_target,'
     || 'conversion_target,actual_spend,actual_impressions,actual_conversions,'
     || 'actual_revenue,spend_pacing_pct,impression_pacing_pct,conversion_pacing_pct,'
     || 'spend_variance,pacing_status',
        raw || '/pacing_report.csv');

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Loading Analysis Outputs';
    RAISE NOTICE '------------------------------------------------';

    CALL bronze.load_table('weekend_weekday_lift',
        'row_id,platform,metric,weekday_avg,weekend_avg,lift_pct,significant,interpretation',
        p_path || '/weekend_weekday_lift.csv');

    batch_end_time := clock_timestamp();
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Loading Bronze Layer is Completed';
    RAISE NOTICE '   - Total Load Duration: % seconds',
                 round(extract(epoch FROM batch_end_time - batch_start_time)::numeric, 2);
    RAISE NOTICE '==========================================';

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'ERROR OCCURRED DURING LOADING BRONZE LAYER';
    RAISE NOTICE 'Error Message: %', SQLERRM;
    RAISE NOTICE 'Error State  : %', SQLSTATE;
    RAISE NOTICE '==========================================';
    RAISE;
END;
$$;
