-- Staging: web analytics events. One row per delivered event - duplicates (DQ02) and
-- late arrivals (DQ12) included. Nested JSON flattened; UTM values kept as delivered (DQ11).
with source as (
    select * from {{ source('web', 'events') }}
),

flattened as (
    select
        payload ->> 'event_id'                                          as event_id,
        payload ->> 'event_name'                                        as event_name,          -- page_view, view_item, add_to_cart, begin_checkout, purchase
        cast(payload ->> 'event_timestamp' as timestamptz)              as event_at,            -- ISO-8601 UTC
        payload ->> 'session_id'                                        as session_id,
        payload ->> 'anonymous_id'                                      as anonymous_id,
        cast(payload ->> 'user_id' as integer)                          as customer_id,         -- null when not logged in
        payload #>> '{page,path}'                                       as page_path,
        payload #>> '{traffic_source,source}'                           as utm_source_raw,
        payload #>> '{traffic_source,medium}'                           as utm_medium_raw,
        payload #>> '{traffic_source,campaign}'                         as utm_campaign_raw,
        payload #>> '{device,category}'                                 as device_category,
        cast(payload #>> '{ecommerce,product_id}' as integer)           as product_id,
        cast(payload #>> '{ecommerce,order_id}' as integer)             as order_id,
        cast(payload #>> '{ecommerce,value}' as numeric(14, 2))         as purchase_value,
        payload #>> '{ecommerce,currency}'                              as purchase_currency,
        _batch_id,
        _loaded_at
    from source
)

select * from flattened