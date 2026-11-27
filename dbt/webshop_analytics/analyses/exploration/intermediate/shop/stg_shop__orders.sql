-- Exploration: stg_shop__orders
-- Goal: understand the grain and the dirty columns before writing int_shop__orders_latest.


select * from staging.stg_shop__orders;


-- What is one row? Events per order
select
    events,
    count(*)                as order_count,
    min(order_id)           as example_order_id
from (
    select order_id, count(*) as events
    from staging.stg_shop__orders
    group by order_id
) as per_order
group by events
order by events;

-- Columns: events = rows (status changes) per order, order_count = orders with that many rows.
-- Finding: One row = one status change of an order (event log). Most orders have
-- 4 events (the normal life cycle). Orders with 1 event are the newest ones, still in progress.
-- Fix in intermediate: int_shop__orders_latest keeps one row per order with the latest status; the first event gives the order date.

-- Status values
select
    coalesce(status, '(null)')      as status,
    count(*)                        as row_count,
    count(distinct order_id)        as order_count
from staging.stg_shop__orders
group by 1
order by row_count desc;

-- Finding: No status repeats within an order. More orders were shipped than paid,
--          probably cash on delivery (paid to the courier, no 'paid' event).
--          259 events have no status (DQ01); 64 orders have no 'pending' event.
-- Fix in intermediate: see Q3 (status sequences) before deciding.

--Check
---Status paths - the order of events per order
select
    status_path,
    count(*)                    as order_count,
    min(order_id)               as example_order_id
from (
    select
        order_id,
        string_agg(coalesce(status, '(null)'), ' > ' order by updated_at_local, _loaded_at)
                                as status_path
    from staging.stg_shop__orders
    group by order_id
) as paths
group by status_path
order by order_count desc;


--Is the missing 'paid' event explained by the payment method?
select
    payment_method,
    count(distinct order_id)                                            as orders,
    count(distinct order_id) filter (where status = 'paid')             as orders_with_paid_event
from staging.stg_shop__orders
group by 1
order by orders desc;

-- Columns: orders = all orders with that payment method,
--          orders_with_paid_event = orders that have a 'paid' status event.
-- Finding: Cash on delivery never has a 'paid' event - the customer pays the
--          courier. This is a business rule, not a data error. Card and PayPal miss
--          the event only for a few orders (null status or still in progress).
--          Bank transfer: 425 orders without payment - probably never paid and
--          cancelled (checked in Q5).
-- Fix in intermediate: no 'paid' event for cash on delivery is not flagged.
--          is_paid = paid event exists, or cash on delivery and delivered.

-- Q5: Bank transfer orders without a 'paid' event - what happened to them?
select
    status_path,
    count(*)                    as order_count,
    min(order_id)               as example_order_id
from (
    select
        order_id,
        string_agg(coalesce(status, '(null)'), ' > ' order by updated_at_local, _loaded_at)
                                as status_path,
        bool_or(status = 'paid') as has_paid
    from staging.stg_shop__orders
    where payment_method = 'bank_transfer'
    group by order_id
) as paths
where not coalesce(has_paid, false)
group by status_path
order by order_count desc;

-- Finding: Unpaid bank transfers are cancelled: 394 of the 399 cancelled orders are
--          bank transfers. 19 are new orders still waiting for the transfer. In 9
--          orders the lost (null) status was the payment, because they were shipped.
-- Fix in intermediate: is_paid = a 'paid' event exists, OR a prepaid order reached
--          'shipped' (it would not ship unpaid), OR a cash-on-delivery order was
--          delivered (paid to the courier).

-- Q6: Are order attributes the same in every event of an order?
select
    count(*)                                                    as orders,
    count(*) filter (where customers > 1)                       as customer_changes,
    count(*) filter (where order_dates > 1)                     as order_date_changes,
    count(*) filter (where currencies > 1)                      as currency_changes,
    count(*) filter (where payment_methods > 1)                 as payment_method_changes,
    count(*) filter (where countries > 1)                       as country_changes,
    count(*) filter (where fees > 1)                            as shipping_fee_changes
from (
    select
        order_id,
        count(distinct customer_id)         as customers,
        count(distinct ordered_at_local)    as order_dates,
        count(distinct currency)            as currencies,
        count(distinct payment_method)      as payment_methods,
        count(distinct shipping_country)    as countries,
        count(distinct shipping_fee_local)  as fees
    from staging.stg_shop__orders
    group by order_id
) as per_order;


-- Finding: Order attributes (customer, order date, currency, payment method,
--          shipping country, shipping fee) are identical in every event of an order.
--          Only status and updated_at change.
-- Fix in intermediate: take the attributes from the first event of the order.


-- Q7: Values of the code columns
select 'shipping_country' as column_name, shipping_country as value, count(distinct order_id) as orders
from staging.stg_shop__orders group by 2
union all
select 'sales_channel', sales_channel, count(distinct order_id)
from staging.stg_shop__orders group by 2
union all
select 'currency', currency, count(distinct order_id)
from staging.stg_shop__orders group by 2
order by column_name, orders desc;

-- Finding: All code columns are clean: shipping_country already uses ISO codes
--          (unlike the customer country), no casing or spelling variants.
-- Fix in intermediate: none needed.