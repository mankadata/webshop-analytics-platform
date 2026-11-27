-- Check 1: duplicates removed? (rows = distinct events)
select count(*) as rows, count(distinct event_id) as distinct_events
from intermediate.int_web__events_cleaned;

-- Check 2: funnel per channel
select
    channel,
    count(*)                                                    as sessions,
    count(*) filter (where has_added_to_cart)                   as added_to_cart,
    count(*) filter (where has_purchased)                       as purchases,
    round(100.0 * count(*) filter (where has_purchased) / count(*), 2)
                                                                as conversion_pct
from intermediate.int_web__sessions
group by channel
order by sessions desc;

-- Finding: Email converts best, paid social worst - compared with spend in marts (ROAS).