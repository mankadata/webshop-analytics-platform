-- Mart (gold): customer retention by first-order cohort.
-- Grain: one row per cohort month x months since the first order.
-- "Of the customers who first bought in March, how many bought again 1, 2, 3 ... months later?"

with orders as (
    select
        customer_key,
        cast(date_trunc('month', order_date) as date)               as order_month
    from {{ ref('fct_orders') }}
    where invoiced_net_eur is not null
),

first_orders as (
    select customer_key, min(order_month) as cohort_month
    from orders
    group by 1
),

activity as (
    select distinct
        first_orders.cohort_month,
        orders.customer_key,
        (extract(year from orders.order_month) - extract(year from first_orders.cohort_month)) * 12
        + extract(month from orders.order_month) - extract(month from first_orders.cohort_month)
                                                                    as months_since_first_order
    from orders
    join first_orders on first_orders.customer_key = orders.customer_key
),

cohort_size as (
    select cohort_month, count(*) as customers
    from first_orders
    group by 1
)

select
    activity.cohort_month,
    cast(activity.months_since_first_order as integer)              as months_since_first_order,
    cohort_size.customers                                           as cohort_customers,
    count(distinct activity.customer_key)                           as active_customers,
    round(count(distinct activity.customer_key)::numeric / cohort_size.customers, 4)
                                                                    as retention_rate
from activity
join cohort_size on cohort_size.cohort_month = activity.cohort_month
group by 1, 2, 3
order by 1, 2