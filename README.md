# Social Campaign Analytics

Analysis toolkit for evaluating paid social campaign performance across Meta, TikTok, and YouTube, covering audience targeting, creative fatigue, and day-of-week timing effects. Includes a Power BI dashboard built on the resulting data.

---
## Data

Source exports live in `social_campaign_analytics_raw_data/`:

| File | Grain | Description |
|---|---|---|
| `fact_campaign_daily.csv` | Campaign × platform × ad format × audience × day | Core fact table; daily spend, delivery, engagement, and outcome metrics |
| `campaign_summary.csv` | Campaign × platform | Totals and averages rolled up per campaign |
| `platform_summary.csv` | Platform | Totals and averages rolled up per platform |
| `weekly_trend.csv` | Week × platform × objective | Weekly performance trend |
| `format_performance.csv` | Platform × ad format | Performance by creative format (e.g. Meta: Carousel/Reels/Stories/Single Image/Video; TikTok: TopView/In-feed/Spark/Branded Hashtag; YouTube: Bumper Ad) |
| `audience_performance.csv` | Brand × platform × audience segment | Performance by audience segment |
| `funnel_analysis.csv` | Brand × platform | Funnel conversion rates (awareness → consideration → intent → conversion) |
| `pacing_report.csv` | Brand × campaign × platform × month | Budget/impression/conversion pacing vs. target |

Key metrics used throughout: `roas`, `ctr`, `cvr`, `cpa`, `cpm`, `cpc`, `frequency`, `engagement_rate`, `vtr` (video completion rate).

Three brands are represented in the sample data — ByteBrew, NovaSkin, and UrbanFit — across Awareness, Consideration, Conversion, and Engagement objectives.

---
## Data Model

The Power BI dashboard is built on a star schema: `fact_campaign_daily` at the center, joined to four dimension tables, created by Power Query.

`fact_campaign_daily` is the hub, with one row per campaign × platform × ad format × audience segment × day. Each dimension joins to it one-to-many:  

<img width="730" height="633" alt="data modelling" src="https://github.com/user-attachments/assets/8931ffd8-8fda-45c4-9d11-d28e65807cef" />

| Dimension | Key | Attributes | Joins to fact on |
|---|---|---|---|
| `dim_date` | `date` | day_of_week, is_weekend, month, quarter, week_of_year, year | `date` |
| `dim_campaign` | `campaign_id` | campaign_name, brand, objective, platform | `campaign_id` |
| `dim_audience` | `audience_segment` | brand, platform | `audience_segment` |
| `dim_platform` | `platform` | ad_format, audience_segment, objective | `platform` |

`fact_campaign_daily` also carries the full metric set (impressions, reach, spend, revenue, roas, ctr, cvr, clicks, conversions, cpa, etc.) — see the fact table description in Data.

---
## Business Questions

Questions this project is built to answer, and where each is addressed:

| Question | Answered by | Key finding |
|---|---|---|
| Which platform delivers the best return on ad spend? | `platform_summary.csv`; Dashboard - Executive Summary | TikTok leads at 12.04x blended ROAS vs. Meta 9.40x and YouTube 1.56x |
| Which individual campaigns are winning or losing, and should any be cut or reworked? | `campaign_summary.csv`; Dashboard - Executive Summary | Black Friday Promo returns 17.04x ROAS; Summer Glow Launch (1.33x) and Brand Awareness Push (1.85x) underperform on spend of $50-85K each |
| Does performance differ between weekdays and weekends, and should scheduling or bidding shift accordingly? | `Weekday_vs_Weekend_lift.py` - `weekend_weekday_lift.csv`; Dashboard - Performance Trends | Weekend ROAS is significantly higher on all three platforms (Meta +43%, TikTok +22%, YouTube +52%); Meta CPA also drops 28% on weekends |
| Which audience segments deliver the most efficient spend, and where should targeting budget concentrate? | `audience_lift.py`; Dashboard - Audience Analysis | Retargeting - Cart Abandoners ($19.62 ROAS) and 25-34 Male ($17.49 ROAS) outperform prospecting segments like Lookalike 1% ($8.45 ROAS) on Meta |
| At what ad frequency does creative fatigue set in, and should frequency caps change? | `ad_fatigue.py` - `creative_fatigue.csv`; Dashboard - Creative & Format | CTR holds relatively flat across frequency bins in the current data - no sharp fatigue cliff detected yet within the observed range |
| Which ad formats perform best on each platform, and should the format mix be reallocated? | `format_performance.csv`; Dashboard - Creative & Format | TikTok TopView (13.15x) and In-feed Ad (12.88x) are top performers; YouTube Bumper Ad (1.55x, $84 CPA) is the weakest format overall |
| Where in the funnel is the biggest drop-off, and which stage most needs optimization? | `funnel_analysis.csv`; Dashboard - Funnel Analysis | Reach-to-video-view holds reasonably (71% to 29%), but the drop from video views to engagement is steep (29.35% to 3.73% of impressions) |
| Do funnel conversion rates vary meaningfully by brand or platform? | `funnel_analysis.csv`; Dashboard - Funnel Analysis | UrbanFit converts at 9% intent-to-conversion across all three platforms vs. 5% for ByteBrew/NovaSkin, suggesting stronger bottom-funnel creative or offer |
| Which campaigns are over- or under-pacing against budget and targets? | `pacing_report.csv`; Dashboard - Pacing Report | Only 22% of campaigns are on track; 44% are underpacing and 33% are overpacing against budget targets |
| Is spend pacing translating into proportional conversion volume, or are we buying volume without results? | `pacing_report.csv`; Dashboard - Pacing Report | Product Launch Wave 1 is overspending at 164-165% of budget pace across all platforms while converting at only 61-100% of its conversion target |
---

## Analyses

**`Weekday_vs_Weekend_lift.py`** — Runs an independent-samples t-test per platform and metric (ROAS, CTR, CPA, CVR) comparing weekend vs. weekday performance, since there's no true holdout group for a controlled lift test. Flags statistically significant differences (p < 0.05) and which period wins. Outputs `weekend_weekday_lift.csv`.

**`Market Campaign.pbix`** — Power BI dashboard consuming the raw data and script outputs above, across six pages: Executive Summary, Performance Trends, Audience Analysis, Creative & Format, Funnel Analysis, and Pacing Report.

## Setup

```bash
pip install pandas numpy scipy
```
---

## Usage

Run each script from the project root:

```bash
python Weekday_vs_Weekend_lift.py
```

Note: `Weekday_vs_Weekend_lift.py` currently reference `fact_campaign_daily.csv` via a hardcoded local path — update the `filepath` variable at the top of each script if your CSVs live in `social_campaign_analytics_raw_data/` or a different location.

---

## Repository structure

```
social_campaign_analytics/
├── README.md
├── Weekday_vs_Weekend_lift.py
├── weekend_weekday_lift.csv
├── Market Campaign.pbix
└── social_campaign_analytics_raw_data/
    ├── fact_campaign_daily.csv
    ├── campaign_summary.csv
    ├── platform_summary.csv
    ├── weekly_trend.csv
    ├── format_performance.csv
    ├── audience_performance.csv
    ├── funnel_analysis.csv
    └── pacing_report.csv
```
