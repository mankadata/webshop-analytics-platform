-- Mart (gold): stock on hand per product and day.
-- Grain: one row per product x calendar day (from the product's first movement to today).
-- A stockout is a day that ends with no stock; negative stock is flagged, not hidden.

with movements as (
    select
        product_id,
        movement_date,
        sum(stock_change)                                           as stock_change,
        sum(-stock_change) filter (where movement_type = 'sale')    as units_sold,
        sum(stock_change)  filter (where movement_type = 'goods_receipt')
                                                                    as units_received
    from {{ ref('int_erp__stock_movements_cleaned') }}
    where product_id is not null
    group by 1, 2
),

days as (
    select date_day
    from {{ ref('dim_date') }}
    where date_day between (select min(movement_date) from movements) and current_date
),

-- a product's history starts with its first stock movement
products as (
    select dim_products.product_id, min(movements.movement_date) as first_movement_date
    from {{ ref('dim_products') }} as dim_products
    join movements on movements.product_id = dim_products.product_id
    group by 1
),

product_days as (
    select
        products.product_id,
        days.date_day,
        coalesce(movements.stock_change, 0)                         as stock_change,
        coalesce(movements.units_sold, 0)                           as units_sold,
        coalesce(movements.units_received, 0)                       as units_received
    from products
    join days
        on days.date_day >= products.first_movement_date
    left join movements
        on  movements.product_id    = products.product_id
        and movements.movement_date = days.date_day
)

select
    product_id,
    date_day,
    stock_change,
    units_sold,
    units_received,
    sum(stock_change) over (
        partition by product_id
        order by date_day
        rows between unbounded preceding and current row
    )                                                               as stock_on_hand,
    sum(stock_change) over (
        partition by product_id
        order by date_day
        rows between unbounded preceding and current row
    ) <= 0                                                          as is_stockout,
    sum(stock_change) over (
        partition by product_id
        order by date_day
        rows between unbounded preceding and current row
    ) < 0                                                           as is_negative_stock
from product_days