{{ config(materialized='table') }}

-- Intermediate (silver): one row per web session with its marketing channel and
-- funnel steps. The channel comes from the UTM tags of the first event (seed
-- utm_channels); a session without UTM tags is 'direct'.

with events as (
    select * from {{ ref('int_web__events_cleaned') }}
),

channels as (
    select * from {{ ref('utm_channels') }}
),

-- UTM tags and device of the first event of each session
first_event as (
    select distinct on (session_id)
        session_id,
        utm_source,
        utm_medium,
        utm_campaign,
        device_category
    from events
    order by session_id, event_at, event_id
),

per_session as (
    select
        session_id,
        min(anonymous_id)                                           as anonymous_id,
        max(customer_id)                                            as customer_id,
        min(event_at)                                               as session_started_at,
        max(event_at)                                               as session_ended_at,
        count(*)                                                    as event_count,

        -- funnel steps reached in the session
        bool_or(event_name = 'view_item')                           as has_viewed_item,
        bool_or(event_name = 'add_to_cart')                         as has_added_to_cart,
        bool_or(event_name = 'begin_checkout')                      as has_begun_checkout,
        bool_or(event_name = 'purchase')                            as has_purchased,

        max(order_id)                                               as order_id,
        sum(purchase_value)                                         as purchase_value,
        max(purchase_currency)                                      as purchase_currency
    from events
    group by session_id
),

final as (
    select
        per_session.session_id,
        per_session.anonymous_id,
        per_session.customer_id,
        per_session.session_started_at,
        per_session.session_ended_at,
        first_event.device_category,

        first_event.utm_source,
        first_event.utm_medium,
        first_event.utm_campaign,
        case
            when first_event.utm_source is null and first_event.utm_medium is null
                then 'direct'
            else coalesce(channels.channel, 'unmapped')
        end                                                         as channel,
        channels.platform,

        per_session.event_count,
        per_session.has_viewed_item,
        per_session.has_added_to_cart,
        per_session.has_begun_checkout,
        per_session.has_purchased,
        per_session.order_id,
        per_session.purchase_value,
        per_session.purchase_currency
    from per_session
    left join first_event
        on first_event.session_id = per_session.session_id
    left join channels
        on  channels.utm_source = first_event.utm_source
        and channels.utm_medium = first_event.utm_medium
)

select * from final