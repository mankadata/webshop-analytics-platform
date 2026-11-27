-- Mart (gold): product dimension, one row per product (latest version),
-- with the average purchase cost in EUR for margin calculations.

with products as (
    select * from {{ ref('int_shop__products_cleaned') }}
),

purchase_orders as (
    select * from {{ ref('int_erp__purchase_orders_cleaned') }}
),

purchase_lines as (
    select * from {{ ref('stg_erp__purchase_order_lines') }}
),

fx_rates as (
    select * from {{ ref('int_ecb__fx_rates_daily') }}
),

stock_movements as (
    select * from {{ ref('int_erp__stock_movements_cleaned') }}
),

-- weighted average purchase cost per product, converted with the order-day rate
purchase_cost as (
    select
        upper(trim(purchase_lines.sku_raw))                         as sku,
        sum(purchase_lines.quantity)                                as purchased_units,
        sum(purchase_lines.quantity
            * cast(replace(regexp_replace(purchase_lines.unit_cost_raw, '[^0-9,-]', '', 'g'), ',', '.') as numeric)
            / fx_rates.units_per_eur)                               as purchase_value_eur
    from purchase_lines
    join purchase_orders
        on purchase_orders.po_number = purchase_lines.po_number
    join fx_rates
        on  fx_rates.currency  = purchase_lines.currency
        and fx_rates.rate_date = purchase_orders.order_date
    group by 1
),

-- fallback for products never bought on a purchase order (sold from the opening
-- stock): the unit cost the ERP recorded on stock movements
movement_cost as (
    select
        product_id,
        sum(abs(stock_change) * unit_cost_eur) / nullif(sum(abs(stock_change)), 0)
                                                                    as avg_unit_cost_eur
    from stock_movements
    where unit_cost_eur is not null
    group by 1
)

select
    products.product_id,
    products.sku,
    products.product_name,
    products.category_code,
    products.category_name,
    products.brand,
    products.supplier_code,
    products.warehouse_code,
    products.list_price_eur,
    round(coalesce(purchase_cost.purchase_value_eur / nullif(purchase_cost.purchased_units, 0),
                   movement_cost.avg_unit_cost_eur), 2)             as avg_unit_cost_eur,
    case
        when purchase_cost.purchased_units > 0     then 'purchase_orders'
        when movement_cost.avg_unit_cost_eur is not null then 'stock_movements'
    end                                                             as  cost_source,
    round(1 - coalesce(purchase_cost.purchase_value_eur / nullif(purchase_cost.purchased_units, 0),
                       movement_cost.avg_unit_cost_eur)
              / nullif(products.list_price_eur, 0), 4)              as list_margin_pct,
    products.weight_g,
    products.is_active,
    products.first_seen_at,
    products.version_count                                          as price_changes
from products
left join purchase_cost
    on purchase_cost.sku = products.sku
left join movement_cost
    on movement_cost.product_id = products.product_id