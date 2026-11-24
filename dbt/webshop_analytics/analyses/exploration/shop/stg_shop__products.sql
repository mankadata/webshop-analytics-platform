-- Exploration: stg_shop__products
-- Goal: understand the grain, categories and weights before writing
--       int_shop__products_cleaned.

-- Q1: What is one row? Versions per product
select
    versions,
    count(*)                    as product_count,
    min(product_id)             as example_product_id
from (
    select product_id, count(*) as versions
    from staging.stg_shop__products
    group by product_id
) as per_product
group by versions
order by versions;
-- Finding: One row = one version of a product; most products changed 1-5 times.

-- All versions of product 137 - what changes?
select
    _batch_id,
    updated_at_local,
    sku,
    product_name,
    category_raw,
    list_price_eur,
    weight_raw,
    is_active
from staging.stg_shop__products
where product_id = 137
order by updated_at_local;
-- Q1b Finding: For product 137 only the price changes between versions
--          (677.76 -> 745.54 -> ... -> 441.46 -> 485.61): every version is a price
--          change. Name, SKU, category and status stay the same. The weight changes
--          only in format: '1,45 kg' until July 2025, then '1451 g' / '1451g'. The kg
--          value is rounded to two decimals (1,45 kg = 1450 g vs 1451 g).
--          Versions are dated to the day (time is always 00:00).
-- Fix in intermediate: int_shop__products_cleaned keeps the latest version per
--          product; the price history is kept for marts (price valid on the order date).
--          Weight in grams; a gram value is preferred over a rounded kg value.


-- All versions of product 137 - what changes?
select
    updated_at_local::date      as changed_on,
    category_raw,
    list_price_eur,
    weight_raw,
    is_active
from staging.stg_shop__products
where product_id = 137
order by updated_at_local;


--  Category spellings
select
    category_raw,
    count(distinct product_id)      as product_count,
    count(*)                        as row_count
from staging.stg_shop__products
group by category_raw
order by lower(trim(category_raw)), row_count desc;

-- Finding: 6 categories in 21 spellings: casing, different English names and
--          Hungarian names (DQ11). Product counts add up to 235, so every product
--          keeps the same spelling in all its versions.

--  Does the SKU prefix match the category?
select
    split_part(upper(trim(sku)), '-', 2)    as sku_category,
    category_raw,
    count(distinct product_id)              as product_count
from staging.stg_shop__products
group by 1, 2
order by 1, 2;

-- Finding: The SKU prefix is a second, reliable source for the category.
-- Fix in intermediate: category_code = SKU prefix; category_name from a 6-row seed
--          product_categories.csv. More robust than mapping 21 spellings: a new
--          spelling tomorrow still works. category_raw is kept only for a test.

-- Q3: Weight formats (digits -> 9)
select
    regexp_replace(weight_raw, '[0-9]', '9', 'g')   as weight_shape,
    count(*)                                        as row_count,
    count(distinct product_id)                      as product_count,
    min(weight_raw)                                 as example
from staging.stg_shop__products
group by 1
order by row_count desc;

-- Finding: Weights mix two units (DQ07) and use a Hungarian decimal comma (DQ08):
--          '0,06 kg', '1025 g', '1025g'. 23 rows have no weight (DQ01). kg values
--          are rounded to 10 g, gram values are exact.
-- Fix in intermediate: weight_g = grams as they are, kg x 1000 (comma -> point),
--          placeholders -> null. Prefer the product's latest gram value from any
--          version; fall back to kg only when no gram value exists.

-- Remaining columns - completeness and ranges (latest version per product)
with latest as (
    select distinct on (product_id) *
    from staging.stg_shop__products
    order by product_id, updated_at_local desc, _loaded_at desc
)

select
    count(*)                                            as products,
    count(*) filter (where brand is null)               as missing_brand,
    count(*) filter (where supplier_code is null)       as missing_supplier,
    count(*) filter (where warehouse_code is null)      as missing_warehouse,
    count(*) filter (where list_price_eur is null
                        or list_price_eur <= 0)         as invalid_price,
    min(list_price_eur)                                 as min_price,
    max(list_price_eur)                                 as max_price,
    count(*) filter (where is_active)                   as active_products,
    count(distinct sku)                                 as distinct_skus
from latest;

-- Finding: The remaining columns are complete and plausible; one SKU per product.
-- Fix in intermediate: none needed.

