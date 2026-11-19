-- Staging: shop orders. One row per order status change, exactly as delivered.
-- Nothing is filtered out here (just in intermediate layer).

with source as (
    select * from {{ source('shop', 'orders') }}
),

renamed as (
    select
        cast(order_id as integer)               as order_id,
        cast(customer_id as integer)            as customer_id,
        cast(ordered_at as timestamp)           as ordered_at_local,    -- shop time (Budapest), no offset
        nullif(lower(trim(status)), '')         as status,              -- empty string -> null (DQ01)
        upper(trim(currency))                   as currency,
        payment_method,
        sales_channel,
        shipping_country,
        cast(shipping_fee as numeric(12, 2))    as shipping_fee_local,  -- in the order's currency
        cast(updated_at as timestamp)           as updated_at_local,    -- when this status was set
        _batch_id,
        _loaded_at
    from source
)

select * from renamed