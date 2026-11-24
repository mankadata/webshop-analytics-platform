-- Exploration: stg_shop__order_items
-- Goal: find duplicates, impossible values and orphans before writing
--       int_shop__order_items_cleaned.

-- Overview - grain and duplicates
select
    count(*)                                        as row_count,
    count(distinct order_item_id)                   as distinct_item_ids,
    count(*) - count(distinct order_item_id)        as duplicate_rows,
    count(distinct order_id)                        as orders_with_items,
    round(count(*)::numeric / count(distinct order_id), 2)
                                                    as items_per_order
from staging.stg_shop__order_items;

-- Finding: One row = one order line (product in an order). 159 rows repeat an
--          order_item_id (DQ02). Every order has at least one line (17,741 orders,
--          same as int_shop__orders_cleaned); 1.71 lines per order on average.
-- Fix in intermediate: are the duplicates exact copies

-- Duplicates - exact copies or different values?
select
    copies,
    different_values,
    different_batches,
    count(*)                        as item_count,
    min(order_item_id)              as example_order_item_id
from (
    select
        order_item_id,
        count(*)                                                as copies,
        count(distinct (order_id, product_id, quantity,
                        unit_price_local, discount_pct))        as different_values,
        count(distinct _batch_id)                               as different_batches
    from staging.stg_shop__order_items
    group by order_item_id
    having count(*) > 1
) as dups
group by 1, 2, 3
order by item_count desc;

-- Finding: 159 order lines appear exactly twice. Every pair is an exact copy from
--          the same daily file - the export wrote the line twice (DQ02).
-- Fix in intermediate: keep one row per order_item_id. No information is lost.


-- Impossible values in quantity, price and discount
select
    case
        when quantity is null or unit_price_local is null      then '1 missing value'
        when quantity <= 0                                      then '2 quantity zero or negative'
        when discount_pct < 0 or discount_pct > 100             then '3 discount outside 0-100 %'
        when unit_price_local <= 0                              then '4 price zero or negative'
        else                                                         '5 plausible'
    end                         as value_check,
    count(*)                    as row_count,
    min(quantity)               as min_quantity,
    max(quantity)               as max_quantity,
    min(discount_pct)           as min_discount,
    max(discount_pct)           as max_discount,
    min(order_item_id)          as example_order_item_id
from staging.stg_shop__order_items
group by 1
order by 1;
-- Finding: Normal lines have quantity 1-5 and discount 0-20 %. 40 lines have
--          quantity 0 or -1, and 18 lines have exactly 120 % discount (a typo for
--          12 or 20?) (DQ09). No missing values, no zero prices.
-- Fix in intermediate: not repaired - guessing is not possible. The line is kept
--          with is_valid = false and dq_issue 'invalid_quantity' / 'invalid_discount',
--          excluded from revenue in marts and listed in the quarantine view (step 8).


-- Q4: order lines whose product or order does not exist
select
    count(*)                                                    as row_count,
    count(*) filter (where p.product_id is null)                as unknown_product,
    count(*) filter (where o.order_id is null)                  as unknown_order,
    min(i.product_id) filter (where p.product_id is null)       as example_unknown_product_id
from staging.stg_shop__order_items as i
left join (select distinct product_id from staging.stg_shop__products) as p
    on i.product_id = p.product_id
left join (select distinct order_id from staging.stg_shop__orders) as o
    on i.order_id = o.order_id;
-- Finding: 35 order lines point to a product that does not exist in the product
--          table (ids like 990019) - orphan records (DQ10). Every line belongs to
--          an existing order.
-- Fix in intermediate: flag with dq_issue 'unknown_product', is_valid = false.

