-- Singular test: an order cannot be shipped before it was placed, and cannot be
-- delivered before it was shipped (the course tip, applied to our order life cycle).
-- Returned-before-delivered events are a known source issue (35 orders, flagged as
-- 'status_out_of_order' in intermediate) and are not checked here.

select
    order_id,
    ordered_at,
    shipped_at,
    delivered_at
from {{ ref('int_shop__orders_cleaned') }}
where shipped_at   < ordered_at
   or delivered_at < shipped_at