-- Check: spend per platform in EUR, every row converted
select
    platform,
    channel,
    currency,
    count(*)                                        as rows,
    count(*) filter (where spend_eur is null)       as missing_eur,
    round(sum(spend_local), 2)                      as spend_local,
    round(sum(spend_eur), 2)                        as spend_eur,
    round(avg(cost_per_click_eur), 4)               as avg_cpc_eur
from intermediate.int_marketing__ad_spend_cleaned
group by 1, 2, 3
order by spend_eur desc;