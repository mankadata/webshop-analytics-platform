-- Check 1: one row per product, every category recognised? (expected: 235, 235, 0)
select
    count(*)                                        as row_count,
    count(distinct product_id)                      as product_count,
    count(*) filter (where category_name is null)   as unknown_category
from intermediate.int_shop__products_cleaned;

-- Check 2: products per category and weight range
select
    category_code,
    category_name,
    count(*)                                        as products,
    count(*) filter (where weight_g is null)        as missing_weight,
    min(weight_g)                                   as min_weight_g,
    max(weight_g)                                   as max_weight_g
from intermediate.int_shop__products_cleaned
group by 1, 2
order by 1;