-- Mart (gold): customer dimension, one row per real person (several accounts with
-- the same e-mail are one customer). No names, e-mails or phone numbers here:
-- personal data stays in the intermediate layer (privacy by design).

with identity as (
    select * from {{ ref('int_shop__customer_identity') }}
),

customers as (
    select * from {{ ref('int_shop__customers_cleaned') }}
),

orders as (
    select * from {{ ref('fct_orders') }}
    where invoiced_net_eur is not null           -- paid and invoiced orders
),

-- attributes of the master (oldest) account
master_account as (
    select
        identity.master_customer_id,
        identity.accounts_per_person,
        customers.customer_type,
        customers.country_code,
        customers.city,
        customers.loyalty_tier,
        customers.is_marketing_opt_in,
        customers.signup_at
    from identity
    join customers on customers.customer_id = identity.customer_id
    where identity.is_master_account
),

order_stats as (
    select
        customer_key,
        count(*)                                                    as order_count,
        min(order_date)                                             as first_order_date,
        max(order_date)                                             as last_order_date,
        round(sum(net_revenue_eur), 2)                              as lifetime_revenue_eur,
        round(sum(gross_margin_eur), 2)                             as lifetime_margin_eur
    from orders
    group by 1
)

select
    master_account.master_customer_id                               as customer_key,
    master_account.accounts_per_person,
    master_account.customer_type,
    master_account.country_code,
    master_account.city,
    master_account.loyalty_tier,
    master_account.is_marketing_opt_in,
    master_account.signup_at,
    coalesce(order_stats.order_count, 0)                            as order_count,
    order_stats.first_order_date,
    order_stats.last_order_date,
    coalesce(order_stats.lifetime_revenue_eur, 0)                   as lifetime_revenue_eur,
    coalesce(order_stats.lifetime_margin_eur, 0)                    as lifetime_margin_eur,
    case
        when order_stats.order_count is null then 'registered_only'
        when order_stats.order_count = 1     then 'one_time'
        else                                      'repeat'
    end                                                             as buyer_type
from master_account
left join order_stats
    on order_stats.customer_key = master_account.master_customer_id
