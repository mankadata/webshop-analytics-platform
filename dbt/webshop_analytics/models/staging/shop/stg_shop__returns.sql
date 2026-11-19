-- Staging: returned order lines.
with source as (
    select * from {{ source('shop', 'returns') }}
),

renamed as (
    select
        cast(return_id as integer)              as return_id,
        cast(order_id as integer)               as order_id,
        cast(order_item_id as integer)          as order_item_id,
        cast(quantity as integer)               as quantity,
        reason_code,
        cast(requested_at as timestamp)         as requested_at_local,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed