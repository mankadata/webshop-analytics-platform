-- Check 1: one row per customer?
select count(*) as row_count, count(distinct customer_id) as customer_count
from intermediate.int_shop__customers_cleaned;

-- Check 2: which rules failed and how often?
select coalesce(dq_issue, '(clean)') as dq_issue, count(*) as row_count
from intermediate.int_shop__customers_cleaned
group by 1
order by row_count desc;