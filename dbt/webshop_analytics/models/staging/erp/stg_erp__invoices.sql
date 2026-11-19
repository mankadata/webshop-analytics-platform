-- Staging: ERP invoices and credit notes (JOVAIRAS). Hungarian number formats stay text (DQ08).
with source as (
    select * from {{ source('erp', 'invoices') }}
),

renamed as (
    select
        szamlaszam                                  as invoice_number,
        bizonylat_tipus                             as document_type,       -- SZAMLA = invoice, JOVAIRAS = credit note
        rendeles_azonosito                          as order_reference,     -- 'WS-100001'
        kelt                                        as invoice_date_raw,    -- '2025.01.01.'
        penznem                                     as currency,
        netto                                       as net_amount_raw,      -- '298 818' or '42,97'
        afa_kulcs                                   as vat_rate_raw,        -- '27%', '27', '27,00'
        afa_osszeg                                  as vat_amount_raw,
        brutto                                      as gross_amount_raw,
        vevo_orszag                                 as customer_country,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed