-- Check 1: flags (expected: 1704 clean + 4 flagged = 1708)
select coalesce(dq_issue, '(clean)') as dq_issue, count(*) as returns
from intermediate.int_shop__returns_cleaned
group by 1
order by returns desc;

-- Check 2: the 2 orders with returns but without 'returned' status
select o.order_id, o.order_status, o.dq_issue, count(*) as returns
from intermediate.int_shop__returns_cleaned as r
join intermediate.int_shop__orders_cleaned as o
    on r.order_id = o.order_id
where o.order_status <> 'returned'
group by 1, 2, 3;

-- Finding: The 2 orders (105709, 115566) end with 'delivered > (null)' in the order
--          event log, and both have a return. The lost status was 'returned': the
--          returns table repairs the order status. In marts, has_return comes from
--          int_shop__returns_cleaned, not from order_status alone.