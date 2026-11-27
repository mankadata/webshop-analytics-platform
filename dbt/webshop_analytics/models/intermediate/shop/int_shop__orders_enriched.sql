-- Intermediate (silver): one row per order with everything the marts need -
-- the real person behind the account, marketing channel, return flag and
-- revenue in EUR from the ERP invoices (the financial truth).

with orders as (
    select * from {{ ref('int_shop__orders_cleaned') }}
),

identity as (
    select * from {{ ref('int_shop__customer_identity') }}
),

reconciliation as (
    select * from {{ ref('int_finance__order_reconciliation') }}
),

-- net revenue = invoiced net amount minus credit notes (credit notes are negative)
invoices as (
    select
        order_id,
        sum(net_amount) filter (where not is_credit_note)          as invoiced_net_local,
        coalesce(sum(net_amount) filter (where is_credit_note), 0) as credited_net_local
    from {{ ref('int_erp__invoices_cleaned') }}
    group by order_id
),

-- the returns table, not the order status, says whether goods came back
returns as (
    select distinct order_id
    from {{ ref('int_shop__returns_cleaned') }}
),

-- marketing channel of the web session that ended with the purchase
web_sessions as (
    select distinct on (order_id)
        order_id,
        channel,
        platform
    from {{ ref('int_web__sessions') }}
    where order_id is not null
    order by order_id, session_started_at
),

final as (
    select
        orders.order_id,
        orders.ordered_at,
        cast(orders.ordered_at at time zone 'Europe/Budapest' as date)  as order_date,
        orders.customer_id,
        identity.master_customer_id,

        orders.order_status,
        orders.is_paid,
        returns.order_id is not null                                as has_return,
        orders.payment_method,
        orders.sales_channel,
        coalesce(web_sessions.channel, 'not_tracked')               as marketing_channel,
        web_sessions.platform                                       as ad_platform,
        orders.shipping_country,

        orders.currency,
        reconciliation.units_per_eur,
        reconciliation.reconciliation_status,

        -- revenue in EUR with the rate of the order day
        round(invoices.invoiced_net_local / reconciliation.units_per_eur, 2)
                                                                    as invoiced_net_eur,
        round(invoices.credited_net_local / reconciliation.units_per_eur, 2)
                                                                    as credited_net_eur,
        round((invoices.invoiced_net_local + invoices.credited_net_local)
              / reconciliation.units_per_eur, 2)                    as net_revenue_eur,
        reconciliation.paid_eur                                     as paid_gross_eur,

        -- first order of the real person (CRM: new vs returning customer)
        row_number() over (
            partition by identity.master_customer_id
            order by orders.ordered_at, orders.order_id
        )                                                           as customer_order_number
    from orders
    left join identity       on identity.customer_id      = orders.customer_id
    left join reconciliation on reconciliation.order_id   = orders.order_id
    left join invoices       on invoices.order_id         = orders.order_id
    left join returns        on returns.order_id          = orders.order_id
    left join web_sessions   on web_sessions.order_id     = orders.order_id
)

select * from final