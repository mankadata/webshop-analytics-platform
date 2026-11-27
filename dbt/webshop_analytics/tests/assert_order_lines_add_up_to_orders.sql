-- Singular test: the revenue allocated to the order lines adds up to the invoiced
-- order (conformed numbers between fct_order_items and fct_orders).
-- Orders without any valid line cannot be allocated and are left out.

with lines as (
    select order_id, sum(sales_eur) as lines_sales_eur
    from {{ ref('fct_order_items') }}
    where is_valid
    group by 1
)

select
    orders.order_id,
    orders.invoiced_net_eur,
    lines.lines_sales_eur
from {{ ref('fct_orders') }} as orders
join lines on lines.order_id = orders.order_id
where orders.invoiced_net_eur is not null
  and abs(orders.invoiced_net_eur - lines.lines_sales_eur) > 0.05
