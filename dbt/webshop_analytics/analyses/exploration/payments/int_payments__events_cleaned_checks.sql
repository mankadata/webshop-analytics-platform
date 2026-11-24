-- Check: one row per event, retries removed, test events flagged
-- expected: 18802 rows; charge.succeeded 17406 (103 test), refund 994, failed 402
select
    event_type,
    is_valid,
    count(*)                                    as events,
    count(distinct event_id)                    as distinct_events,
    count(*) filter (where delivery_count > 1)  as were_retried,
    sum(amount_local)                           as total_amount_local
from intermediate.int_payments__events_cleaned
group by 1, 2
order by 1, 2;