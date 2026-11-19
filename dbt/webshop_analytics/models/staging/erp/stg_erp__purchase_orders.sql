-- Staging: ERP purchase order headers. One row per status event (NYITOTT = open, TELJESITVE = received).
with source as (
    select * from {{ source('erp', 'purchase_orders') }}
),

renamed as (
    select
        po_szam                                     as po_number,
        szallito_kod                                as supplier_code,
        rendeles_datum                              as order_date_raw,      -- '2025.01.04.' (DQ06)
        vart_datum                                  as expected_date_raw,
        statusz                                     as status_code,
        modositva                                   as modified_on_raw,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed