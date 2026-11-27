-- Exploration: stg_web__events
-- Q1: Event types and duplicates
select
    event_name,
    count(*)                                        as rows,
    count(distinct event_id)                        as distinct_events,
    count(*) - count(distinct event_id)             as duplicate_rows,
    count(distinct session_id)                      as sessions,
    count(*) filter (where customer_id is not null) as logged_in,
    count(*) filter (where order_id is not null)    as with_order
from staging.stg_web__events
group by event_name
order by rows desc;

-- Finding: 3,015 duplicate events (DQ02). Funnel: 395k sessions -> 224k product
--          views -> 67k add to cart -> 30k checkouts -> 14.4k purchases (3.6 %).
--          Every session starts with exactly one page_view; every purchase event
--          carries the customer and the order id.
-- Fix in intermediate: keep one row per event_id; sessions with channel in a
--          separate model.


-- Q2: UTM source / medium pairs (per session, first event)
select
    lower(trim(utm_source_raw))                     as utm_source,
    lower(trim(utm_medium_raw))                     as utm_medium,
    utm_source_raw                                  as example_source,
    utm_medium_raw                                  as example_medium,
    count(distinct session_id)                      as sessions
from staging.stg_web__events
group by 1, 2, 3, 4
order by utm_source, utm_medium, sessions desc;


select
    lower(trim(utm_source_raw))     as utm_source,
    lower(trim(utm_medium_raw))     as utm_medium,
    count(distinct session_id)      as sessions
from staging.stg_web__events
group by 1, 2
order by 1, 2;


-- Finding: 5 marketing channels hide behind 12 source/medium spellings (DQ11).
-- Fix in intermediate: seed utm_channels.csv maps every pair to a channel and an
--          ad platform; no UTM tags = 'direct'; an unknown pair = 'unmapped'.