import pandas as pd
import numpy as np 
from scipy import stats

filepath = r'C:\Users\natha\Downloads\social_campaign_analytics\fact_campaign_daily.csv'
df = pd.read_csv(filepath) #.csv address
df["date"] = pd.to_datetime(df['date'])

#-----------------------------------------
# statistical lift: weekend vs. weekday for different metric performances
# Real lift testing compares exposed vs control - 
# no holdout group so we use weekend and weekday
#-----------------------------------------

results = []

for platform in df['platform'].unique():
    for metric, col in [('ROAS', 'roas'), ('CTR','ctr'), ('CPA', 'cpa'), ('CVR','cvr')]: 
        plat_df = df[df["platform"] == platform] 
        weekend = plat_df[plat_df["is_weekend"] == True][col].dropna()
        weekday = plat_df[plat_df["is_weekend"] == False][col].dropna() 

        # safeguard for minimum degrees of freedom
        if len(weekend) < 10 or len(weekday) < 10: 
            continue

        # finding the p-value for the weekend vs weekday for all metrics
        t_stat, p_val = stats.ttest_ind(weekend, weekday)
        lift = (weekend.mean() - weekday.mean()) / weekday.mean() * 100 

        if p_val < 0.05: 
            if metric == 'CPA': 
                interpretation = 'Weekday outperforms' if lift < 0 else 'Weekend outperforms'
            else: 
                interpretation = 'Weekend outperforms' if lift > 0 else 'Weekday outperforms'
        else: 
            interpretation = 'no significance'

        results.append({
            'Platform': platform, 
            'Metric': metric,
            'Weekday Avg': round(weekday.mean(), 4), 
            'Weekend Avg': round(weekend.mean(), 4),
            'Lift %': round(lift, 2), 
            'p_val' : p_val
            'Significant': ['Yes' if p_val < 0.5 else 'No'], 
            'Interpretation': interpretation
            })    

# print results
print(f"{platform}: ") 
print(f" weekday ROAS: {weekday.mean():.2f}")
print(f" weekend ROAS: {weekend.mean():.2f}")
print(f" Lift:         {lift:+.1f}%")
print(f" p-value:      {p_val:.4f}")
print(f" Significant:  {p_val < 0.05}\n")

# export results to a csv files for PowerBI DB
export = r'C:\Users\natha\Downloads\social_campaign_analytics\weekend_weekday_lift.csv'
pd.DataFrame(results).to_csv(export)
print("your file has exported successfully!")