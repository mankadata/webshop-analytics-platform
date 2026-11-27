-- Exploration: stg_erp__stock_movements
-- Q1: Movement types - counts, signs and duplicates
select
    movement_code,
    count(*)                                            as row_count,
    count(distinct movement_id)                         as distinct_ids,
    count(*) filter (where quantity > 0)                as positive,
    count(*) filter (where quantity < 0)                as negative,
    count(*) filter (where quantity = 0 or quantity is null) as zero_or_missing,
    min(reference)                                      as example_reference,
    min(note)                                           as example_note
from staging.stg_erp__stock_movements
group by movement_code
order by row_count desc;

-- Q2: Formats - date, unit cost, SKU, and does the SKU match a product?
select
    regexp_replace(movement_date_raw, '[0-9]', '9', 'g')    as date_shape,
    regexp_replace(unit_cost_eur_raw, '[0-9]', '9', 'g')    as cost_shape,
    case
        when sku_raw = upper(trim(sku_raw))              then '1 clean'
        when upper(trim(sku_raw)) in (select sku from intermediate.int_shop__products_cleaned)
                                                         then '2 messy, but matches a product'
        else                                                  '3 no matching product'
    end                                                     as sku_check,
    count(*)                                                as row_count,
    min(sku_raw)                                            as example_sku,
    min(unit_cost_eur_raw)                                  as example_cost
from staging.stg_erp__stock_movements
group by 1, 2, 3
order by row_count desc;

-- Finding: Quantities are stored as positive numbers and the movement code gives the
--          direction. 66 sales carry a minus sign (DQ09). Stock count adjustments are
--          signed on purpose (surplus or shrinkage). 321 SKUs need reformatting (DQ04).
-- Fix in intermediate: stock_change = -abs(quantity) for sales, +abs for receipts and
--          returns, own sign for stock counts; the 66 sales are flagged 'sign_corrected'.
--          SKU = upper(trim()), then matched to the product.

