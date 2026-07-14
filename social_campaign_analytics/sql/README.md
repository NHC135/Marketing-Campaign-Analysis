# Postgres Medallion Warehouse — Social Campaign Analytics

PostgreSQL implementation of the data behind `Market Campaign.pbix` / `Market Campaign.pdf`, following the medallion architecture (bronze → silver → gold) with a snowflake data model. Script layout and conventions mirror the CRM/ERP SQL warehouse project (init_database → per-layer DDL → `proc_load_*` stored procedures → gold views → per-layer quality checks), PostgreSQL.

Verified end-to-end on PostgreSQL: the gold views reproduce the published Power BI dashboard PDF (revenue $6,702,764.38, blended ROAS 7.57x, CTR 1.83%, CPA $16.96, impressions 102.63M).

## Files & run order

```
# 1. Database + schemas (connects to the postgres maintenance DB; DROPS and
#    recreates social_campaign_dw — see WARNING in the script header)
psql -d postgres -f sql/init_database.sql

# 2. Bronze: raw tables + stored-procedure loader
psql  sql/ddl_bronze.sql
psql  sql/proc_load_bronze.sql
psql  "CALL bronze.load_bronze('/absolute/path/to/social_campaign_analytics')"

# 3. Silver: snowflake schema + ETL stored procedure (truncate & insert)
psql  sql/ddl_silver.sql
psql  sql/proc_load_silver.sql
psql  "CALL silver.load_silver()"

# 4. Gold: analytics-ready views
psql sql/ddl_gold.sql

# 5. Quality checks (unless a check states otherwise, expectation: no results)
psql sql/quality_checks_silver.sql
psql sql/quality_checks_gold.sql
```

## MSSQL → PostgreSQL translations used

`IF OBJECT_ID(...) DROP TABLE` → `DROP TABLE IF EXISTS`; `NVARCHAR(n)` → `VARCHAR(n)`; `FLOAT` → `DOUBLE PRECISION` (not `REAL` — 4-byte floats drop cents and break penny-level reconciliation); `BULK INSERT` → `COPY ... WITH (FORMAT csv, HEADER true)`; `PRINT` → `RAISE NOTICE`; `BEGIN TRY/CATCH` → `EXCEPTION WHEN OTHERS`; `GETDATE()` → `now()`; `CREATE OR ALTER PROCEDURE` → `CREATE OR REPLACE PROCEDURE`.

## Layers

**Bronze — "Ingest"** (`ddl_bronze.sql`, `proc_load_bronze.sql`) — one typed table per source CSV, loaded as-is (full load, truncate & insert) with per-table timing notices and error handling. Source defects are landed untouched: 27 exact duplicate pacing rows, float-styled integer columns, zeroed actuals mislabeled "Overpacing".

**Silver — "Clean"** (`ddl_silver.sql`, `proc_load_silver.sql`) — standardized, normalized, deduplicated snowflake schema with `dwh_create_date` audit columns. Ratio metrics (CTR, CPM, CPC, CPA, CVR, ROAS, engagement rate, VTR, frequency) are recomputed from raw counts rather than trusted from the export. 
Enrichments: gap-free calendar with both ISO and source (`%U`) week labels, targeting-type classification, video-format flags, `days_into_campaign`, creative-fatigue frequency bins, generated `net_revenue`.

Grain of `fact_campaign_daily`: date × campaign × platform × ad format × audience segment (enforced UNIQUE), with row-level CHECKs for funnel ordering and non-negativity.

**Gold — "Business"** (`ddl_gold.sql`) — views only, one set per dashboard page. Blended ratios are always ratio-of-sums, matching Power BI's measures.

| Dashboard page | Gold view(s) | Replaces CSV |
|---|---|---|
| Executive Summary | `vw_executive_kpis`, `vw_campaign_summary`, `vw_platform_summary` | campaign_summary, platform_summary |
| Performance Trends | `vw_daily_kpi_trend`, `vw_monthly_spend`, `vw_weekly_trend`, `vw_weekend_weekday_lift` | weekly_trend, weekend_weekday_lift |
| Audience Analysis | `vw_audience_performance` (composite score + platform lift) | audience_performance |
| Creative & Format | `vw_format_performance` (score + tier), `vw_creative_fatigue` | format_performance, creative_fatigue |
| Funnel Analysis | `vw_funnel_stages`, `vw_funnel_pass_through` | funnel_analysis |
| Pacing Report | `vw_pacing_report`, `vw_pacing_status_summary` | pacing_report |

## Quality checks

`quality_checks_silver.sql` — key uniqueness, unwanted spaces, domain standardization, calendar gaps, week-label convention, bronze→silver row completeness, funnel ordering, negative measures, implausible metric ranges, derived-metric consistency vs the export, FK orphans, pacing dedup effectiveness, dimension cardinalities.

`quality_checks_gold.sql` — join fan-out on the enriched base view; reconciliation of every gold view against its pre-aggregated source CSV (platform, campaign, audience, format, funnel, weekly trend, weekend lift); and dashboard that compare `vw_executive_kpis`, campaign ROAS, and platform ROAS against the printed PDF values.
