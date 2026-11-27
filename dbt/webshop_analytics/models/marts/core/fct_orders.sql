-- Mart (gold): order fact, one row per order.
-- Revenue from the ERP (net of VAT, minus credit notes), cost from the average
-- purchase price, so every order carries its own gross margin.

with orders as (
    select * from {{ ref('int_shop__orders_enriched') }}
),

order_items as (
    select * from {{ ref('int_shop__order_items_cleaned') }}
    where is_valid
),

returns as (
    select * from {{ ref('int_shop__returns_cleaned') }}
    where is_valid
),

products as (
    select product_id, avg_unit_cost_eur from {{ ref('dim_products') }}
),

sold as (
    select
        order_items.order_id,
        count(*)                                                    as line_count,
        sum(order_items.quantity)                                   as units_sold,
        sum(order_items.quantity * products.avg_unit_cost_eur)      as cost_of_goods_eur
    from order_items
    left join products on products.product_id = order_items.product_id
    group by 1
),

returned as (
    select
        returns.order_id,
        sum(returns.returned_quantity)                              as units_returned,
        sum(returns.returned_quantity * products.avg_unit_cost_eur) as returned_cost_eur
    from returns
    left join products on products.product_id = returns.product_id
    group by 1
)

select
    orders.order_id,
    orders.order_date,
    orders.ordered_at,
    orders.master_customer_id                                       as customer_key,
    orders.customer_id                                              as customer_account_id,
    orders.customer_order_number,
    orders.customer_order_number = 1                                as is_first_order,

    orders.order_status,
    orders.is_paid,
    orders.has_return,
    orders.payment_method,
    orders.sales_channel,
    orders.marketing_channel,
    orders.ad_platform,
    orders.shipping_country,
    orders.currency,
    orders.reconciliation_status,

    coalesce(sold.line_count, 0)                                    as line_count,
    coalesce(sold.units_sold, 0)                                    as units_sold,
    coalesce(returned.units_returned, 0)                            as units_returned,

    orders.invoiced_net_eur,
    orders.credited_net_eur,
    orders.net_revenue_eur,
    orders.paid_gross_eur,

    -- cost of the goods that stayed with the customer
    case when orders.invoiced_net_eur is not null then
        round(coalesce(sold.cost_of_goods_eur, 0) - coalesce(returned.returned_cost_eur, 0), 2)
    end                                                             as cost_of_goods_eur,
    case when orders.invoiced_net_eur is not null then
        round(orders.net_revenue_eur
              - (coalesce(sold.cost_of_goods_eur, 0) - coalesce(returned.returned_cost_eur, 0)), 2)
    end                                                             as gross_margin_eur
from orders
left join sold     on sold.order_id     = orders.order_id
left join returned on returned.order_id = orders.order_id
