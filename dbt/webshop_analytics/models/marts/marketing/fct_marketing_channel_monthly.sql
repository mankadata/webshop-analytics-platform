-- Mart (gold): marketing performance per month and channel.
-- Grain: one row per month x marketing channel.
-- ROAS = net revenue / ad spend; CAC = ad spend / new customers.

with spend as (
    select
        cast(date_trunc('month', report_date) as date)              as month,
        channel,
        sum(spend_eur)                                              as spend_eur,
        sum(clicks)                                                 as clicks,
        sum(impressions)                                            as impressions
    from {{ ref('int_marketing__ad_spend_cleaned') }}
    group by 1, 2
),

sessions as (
    select
        cast(date_trunc('month', session_started_at at time zone 'Europe/Budapest') as date)
                                                                    as month,
        channel,
        count(*)                                                    as sessions,
        count(*) filter (where has_added_to_cart)                   as sessions_with_cart,
        count(*) filter (where has_purchased)                       as sessions_with_purchase
    from {{ ref('int_web__sessions') }}
    group by 1, 2
),

orders as (
    select
        cast(date_trunc('month', order_date) as date)               as month,
        marketing_channel                                           as channel,
        count(*)                                                    as orders,
        count(*) filter (where is_first_order)                      as new_customers,
        sum(net_revenue_eur)                                        as net_revenue_eur,
        sum(gross_margin_eur)                                       as gross_margin_eur
    from {{ ref('fct_orders') }}
    where invoiced_net_eur is not null
    group by 1, 2
),

-- every month x channel that appears in any of the three sources
keys as (
    select month, channel from spend
    union
    select month, channel from sessions
    union
    select month, channel from orders
)

select
    keys.month,
    keys.channel,
    coalesce(spend.spend_eur, 0)                                    as spend_eur,
    coalesce(spend.impressions, 0)                                  as impressions,
    coalesce(spend.clicks, 0)                                       as clicks,
    coalesce(sessions.sessions, 0)                                  as sessions,
    coalesce(sessions.sessions_with_purchase, 0)                    as sessions_with_purchase,
    round(sessions.sessions_with_purchase::numeric / nullif(sessions.sessions, 0), 4)
                                                                    as conversion_rate,
    coalesce(orders.orders, 0)                                      as orders,
    coalesce(orders.new_customers, 0)                               as new_customers,
    coalesce(orders.net_revenue_eur, 0)                             as net_revenue_eur,
    coalesce(orders.gross_margin_eur, 0)                            as gross_margin_eur,
    round(orders.net_revenue_eur / nullif(spend.spend_eur, 0), 2)   as roas,
    round(spend.spend_eur / nullif(orders.new_customers, 0), 2)     as cac_eur
from keys
left join spend    on spend.month    = keys.month and spend.channel    = keys.channel
left join sessions on sessions.month = keys.month and sessions.channel = keys.channel
left join orders   on orders.month   = keys.month and orders.channel   = keys.channel