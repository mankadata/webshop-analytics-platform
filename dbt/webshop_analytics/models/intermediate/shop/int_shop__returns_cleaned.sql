-- Intermediate (silver): one row per return, linked to the order line, valued.
-- Rules come from analyses/exploration/shop/stg_shop__returns.sql (Q1).

with returns as (
    select * from {{ ref('stg_shop__returns') }}
),

order_items as (
    select * from {{ ref('int_shop__order_items_cleaned') }}
),

final as (
    select
        returns.return_id,
        returns.order_id,
        returns.order_item_id,
        order_items.product_id,
        returns.quantity                                            as returned_quantity,
        order_items.quantity                                        as purchased_quantity,
        returns.reason_code,

        -- value of the returned goods in the order currency (refund basis)
        round(returns.quantity * order_items.unit_price_local
              * (1 - order_items.discount_pct / 100.0), 2)          as return_amount_local,

        -- shop times are Budapest local time -> UTC (timestamptz)
        returns.requested_at_local at time zone 'Europe/Budapest'   as requested_at,

        returns.quantity <= order_items.quantity
            and order_items.is_valid                                as is_valid,
        nullif(concat_ws(', ',
            case when returns.quantity > order_items.quantity
                 then 'returned_more_than_bought' end,
            case when not order_items.is_valid
                 then 'invalid_order_line' end
        ), '')                                                      as dq_issue,

        returns._batch_id,
        returns._loaded_at
    from returns
    left join order_items
        on returns.order_item_id = order_items.order_item_id
)

select * from final