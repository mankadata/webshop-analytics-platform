-- Exploration: stg_payments__events

select * from staging.stg_payments__events

-- Event types, duplicates (webhook retries) and test events
select
    event_type,
    count(*)                                                    as row_count,
    count(distinct event_id)                                    as distinct_events,
    count(*) - count(distinct event_id)                         as retried_rows,
    count(*) filter (where not is_livemode)                     as test_events,
    count(*) filter (where failure_code is not null)            as with_failure_code,
    count(distinct payment_id)                                  as payments,
    min(order_reference)                                        as example_reference
from staging.stg_payments__events
group by event_type
order by row_count desc;

-- Finding: 272 webhook retries - the provider sent the same event again (DQ02).
--          106 successful charges are test transactions (livemode = false, DQ10).
--          994 refunds = 994 orders with returns. Failure codes appear only on
--          failed charges. Order reference format: 'WS-100001' (WS- + order_id).
-- Fix in intermediate: keep one row per event_id; flag test events; order_id
--          parsed from the reference.

-- Order reference formats and links to orders
select
    is_livemode,
    regexp_replace(order_reference, '[0-9]', '9', 'g')          as reference_shape,
    count(distinct e.event_id)                                  as events,
    count(distinct e.event_id) filter (where o.order_id is not null)
                                                                as linked_to_order,
    min(order_reference)                                        as example
from staging.stg_payments__events as e
left join intermediate.int_shop__orders_cleaned as o
    on o.order_id = cast(nullif(regexp_replace(e.order_reference, '\D', '', 'g'), '') as integer)
group by 1, 2
order by events desc;

-- Finding: Every live event links to an existing order. Test events are marked
--          twice (livemode = false and the 'WS-TEST-' prefix) and never link to an
--          order. 18,699 + 103 = 18,802 distinct events.
-- Fix in intermediate: order_id = digits of the reference for live events;
--          test events flagged with dq_issue 'test_transaction', is_valid = false.


-- Q3: amount_minor vs order total - what is the divisor per currency?
with order_totals as (
    select
        o.order_id,
        o.currency,
        sum(i.net_amount_local) + o.shipping_fee_local          as order_total_local
    from intermediate.int_shop__orders_cleaned as o
    join intermediate.int_shop__order_items_cleaned as i
        on i.order_id = o.order_id
    group by o.order_id, o.currency, o.shipping_fee_local
),

charges as (
    select distinct on (event_id)
        cast(regexp_replace(order_reference, '\D', '', 'g') as integer)   as order_id,
        amount_minor,
        currency
    from staging.stg_payments__events
    where event_type = 'charge.succeeded' and is_livemode
)

select
    c.currency                                                  as payment_currency,
    t.currency                                                  as order_currency,
    count(*)                                                    as charges,
    percentile_cont(0.5) within group
        (order by c.amount_minor / nullif(t.order_total_local, 0))  as median_ratio,
    count(*) filter (where c.amount_minor = round(t.order_total_local * 100))
                                                                as exact_match_x100
from charges as c
join order_totals as t
    on t.order_id = c.order_id
group by 1, 2
order by 1, 2;


-- Finding: amount_minor is in hundredths for both currencies (HUF too), so
--          amount = amount_minor / 100. Payment currency always equals the order
--          currency. 16,992 of 17,303 live charges match the order total to the
--          cent; the 311 differences are investigated in the finance reconciliation.
-- Fix in intermediate: amount = amount_minor / 100.

