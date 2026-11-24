-- Check 1: reconciliation status per order
select
    reconciliation_status,
    count(*)                                    as orders,
    round(sum(order_total_eur), 2)              as order_total_eur,
    round(sum(paid_eur), 2)                     as paid_eur,
    round(sum(paid_eur) - sum(order_total_eur), 2)  as difference_eur
from intermediate.int_finance__order_reconciliation
group by 1
order by orders desc;

-- Check 2: refunds vs credit notes, missing exchange rates
select
    count(*) filter (where not is_refund_matched)   as refund_mismatch,
    count(*) filter (where units_per_eur is null)   as missing_fx_rate
from intermediate.int_finance__order_reconciliation;

-- Finding: 97 % of the orders reconcile across shop, payments and ERP. 468 EUR is
--          missing on 36 underpaid orders. Orders with invalid lines must take their
--          revenue from the payment, not from the order lines.

