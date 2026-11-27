-- Mart (gold): CRM segment of every customer (real person), RFM based.
-- Grain: one row per customer.
-- Recency is measured against the last order date in the data, not today, so the
-- segments stay meaningful even when no new data arrives.

with customers as (
    select * from {{ ref('dim_customers') }}
),

reference_date as (
    select max(order_date) as as_of_date
    from {{ ref('fct_orders') }}
    where invoiced_net_eur is not null
)

select
    customers.customer_key,
    customers.country_code,
    customers.customer_type,
    customers.buyer_type,
    customers.order_count                                           as frequency,
    customers.lifetime_revenue_eur                                  as monetary_eur,
    reference_date.as_of_date - customers.last_order_date           as recency_days,
    reference_date.as_of_date,
    case
        when customers.order_count = 0                                       then 'registered_only'
        when customers.order_count >= 5
         and reference_date.as_of_date - customers.last_order_date <= 90     then 'champion'
        when customers.order_count >= 2
         and reference_date.as_of_date - customers.last_order_date <= 90     then 'loyal'
        when customers.order_count = 1
         and reference_date.as_of_date - customers.last_order_date <= 90     then 'new'
        when customers.order_count >= 2
         and reference_date.as_of_date - customers.last_order_date <= 180    then 'at_risk'
        else                                                                       'lost'
    end                                                             as segment
from customers
cross join reference_date