-- Intermediate (silver): one row per payment event, deduplicated, test events flagged.
-- Rules come from analyses/exploration/payments/stg_payments__events.sql (Q1-Q3).

with events as (
    select * from {{ ref('stg_payments__events') }}
),

-- Q1: webhook retries deliver the same event more than once -> keep one per event_id
deduplicated as (
    select
        *,
        count(*) over (partition by event_id)                       as delivery_count,
        row_number() over (
            partition by event_id
            order by created_at
        )                                                           as copy_number
    from events
),

final as (
    select
        event_id,
        event_type,
        payment_id,

        -- Q2: 'WS-100001' -> 100001; test references never point to a real order
        case
            when is_livemode
                then cast(nullif(regexp_replace(order_reference, '\D', '', 'g'), '') as integer)
        end                                                         as order_id,
        order_reference,

        -- Q3: amounts arrive in hundredths for every currency (HUF too)
        cast(amount_minor / 100.0 as numeric(14, 2))                as amount_local,
        currency,

        payment_method_type,
        card_brand,
        failure_code,
        created_at,
        is_livemode,
        delivery_count,

        -- Q1/Q2: test transactions are kept but excluded from every business figure
        is_livemode                                                 as is_valid,
        case when not is_livemode then 'test_transaction' end       as dq_issue
    from deduplicated
    where copy_number = 1
)

select * from final