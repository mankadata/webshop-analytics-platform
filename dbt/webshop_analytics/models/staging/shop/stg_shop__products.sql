-- Staging: shop products. One row per product version (price change, delisting).

with source as (
    select * from {{ source('shop', 'products') }}
),

renamed as (
    select
        cast(product_id as integer)             as product_id,
        sku,
        product_name,
        category                                as category_raw,        -- 15+ spellings (DQ11)
        brand,
        cast(list_price_eur as numeric(12, 2))  as list_price_eur,
        weight                                  as weight_raw,          -- '350 g', '350g', '0,35 kg', 'n/a' (DQ07)
        warehouse_code,
        supplier_code,
        cast(is_active as boolean)              as is_active,
        cast(updated_at as timestamp)           as updated_at_local,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed