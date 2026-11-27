-- Singular test: every invoice carries the VAT rate of its country on its date.
-- Romania raised its rate from 19 % to 21 % on 2025-08-01 (a real change, found in
-- exploration); any other rate is an error. Returns the rows that break the rule.

with expected as (
    select
        invoice_number,
        customer_country,
        invoice_date,
        vat_rate,
        case customer_country
            when 'HU' then 27
            when 'AT' then 20
            when 'CZ' then 21
            when 'DE' then 19
            when 'PL' then 23
            when 'SK' then 23
            when 'RO' then case when invoice_date < date '2025-08-01' then 19 else 21 end
        end                                                         as expected_vat_rate
    from {{ ref('int_erp__invoices_cleaned') }}
)

select *
from expected
where expected_vat_rate is null
   or vat_rate <> expected_vat_rate
