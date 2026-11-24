-- Exploration: stg_erp__invoices
-- Q1: Formats of every text column (digits -> 9)
select 'document_type' as column_name, document_type as shape, count(*) as row_count, min(document_type) as example
from staging.stg_erp__invoices group by 2
union all
select 'invoice_date_raw', regexp_replace(invoice_date_raw, '[0-9]', '9', 'g'), count(*), min(invoice_date_raw)
from staging.stg_erp__invoices group by 2
union all
select 'net_amount_raw', regexp_replace(net_amount_raw, '[0-9]', '9', 'g'), count(*), min(net_amount_raw)
from staging.stg_erp__invoices group by 2
union all
select 'vat_rate_raw', vat_rate_raw, count(*), min(vat_rate_raw)
from staging.stg_erp__invoices group by 2
union all
select 'currency', currency, count(*), min(currency)
from staging.stg_erp__invoices group by 2
union all
select 'order_reference', regexp_replace(order_reference, '[0-9]', '9', 'g'), count(*), min(order_reference)
from staging.stg_erp__invoices group by 2
order by column_name, row_count desc;


-- Finding: Hungarian number and date formats (DQ06, DQ08). 17,303 invoices and
--          994 credit notes = the live charges and refunds in the payment data.
-- Fix in intermediate: parse numbers (remove spaces, comma -> point), dates with
--          to_date('YYYY.MM.DD.'), VAT rate as a number.


-- Q2: Invoice arithmetic, signs and VAT rate per country
with parsed as (
    select
        *,
        to_date(invoice_date_raw, 'YYYY.MM.DD.')                                             as invoice_date,
        cast(replace(regexp_replace(net_amount_raw,   '[^0-9,-]', '', 'g'), ',', '.') as numeric) as net_amount,
        cast(replace(regexp_replace(vat_amount_raw,   '[^0-9,-]', '', 'g'), ',', '.') as numeric) as vat_amount,
        cast(replace(regexp_replace(gross_amount_raw, '[^0-9,-]', '', 'g'), ',', '.') as numeric) as gross_amount,
        cast(replace(regexp_replace(vat_rate_raw,     '[^0-9,]',  '', 'g'), ',', '.') as numeric) as vat_rate,
        case when currency = 'HUF' then 1 else 0.01 end                                      as tolerance
    from staging.stg_erp__invoices
)

select
    document_type,
    count(*)                                                                    as documents,
    count(*) filter (where abs(net_amount + vat_amount - gross_amount) > tolerance)
                                                                                as gross_not_net_plus_vat,
    count(*) filter (where abs(net_amount * vat_rate / 100 - vat_amount) > tolerance)
                                                                                as vat_not_rate_x_net,
    count(*) filter (where (document_type = 'SZAMLA'   and gross_amount < 0)
                        or (document_type = 'JOVAIRAS' and gross_amount > 0))  as wrong_sign,
    min(invoice_date)                                                           as first_date,
    max(invoice_date)                                                           as last_date
from parsed
group by document_type;

-- Q3: VAT rate per customer country
with parsed as (
    select
        customer_country,
        cast(replace(regexp_replace(vat_rate_raw, '[^0-9,]', '', 'g'), ',', '.') as numeric) as vat_rate
    from staging.stg_erp__invoices
)
select customer_country, vat_rate, count(*) as documents
from parsed
group by 1, 2
order by 1, 2;


-- Q3b: Romania - does the VAT rate change on a date?
select
    cast(replace(regexp_replace(vat_rate_raw, '[^0-9,]', '', 'g'), ',', '.') as numeric) as vat_rate,
    min(to_date(invoice_date_raw, 'YYYY.MM.DD.'))   as first_invoice,
    max(to_date(invoice_date_raw, 'YYYY.MM.DD.'))   as last_invoice,
    count(*)                                        as documents
from staging.stg_erp__invoices
where customer_country = 'RO'
group by 1
order by 1;

-- Finding: One VAT rate per country, except Romania: 19 % until 2025-07-31 and 21 %
--          from 2025-08-01 - the real Romanian VAT increase of August 2025, not an
--          error. No overlap between the two periods.
-- Fix in intermediate: none; documented, and a test will check the rate by
--          country and date (step 8).


-- Q2b: Size of the VAT differences
with parsed as (
    select
        currency,
        cast(replace(regexp_replace(net_amount_raw, '[^0-9,-]', '', 'g'), ',', '.') as numeric) as net_amount,
        cast(replace(regexp_replace(vat_amount_raw, '[^0-9,-]', '', 'g'), ',', '.') as numeric) as vat_amount,
        cast(replace(regexp_replace(vat_rate_raw,   '[^0-9,]',  '', 'g'), ',', '.') as numeric) as vat_rate
    from staging.stg_erp__invoices
)

select
    currency,
    case
        when abs(net_amount * vat_rate / 100 - vat_amount) = 0     then '1 exact'
        when abs(net_amount * vat_rate / 100 - vat_amount) <= 0.01 then '2 rounding, max 1 cent'
        when abs(net_amount * vat_rate / 100 - vat_amount) <= 1    then '3 rounding, max 1 unit'
        else                                                            '4 real error'
    end                                                         as difference,
    count(*)                                                    as documents,
    round(max(abs(net_amount * vat_rate / 100 - vat_amount)), 2) as max_difference
from parsed
group by 1, 2
order by 1, 2;


-- Finding: No material VAT error. All differences are rounding (max 2 cents or
--          1.56 Ft), probably VAT rounded per line and then summed. The profiling
--          figure of 82 'gross is not net + VAT' came from comparing without a
--          rounding tolerance - corrected here.
-- Fix in intermediate: tolerance 0.05 EUR / 2 Ft; the difference is kept in
--          vat_rounding_difference. Cross-system checks (invoice vs payment vs
--          order) follow in the finance reconciliation.


