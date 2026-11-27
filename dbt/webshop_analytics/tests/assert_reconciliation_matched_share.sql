-- Singular test: at least 95 % of the paid orders reconcile across shop, payments
-- and ERP. A drop below that means a source changed or a load went wrong.

select
    count(*)                                                        as paid_orders,
    count(*) filter (where reconciliation_status = 'matched')       as matched_orders
from {{ ref('int_finance__order_reconciliation') }}
where reconciliation_status <> 'not_paid'
having count(*) filter (where reconciliation_status = 'matched') < 0.95 * count(*)
