-- Staging: payment provider webhooks. One row per delivered webhook - retries (DQ02) and
-- test transactions (DQ10) included.
with source as (
    select * from {{ source('payments', 'events') }}
),

flattened as (
    select
        payload ->> 'id'                                                as event_id,
        payload ->> 'type'                                              as event_type,
        to_timestamp(cast(payload ->> 'created' as bigint))             as created_at,          -- epoch seconds -> timestamptz (UTC)
        cast(payload ->> 'livemode' as boolean)                         as is_livemode,         -- false = test transaction
        payload #>> '{data,object,id}'                                  as payment_id,
        payload #>> '{data,object,order_reference}'                     as order_reference,     -- 'WS-100001'
        cast(payload #>> '{data,object,amount}' as bigint)              as amount_minor,        -- minor units: 5285 = 52.85
        upper(payload #>> '{data,object,currency}')                     as currency,
        payload #>> '{data,object,payment_method_details,type}'         as payment_method_type,
        payload #>> '{data,object,payment_method_details,card,brand}'   as card_brand,
        payload #>> '{data,object,failure_code}'                        as failure_code,
        _batch_id,
        _loaded_at
    from source
)

select * from flattened