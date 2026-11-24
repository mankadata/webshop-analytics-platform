-- Exploration: finance reconciliation - shop vs payments vs ERP
-- Q1: Do the three systems agree per order?
with order_totals as (
    select
        o.order_id,
        o.currency,
        o.order_status,
        sum(i.net_amount_local) + o.shipping_fee_local          as order_total,
        bool_or(not i.is_valid)                                 as has_invalid_line
    from intermediate.int_shop__orders_cleaned as o
    join intermediate.int_shop__order_items_cleaned as i
        on i.order_id = o.order_id
    group by o.order_id, o.currency, o.order_status, o.shipping_fee_local
),

payments as (
    select
        order_id,
        sum(amount_local) filter (where event_type = 'charge.succeeded')    as paid,
        sum(amount_local) filter (where event_type = 'refund.succeeded')    as refunded
    from intermediate.int_payments__events_cleaned
    where is_valid
    group by order_id
),

documents as (
    select
        order_id,
        sum(gross_amount) filter (where not is_credit_note)     as invoiced,
        sum(gross_amount) filter (where is_credit_note)         as credited
    from intermediate.int_erp__invoices_cleaned
    group by order_id
)

select
    t.has_invalid_line,
    count(*)                                                            as orders,
    count(*) filter (where p.paid is null)                              as not_paid,
    count(*) filter (where d.invoiced is null)                          as not_invoiced,
    count(*) filter (where abs(p.paid - t.order_total) > 0.01)          as paid_differs_from_order,
    count(*) filter (where abs(d.invoiced - p.paid) > 0.01)             as invoice_differs_from_paid,
    count(*) filter (where abs(coalesce(p.refunded, 0) + coalesce(d.credited, 0)) > 0.01)
                                                                        as refund_differs_from_credit
from order_totals as t
left join payments  as p on p.order_id = t.order_id
left join documents as d on d.order_id = t.order_id
group by t.has_invalid_line
order by t.has_invalid_line;

-- Q2: Size of the differences per check and currency
with order_totals as (
    select
        o.order_id,
        o.currency,
        sum(i.net_amount_local) + o.shipping_fee_local          as order_total
    from intermediate.int_shop__orders_cleaned as o
    join intermediate.int_shop__order_items_cleaned as i
        on i.order_id = o.order_id
    group by o.order_id, o.currency, o.shipping_fee_local
),

payments as (
    select
        order_id,
        sum(amount_local) filter (where event_type = 'charge.succeeded')    as paid,
        sum(amount_local) filter (where event_type = 'refund.succeeded')    as refunded
    from intermediate.int_payments__events_cleaned
    where is_valid
    group by order_id
),

documents as (
    select
        order_id,
        sum(gross_amount) filter (where not is_credit_note)     as invoiced,
        sum(gross_amount) filter (where is_credit_note)         as credited
    from intermediate.int_erp__invoices_cleaned
    group by order_id
),

differences as (
    select t.currency, 'paid vs order'      as check_name, p.paid - t.order_total              as difference
    from order_totals as t join payments as p on p.order_id = t.order_id
    union all
    select t.currency, 'invoice vs paid',                  d.invoiced - p.paid
    from order_totals as t join payments as p on p.order_id = t.order_id
                           join documents as d on d.order_id = t.order_id
    union all
    select t.currency, 'refund vs credit',                 coalesce(p.refunded, 0) + coalesce(d.credited, 0)
    from order_totals as t join payments as p on p.order_id = t.order_id
                           join documents as d on d.order_id = t.order_id
)

select
    check_name,
    currency,
    case
        when abs(difference) <= 0.01 then '1 equal'
        when abs(difference) <= 1    then '2 rounding, max 1 unit'
        else                              '3 real difference'
    end                                 as size,
    count(*)                            as orders,
    round(min(difference), 2)           as min_difference,
    round(max(difference), 2)           as max_difference
from differences
where difference is not null
group by 1, 2, 3
order by 1, 2, 3;


-- Q3: The real differences (> 1 unit) - values and order context
with order_totals as (
    select
        o.order_id,
        o.currency,
        o.payment_method,
        o.order_status,
        sum(i.net_amount_local) + o.shipping_fee_local          as order_total,
        bool_or(not i.is_valid)                                 as has_invalid_line
    from intermediate.int_shop__orders_cleaned as o
    join intermediate.int_shop__order_items_cleaned as i
        on i.order_id = o.order_id
    group by o.order_id, o.currency, o.payment_method, o.order_status, o.shipping_fee_local
),

payments as (
    select order_id, sum(amount_local) as paid
    from intermediate.int_payments__events_cleaned
    where is_valid and event_type = 'charge.succeeded'
    group by order_id
),

documents as (
    select order_id, sum(gross_amount) as invoiced
    from intermediate.int_erp__invoices_cleaned
    where not is_credit_note
    group by order_id
)

select
    case
        when abs(p.paid - t.order_total) > 1 then 'paid vs order'
        else 'invoice vs paid'
    end                                                 as check_name,
    t.has_invalid_line,
    t.payment_method,
    round(case
        when abs(p.paid - t.order_total) > 1 then p.paid - t.order_total
        else d.invoiced - p.paid
    end, 2)                                             as difference,
    count(*)                                            as orders,
    min(t.order_id)                                     as example_order_id
from order_totals as t
join payments  as p on p.order_id = t.order_id
join documents as d on d.order_id = t.order_id
where abs(p.paid - t.order_total) > 1
   or abs(d.invoiced - p.paid) > 1
group by 1, 2, 3, 4
order by 1, 2, orders desc;

-- Finding: Three systems agree for ~99 % of the orders. Real cross-system
--          differences (DQ14): 19 underpaid orders (exactly 50 short) and the orders
--          whose shop total is distorted by invalid lines.
-- Fix in intermediate: int_finance__order_reconciliation - one row per order with
--          the three amounts, the differences, EUR values and a reconciliation_status.

