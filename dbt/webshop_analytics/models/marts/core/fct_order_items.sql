-- Mart (gold): order line fact, one row per order line.
-- Revenue is the ERP order revenue allocated to the valid lines by their share of
-- the order value, so the lines always add up to the invoiced order (conformed
-- with fct_orders). Invalid lines are kept, flagged and carry no revenue.

with items as (
    select * from {{ ref('int_shop__order_items_cleaned') }}
),

orders as (
    select order_id, order_date, customer_key, marketing_channel, shipping_country,
           invoiced_net_eur
    from {{ ref('fct_orders') }}
),

products as (
    select product_id, category_code, avg_unit_cost_eur from {{ ref('dim_products') }}
),

returns as (
    select order_item_id, sum(returned_quantity) as returned_quantity
    from {{ ref('int_shop__returns_cleaned') }}
    where is_valid
    group by 1
),

valid_line_share as (
    select
        order_item_id,
        net_amount_local / nullif(sum(net_amount_local) over (partition by order_id), 0)
                                                                    as share_of_order
    from items
    where is_valid
)

select
    items.order_item_id,
    items.order_id,
    orders.order_date,
    orders.customer_key,
    orders.marketing_channel,
    orders.shipping_country,
    items.product_id,
    products.category_code,
    items.is_valid,
    items.dq_issue,

    items.quantity,
    coalesce(returns.returned_quantity, 0)                          as returned_quantity,

    -- invoiced sales of the line (EUR, without VAT) and the returned part of it
    round(orders.invoiced_net_eur * valid_line_share.share_of_order, 2)
                                                                    as sales_eur,
    round(orders.invoiced_net_eur * valid_line_share.share_of_order
          * coalesce(returns.returned_quantity, 0) / nullif(items.quantity, 0), 2)
                                                                    as returns_eur,
    -- cost of the goods that stayed with the customer (valid, invoiced lines only)
    case when items.is_valid and orders.invoiced_net_eur is not null then
        round(products.avg_unit_cost_eur
              * (items.quantity - coalesce(returns.returned_quantity, 0)), 2)
    end                                                             as cost_of_goods_eur
from items
join orders
    on orders.order_id = items.order_id
left join valid_line_share
    on valid_line_share.order_item_id = items.order_item_id
left join products
    on products.product_id = items.product_id
left join returns
    on returns.order_item_id = items.order_item_id