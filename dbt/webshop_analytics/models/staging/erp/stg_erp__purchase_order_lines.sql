-- Staging: ERP purchase order lines.
with source as (
    select * from {{ source('erp', 'purchase_order_lines') }}
),

renamed as (
    select
        po_szam                                     as po_number,
        cast(sor as integer)                        as line_number,
        cikkszam                                    as sku_raw,
        cast(mennyiseg as integer)                  as quantity,
        egysegar                                    as unit_cost_raw,       -- '1 299,90' (DQ08), supplier currency
        penznem                                     as currency,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed