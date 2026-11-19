-- Staging: ERP suppliers. Hungarian column names translated to English.
with source as (
    select * from {{ source('erp', 'suppliers') }}
),

renamed as (
    select
        szallito_kod                                as supplier_code,
        nev                                         as supplier_name,
        orszag                                      as country_code,
        penznem                                     as currency,
        cast(fizetesi_hatarido_nap as integer)      as payment_terms_days,
        rogzitve                                    as recorded_on_raw,     -- '2025.01.01.' (DQ06)
        _batch_id,
        _loaded_at
    from source
)

select * from renamed