{{ config(severity='warn') }}

-- Singular test (warning): the monthly gross margin stays between 10 % and 40 %.
-- This test would have caught the missing purchase costs that made the 2025
-- margin look like 27 % instead of 23 %.

select
    cast(date_trunc('month', order_date) as date)                   as month,
    round(100 * sum(gross_margin_eur) / nullif(sum(net_revenue_eur), 0), 1)
                                                                    as gross_margin_pct
from {{ ref('fct_orders') }}
where invoiced_net_eur is not null
group by 1
having sum(gross_margin_eur) / nullif(sum(net_revenue_eur), 0) not between 0.10 and 0.40
