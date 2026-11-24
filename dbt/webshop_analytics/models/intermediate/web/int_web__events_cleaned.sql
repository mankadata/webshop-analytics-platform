{{ config(materialized='table') }}

-- Intermediate (silver): one row per web analytics event, deduplicated.
-- Rules come from analyses/exploration/web/stg_web__events.sql (Q1-Q2).
-- Materialized as a table: ~750k rows are read by the sessions model and by marts.

with events as (
    select * from {{ ref('stg_web__events') }}
),

-- Q1: the tracker sends some events twice -> keep one row per event_id
deduplicated as (
    select
        *,
        row_number() over (
            partition by event_id
            order by event_at
        )                                                           as copy_number
    from events
),

final as (
    select
        event_id,
        event_name,
        event_at,
        session_id,
        anonymous_id,
        customer_id,
        page_path,

        -- Q2: 'Facebook' and 'facebook' are the same source
        nullif(lower(trim(utm_source_raw)), '')                     as utm_source,
        nullif(lower(trim(utm_medium_raw)), '')                     as utm_medium,
        nullif(lower(trim(utm_campaign_raw)), '')                   as utm_campaign,

        device_category,
        product_id,
        order_id,
        purchase_value,
        purchase_currency
    from deduplicated
    where copy_number = 1
)

select * from final