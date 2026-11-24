-- Check: one row per document, every order linked, no flagged document expected
select
    i.document_type,
    count(*)                                        as documents,
    count(distinct i.invoice_number)                as distinct_numbers,
    count(*) filter (where o.order_id is null)      as unknown_order,
    count(*) filter (where i.dq_issue is not null)  as flagged,
    max(abs(i.vat_rounding_difference))             as max_rounding_difference
from intermediate.int_erp__invoices_cleaned as i
left join intermediate.int_shop__orders_cleaned as o
    on i.order_id = o.order_id
group by 1
order by 1;