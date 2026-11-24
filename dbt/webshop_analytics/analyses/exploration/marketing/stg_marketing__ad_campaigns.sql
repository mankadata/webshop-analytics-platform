-- Exploration: stg_marketing__ad_campaigns
-- Q1: Platforms - currency, date coverage, duplicates and plausibility
select
    platform,
    currency,
    count(*)                                                        as rows,
    count(distinct (report_date, campaign_id))                      as distinct_campaign_days,
    count(*) - count(distinct (report_date, campaign_id))           as duplicate_rows,
    count(distinct campaign_id)                                     as campaigns,
    min(report_date)                                                as first_day,
    max(report_date)                                                as last_day,
    (max(report_date) - min(report_date) + 1) - count(distinct report_date)
                                                                    as days_without_report,
    count(*) filter (where clicks > impressions)                    as more_clicks_than_impressions,
    count(*) filter (where spend_local < 0 or clicks < 0 or impressions < 0)
                                                                    as negative_values,
    round(sum(spend_local), 2)                                      as total_spend_local
from staging.stg_marketing__ad_campaigns
group by 1, 2
order by 1, 2;

-- Finding: Clean data. Spend comes in three currencies (DQ07). Late Meta reports
--          (DQ13) arrive complete one day later - a timeliness issue handled by
--          source freshness, not by the model.
-- Fix in intermediate: spend in EUR with the ECB rate of the report day;
--          platform mapped to a marketing channel.

