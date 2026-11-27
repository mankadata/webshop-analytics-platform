-- Intermediate (silver): one row per order, current status, cleaned.
-- Rules come from analyses/exploration/intermediate/shop/stg_shop__orders.sql.
-- The source is an event log: one row per status change of an order.


with order_events as (
    select * from {{ ref('stg_shop__orders') }}
),

-- Step 1: business rank of each status (Q3: timestamps cannot be trusted)
ranked as (
    select
        *,
        case status
            when 'pending'   then 1
            when 'paid'      then 2
            when 'shipped'   then 3
            when 'delivered' then 4
            when 'returned'  then 5
            when 'cancelled' then 5
        end                                                         as status_rank
    from order_events
),

-- Step 2: one row per order
per_order as (
    select
        order_id,

        -- Q6: identical in every event, so any event will do
        min(customer_id)                                            as customer_id,
        min(ordered_at_local)                                       as ordered_at_local,
        min(currency)                                               as currency,
        min(payment_method)                                         as payment_method,
        min(sales_channel)                                          as sales_channel,
        min(shipping_country)                                       as shipping_country,
        min(shipping_fee_local)                                     as shipping_fee_local,

        -- Q3: current status = highest business rank among non-null statuses
        (array_agg(status order by status_rank desc nulls last, updated_at_local desc))[1]
                                                                    as order_status,

        -- milestone timestamps (local time, converted below)
        min(updated_at_local) filter (where status = 'paid')        as paid_at_local,
        min(updated_at_local) filter (where status = 'shipped')     as shipped_at_local,
        min(updated_at_local) filter (where status = 'delivered')   as delivered_at_local,
        min(updated_at_local) filter (where status = 'returned')    as returned_at_local,
        min(updated_at_local) filter (where status = 'cancelled')   as cancelled_at_local,
        max(updated_at_local)                                       as last_event_at_local,

        count(*)                                                    as event_count,
        count(*) filter (where status is null)                      as missing_status_events,

        max(_batch_id)                                              as _batch_id,
        max(_loaded_at)                                             as _loaded_at
    from ranked
    group by order_id
),

final as (
    select
        order_id,
        customer_id,
        order_status,
        payment_method,
        payment_method = 'cash_on_delivery'                         as is_cash_on_delivery,

        -- Q4/Q5: paid event, or a prepaid order that was shipped,
        -- or a cash-on-delivery order that was delivered
        paid_at_local is not null
            or (payment_method <> 'cash_on_delivery'
                and coalesce(shipped_at_local, delivered_at_local, returned_at_local) is not null)
            or (payment_method = 'cash_on_delivery' and delivered_at_local is not null)
                                                                    as is_paid,

        sales_channel,
        shipping_country,
        currency,
        shipping_fee_local,

        -- shop times are Budapest local time -> UTC (timestamptz)
        ordered_at_local    at time zone 'Europe/Budapest'          as ordered_at,
        paid_at_local       at time zone 'Europe/Budapest'          as paid_at,
        shipped_at_local    at time zone 'Europe/Budapest'          as shipped_at,
        delivered_at_local  at time zone 'Europe/Budapest'          as delivered_at,
        returned_at_local   at time zone 'Europe/Budapest'          as returned_at,
        cancelled_at_local  at time zone 'Europe/Budapest'          as cancelled_at,
        last_event_at_local at time zone 'Europe/Budapest'          as last_event_at,

        event_count,

        nullif(concat_ws(', ',
            case when missing_status_events > 0 then 'missing_status_event' end,
            case when returned_at_local < delivered_at_local then 'status_out_of_order' end
        ), '')                                                      as dq_issue,

        _batch_id,
        _loaded_at
    from per_order
)

select * from final