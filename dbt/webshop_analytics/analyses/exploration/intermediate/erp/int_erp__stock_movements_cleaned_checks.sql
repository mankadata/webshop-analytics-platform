-- Check 1: movement types, signs and flags
select
    movement_type,
    count(*)                                        as movements,
    sum(stock_change)                               as total_stock_change,
    count(*) filter (where stock_change < 0)        as outgoing,
    count(*) filter (where dq_issue is not null)    as flagged,
    count(*) filter (where was_sku_reformatted)     as sku_reformatted
from intermediate.int_erp__stock_movements_cleaned
group by 1
order by movements desc;

-- Check 2: is any product's stock negative today?
select
    count(*)                                        as products,
    count(*) filter (where stock_on_hand < 0)       as negative_stock,
    min(stock_on_hand)                              as min_stock,
    max(stock_on_hand)                              as max_stock
from (
    select product_id, sum(stock_change) as stock_on_hand
    from intermediate.int_erp__stock_movements_cleaned
    group by product_id
) as stock;

-- Q3: The products with negative stock - is it the sign correction?
with stock as (
    select
        product_id,
        sku,
        sum(stock_change)                                               as stock_now,
        -- the 66 corrected sales: what if they were inflows instead?
        sum(abs(quantity_raw)) filter (where dq_issue = 'sign_corrected') as corrected_units,
        count(*) filter (where dq_issue = 'sign_corrected')             as corrected_movements,
        min(movement_date) filter (where movement_type = 'goods_receipt') as first_receipt
    from intermediate.int_erp__stock_movements_cleaned
    group by product_id, sku
)

select
    product_id,
    sku,
    stock_now,
    corrected_movements,
    corrected_units,
    stock_now + 2 * coalesce(corrected_units, 0)    as stock_if_inflows,
    first_receipt
from stock
where stock_now < 0
order by stock_now;

-- Finding: The sign correction is right. The negative stock is a real cross-system
--          issue (DQ14): products were sold before - or without - a recorded goods
--          receipt. Kept as it is in intermediate; flagged in the marts stock model
--          and covered by a test in step 8.

