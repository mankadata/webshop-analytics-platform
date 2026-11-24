-- Check 1: duplicates removed? (expected: 30144 rows, 30144 distinct ids)
select count(*) as row_count, count(distinct order_item_id) as item_count
from intermediate.int_shop__order_items_cleaned;

-- Check 2: data-quality flags (expected: 40 invalid_quantity, 18 invalid_discount,
--          35 unknown_product - a little less if some duplicates were also invalid)
select coalesce(dq_issue, '(clean)') as dq_issue, is_valid, count(*) as order_lines
from intermediate.int_shop__order_items_cleaned
group by 1, 2
order by order_lines desc;