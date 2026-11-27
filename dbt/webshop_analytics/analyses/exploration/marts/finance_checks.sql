-- Check 1: enriched orders - one row per order, every invoiced order has revenue
select
    count(*)                                            as orders,
    count(distinct order_id)                            as distinct_orders,
    count(*) filter (where invoiced_net_eur is not null) as invoiced_orders,
    count(distinct master_customer_id)                  as people,
    count(*) filter (where customer_order_number = 1)   as first_orders
from intermediate.int_shop__orders_enriched;

-- Check 2: yearly totals from the mart
select
    extract(year from month)                            as year,
    sum(order_count)                                    as orders,
    round(sum(gross_sales_eur), 2)                      as gross_sales_eur,
    round(sum(returns_eur), 2)                          as returns_eur,
    round(sum(net_revenue_eur), 2)                      as net_revenue_eur
from marts.fct_monthly_revenue
group by 1
order by 1;

