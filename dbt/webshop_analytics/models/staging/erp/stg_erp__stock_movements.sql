-- Staging: ERP stock movements. Hungarian dates and numbers stay text until intermediate.
with source as (
    select * from {{ source('erp', 'stock_movements') }}
),

renamed as (
    select
        cast(mozgas_azon as integer)                as movement_id,
        datum                                       as movement_date_raw,   -- '2025.01.01.' (DQ06)
        raktar                                      as warehouse_code,
        cikkszam                                    as sku_raw,             -- casing and spaces vary (DQ04)
        mozgasnem                                   as movement_code,       -- BEV, ELAD, VISSZ, LELT (DQ11)
        cast(mennyiseg as integer)                  as quantity,            -- some sales booked negative (DQ09)
        egysegar_eur                                as unit_cost_eur_raw,   -- '15,94' (DQ08)
        nullif(bizonylat, '')                       as reference,
        nullif(megjegyzes, '')                      as note,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed