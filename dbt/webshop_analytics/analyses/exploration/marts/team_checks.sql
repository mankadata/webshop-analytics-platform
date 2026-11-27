-- Checks for the team marts (marketing, operations, crm)

-- Marketing: ROAS and CAC per channel (all months)
select
    channel,
    round(sum(spend_eur), 0)                                        as spend_eur,
    sum(new_customers)                                              as new_customers,
    round(sum(net_revenue_eur), 0)                                  as net_revenue_eur,
    round(sum(net_revenue_eur) / nullif(sum(spend_eur), 0), 2)      as roas,
    round(sum(spend_eur) / nullif(sum(new_customers), 0), 2)        as cac_eur
from marts.fct_marketing_channel_monthly
group by 1
order by spend_eur desc;

-- Operations: stockout days and negative stock
select
    count(distinct product_id)                                      as products,
    count(*)                                                        as product_days,
    count(*) filter (where is_stockout)                             as stockout_days,
    round(100.0 * count(*) filter (where is_stockout) / count(*), 1) as stockout_pct,
    count(distinct product_id) filter (where is_negative_stock)     as products_with_negative_stock
from marts.fct_stock_daily;

-- CRM: segments
select segment, count(*) as customers, round(sum(monetary_eur), 0) as revenue_eur
from marts.dim_customer_segments
group by 1
order by 2 desc;

-- CRM: average retention after 1, 3 and 6 months
select
    months_since_first_order,
    round(avg(retention_rate) * 100, 1)                             as avg_retention_pct
from marts.fct_customer_cohorts
where months_since_first_order in (1, 3, 6)
group by 1
order by 1;

-- Check: new customers across all channels (should be 4405 = people with an order)
select sum(new_customers) as new_customers
from marts.fct_marketing_channel_monthly;


-- Check 7: exactly one first order per buyer?
select
    count(*) filter (where is_first_order)          as first_orders,
    count(distinct customer_key)
        filter (where invoiced_net_eur is not null) as buyers
from marts.fct_orders;



-- Marketing result: paid_search ROAS 7.4 CAC 135 | paid_social ROAS 4.7 CAC 229 |
--   email CAC 9 (ROAS 124 is inflated: newsletter readers are existing customers).
--   Bug found: new customers summed to 4,305 vs 4,405 buyers - a cancelled first
--   order hid the real first purchase. Fixed in int_shop__orders_enriched.
-- Operations result: 857 stockout days of 131,736 (0.7 %); 94 products were
--   negative at some point - sales are booked before the goods receipt (DQ14).
-- CRM result: champions 603 (12 % of customers, 38 % of revenue); at_risk 734
--   (769k EUR); lost 1,773; registered_only 721. Retention 21.7 % after 1 month,
--   20.0 % after 3, 18.4 % after 6.
-- Result: 4,385 new customers = 4,385 buyers in dim_customers (repeat 3,276 + one_time 1,109).
--   Definitions: 5,106 people registered, 4,405 placed an order, 4,385 paid for one
--   (20 people only had cancelled orders). Before the fix the marketing mart showed
--   4,305: a cancelled first order hid the real first purchase.