-- Intermediate (silver): one row per ERP document (invoice or credit note), parsed.
-- Rules come from analyses/exploration/erp/stg_erp__invoices.sql (Q1-Q3).
-- The ERP exports Hungarian formats: '1 003 110', '-1 048,12', '27%', '2025.01.31.'

with invoices as (
    select * from {{ ref('stg_erp__invoices') }}
),

parsed as (
    select
        invoice_number,
        document_type,
        order_reference,
        currency,
        customer_country,

        to_date(invoice_date_raw, 'YYYY.MM.DD.')                                    as invoice_date,

        -- keep digits, comma and minus only, then comma -> decimal point
        cast(replace(regexp_replace(net_amount_raw,   '[^0-9,-]', '', 'g'), ',', '.') as numeric(14, 2))
                                                                                    as net_amount,
        cast(replace(regexp_replace(vat_amount_raw,   '[^0-9,-]', '', 'g'), ',', '.') as numeric(14, 2))
                                                                                    as vat_amount,
        cast(replace(regexp_replace(gross_amount_raw, '[^0-9,-]', '', 'g'), ',', '.') as numeric(14, 2))
                                                                                    as gross_amount,
        -- '27%', '27,00' and '27' -> 27
        cast(replace(regexp_replace(vat_rate_raw,     '[^0-9,]',  '', 'g'), ',', '.') as numeric(5, 2))
                                                                                    as vat_rate
    from invoices
),

final as (
    select
        invoice_number,
        case document_type
            when 'SZAMLA'   then 'invoice'
            when 'JOVAIRAS' then 'credit_note'
        end                                                                         as document_type,
        document_type = 'JOVAIRAS'                                                  as is_credit_note,

        -- 'WS-100001' -> 100001
        cast(nullif(regexp_replace(order_reference, '\D', '', 'g'), '') as integer) as order_id,
        invoice_date,
        currency,
        customer_country,
        net_amount,
        vat_rate,
        vat_amount,
        gross_amount,

        -- Q2b: differences up to 2 cents / 1.56 Ft are VAT rounding, not errors
        round(net_amount * vat_rate / 100 - vat_amount, 2)                          as vat_rounding_difference,

        nullif(concat_ws(', ',
            case when abs(net_amount + vat_amount - gross_amount)
                      > case when currency = 'HUF' then 2 else 0.05 end
                 then 'gross_not_net_plus_vat' end,
            case when abs(net_amount * vat_rate / 100 - vat_amount)
                      > case when currency = 'HUF' then 2 else 0.05 end
                 then 'vat_calculation_error' end,
            case when (document_type = 'SZAMLA' and gross_amount < 0)
                   or (document_type = 'JOVAIRAS' and gross_amount > 0)
                 then 'wrong_sign' end
        ), '')                                                                      as dq_issue
    from parsed
)

select * from final