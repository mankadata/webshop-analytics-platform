-- Staging: order lines as delivered - duplicates (DQ02) and impossible values (DQ09) included.

with source as (
    select * from {{ source('shop', 'order_items') }}
),

renamed as (
    select
        cast(order_item_id as integer)          as order_item_id,
        cast(order_id as integer)               as order_id,
        cast(product_id as integer)             as product_id,
        cast(quantity as integer)               as quantity,
        cast(unit_price as numeric(14, 2))      as unit_price_local,    -- VAT included, order currency
        cast(discount_pct as integer)           as discount_pct,
        cast(created_at as timestamp)           as created_at_local,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed