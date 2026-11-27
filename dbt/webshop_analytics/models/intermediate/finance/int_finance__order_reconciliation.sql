-- Intermediate (silver): one row per order, the three systems side by side.
-- shop (what should be paid) vs payments (what was paid) vs ERP (what was invoiced).
-- Rules come from analyses/exploration/intermediate/finance/reconciliation.sql (Q1-Q3).

with orders as (
    select * from {{ ref('int_shop__orders_cleaned') }}
),

order_lines as (
    select
        order_id,
        sum(net_amount_local)                                       as lines_total_local,
        bool_or(not is_valid)                                       as has_invalid_line
    from {{ ref('int_shop__order_items_cleaned') }}
    group by order_id
),

payments as (
    select
        order_id,
        sum(amount_local) filter (where event_type = 'charge.succeeded')    as paid_local,
        sum(amount_local) filter (where event_type = 'refund.succeeded')    as refunded_local
    from {{ ref('int_payments__events_cleaned') }}
    where is_valid
    group by order_id
),

documents as (
    select
        order_id,
        sum(gross_amount) filter (where not is_credit_note)         as invoiced_local,
        sum(gross_amount) filter (where is_credit_note)             as credited_local
    from {{ ref('int_erp__invoices_cleaned') }}
    group by order_id
),

fx_rates as (
    select * from {{ ref('int_ecb__fx_rates_daily') }}
),

combined as (
    select
        orders.order_id,
        orders.ordered_at,
        orders.order_status,
        orders.payment_method,
        orders.currency,
        order_lines.has_invalid_line,

        order_lines.lines_total_local + orders.shipping_fee_local   as order_total_local,
        payments.paid_local,
        documents.invoiced_local,
        payments.refunded_local,
        documents.credited_local,

        -- rounding tolerance: 2 Ft for HUF, 5 cents for EUR
        case when orders.currency = 'HUF' then 2 else 0.05 end     as tolerance,

        -- rate of the order day (Budapest calendar day)
        fx_rates.units_per_eur
    from orders
    left join order_lines on order_lines.order_id = orders.order_id
    left join payments    on payments.order_id    = orders.order_id
    left join documents   on documents.order_id   = orders.order_id
    left join fx_rates
        on  fx_rates.currency  = orders.currency
        and fx_rates.rate_date = cast(orders.ordered_at at time zone 'Europe/Budapest' as date)
),

final as (
    select
        order_id,
        ordered_at,
        order_status,
        payment_method,
        currency,
        has_invalid_line,

        order_total_local,
        paid_local,
        invoiced_local,
        refunded_local,
        credited_local,

        round(paid_local - order_total_local, 2)                    as paid_minus_order_local,
        round(invoiced_local - paid_local, 2)                       as invoiced_minus_paid_local,

        -- everything in EUR with the ECB rate of the order day
        units_per_eur,
        round(order_total_local / units_per_eur, 2)                 as order_total_eur,
        round(paid_local        / units_per_eur, 2)                 as paid_eur,
        round(invoiced_local    / units_per_eur, 2)                 as invoiced_eur,

        case
            when paid_local is null and invoiced_local is null      then 'not_paid'
            when paid_local is null or invoiced_local is null       then 'missing_document'
            when abs(paid_local - order_total_local) <= tolerance
             and abs(invoiced_local - paid_local) <= tolerance      then 'matched'
            when has_invalid_line                                   then 'invalid_order_line'
            when abs(invoiced_local - order_total_local) <= tolerance
             and paid_local < order_total_local                     then 'underpaid'
            else                                                         'unexplained'
        end                                                         as reconciliation_status,

        -- refunds and credit notes must cancel out
        abs(coalesce(refunded_local, 0) + coalesce(credited_local, 0)) <= tolerance
                                                                    as is_refund_matched
    from combined
)

select * from final