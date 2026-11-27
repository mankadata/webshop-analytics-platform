-- Check 1: one row per order? (both should be 17741)
select count(*) as row_count, count(distinct order_id) as order_count
from intermediate.int_shop__orders_cleaned;

-- Check 2: current status vs paid flag
select order_status, is_paid, count(*) as orders
from intermediate.int_shop__orders_cleaned
group by 1, 2
order by 1, 2;

-- Check 3: data-quality flags (expected: 259 missing_status_event, 35 status_out_of_order)
select coalesce(dq_issue, '(clean)') as dq_issue, count(*) as orders
from intermediate.int_shop__orders_cleaned
group by 1
order by orders desc;