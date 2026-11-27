-- Mart (gold): monthly net revenue by country and marketing channel.
-- Grain: one row per month x shipping country x marketing channel.
-- Revenue = ERP net amount (without VAT) minus credit notes, in EUR.

with orders as (
    select * from {{ ref('int_shop__orders_enriched') }}
    where invoiced_net_eur is not null          -- invoiced = paid orders only
)

select
    cast(date_trunc('month', order_date) as date)                   as month,
    shipping_country,
    marketing_channel,
    count(distinct order_id)                                        as order_count,
    count(distinct master_customer_id)                              as unique_customers,
    count(distinct order_id) filter (where customer_order_number = 1)
                                                                    as new_customer_orders,
    sum(invoiced_net_eur)                                           as gross_sales_eur,
    sum(credited_net_eur)                                           as returns_eur,
    sum(net_revenue_eur)                                            as net_revenue_eur,
    round(sum(net_revenue_eur) / count(distinct order_id), 2)       as avg_order_value_eur
from orders
group by 1, 2, 3
order by 1, 2, 3