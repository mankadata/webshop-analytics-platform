-- Checks for the core marts (dim_date, dim_products, dim_suppliers, fct_orders, dim_customers)

-- Check 1: one row per key in every core mart
select 'dim_date' as model, count(*) as rows, count(distinct date_day) as keys from marts.dim_date
union all select 'dim_products',  count(*), count(distinct product_id)    from marts.dim_products
union all select 'dim_suppliers', count(*), count(distinct supplier_code) from marts.dim_suppliers
union all select 'fct_orders',    count(*), count(distinct order_id)      from marts.fct_orders
union all select 'dim_customers', count(*), count(distinct customer_key)  from marts.dim_customers;

-- Check 2: gross margin per year
select
    extract(year from order_date)                               as year,
    round(sum(net_revenue_eur), 0)                              as net_revenue_eur,
    round(sum(cost_of_goods_eur), 0)                            as cost_of_goods_eur,
    round(sum(gross_margin_eur), 0)                             as gross_margin_eur,
    round(100 * sum(gross_margin_eur) / sum(net_revenue_eur), 1) as gross_margin_pct,
    count(*) filter (where cost_of_goods_eur = 0
                       and net_revenue_eur > 0)                 as orders_without_cost
from marts.fct_orders
where invoiced_net_eur is not null
group by 1
order by 1;

-- Result after the cost fix:
--   2025  net revenue 2,096,153  cost 1,602,577  margin 493,577  23.5 %
--   2026  net revenue 2,172,441  cost 1,668,473  margin 503,968  23.2 %
-- Finding: before the fix the 2025 margin looked like 27.4 % and seemed to fall.
--          The cause was missing purchase costs (products sold from the opening
--          stock). After the fix the margin is a stable ~23 % in both years.

-- Check 3: customers by buyer type
select
    buyer_type,
    count(*)                                                    as customers,
    round(sum(lifetime_revenue_eur), 0)                         as revenue_eur
from marts.dim_customers
group by 1
order by 2 desc;

-- Check 4: products without a purchase cost
select
    count(*) filter (where avg_unit_cost_eur is null)   as products_without_cost,
    count(*)                                            as products
from marts.dim_products;
-- Result (before the fix): 23 of 235 products have no purchase cost - they were
--         sold from the opening stock and never bought on a purchase order.

-- Check 5: where does the product cost come from?
select cost_source, count(*) as products, round(avg(list_margin_pct) * 100, 1) as avg_list_margin_pct
from marts.dim_products
group by 1
order by 2 desc;

-- Check 6: the orders without cost - do they have any valid line?
select
    count(*)                                        as orders_without_cost,
    count(*) filter (where line_count = 0)          as no_valid_line
from marts.fct_orders
where invoiced_net_eur is not null
  and cost_of_goods_eur = 0
  and net_revenue_eur > 0;

  -- Result: 29 orders without cost - 26 have no valid line at all (only unknown
--         products or quantity 0 / -1), 3 were fully returned: the returned cost
--         cancels the cost of goods, while the shipping fee stays as revenue.
-- Finding: not a model error; covered by a warning test in step 8.


-- Check 8: order lines add up to the orders (conformed revenue)
select
    (select round(sum(invoiced_net_eur), 2) from marts.fct_orders)      as orders_sales_eur,
    (select round(sum(sales_eur), 2)        from marts.fct_order_items) as lines_sales_eur;

-- Check 9: gross margin by product category
select
    category_code,
    round(sum(sales_eur - returns_eur), 0)                              as net_sales_eur,
    round(sum(cost_of_goods_eur), 0)                                    as cost_eur,
    round(100 * sum(sales_eur - returns_eur - cost_of_goods_eur)
              / nullif(sum(sales_eur - returns_eur), 0), 1)             as margin_pct
from marts.fct_order_items
where is_valid
group by 1
order by net_sales_eur desc;

-- Check 8 Result: orders 4,512,996 EUR vs lines 4,508,731 EUR; the 4,265 EUR (0.09 %)
--   gap is the 26 orders with only invalid lines (no valid line to allocate to).
-- Check 9 Result: Electronics brings over half of the sales with the lowest margin
--   (21.8 %); Books the highest margin (31.1 %) with the smallest sales.

