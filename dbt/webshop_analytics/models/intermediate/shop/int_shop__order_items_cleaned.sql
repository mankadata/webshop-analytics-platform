-- Intermediate (silver): one row per order line, deduplicated and validated.
-- Rules come from analyses/exploration/intermediate/shop/stg_shop__order_items.sql (Q1-Q4).
-- Invalid lines are kept but flagged (is_valid = false), so nothing disappears
-- silently; marts use only valid lines, the quarantine view lists the others.

with order_items as (
    select * from {{ ref('stg_shop__order_items') }}
),

products as (
    select distinct product_id from {{ ref('stg_shop__products') }}
),

-- Q2: exact duplicates from the same file -> keep one row per order_item_id
deduplicated as (
    select
        *,
        row_number() over (
            partition by order_item_id
            order by _loaded_at
        )                                                           as copy_number
    from order_items
),

validated as (
    select
        deduplicated.*,
        products.product_id is not null                             as is_known_product,
        quantity > 0                                                as is_quantity_valid,
        discount_pct between 0 and 100                              as is_discount_valid
    from deduplicated
    -- Q4: lines for products that do not exist
    left join products
        on deduplicated.product_id = products.product_id
    where copy_number = 1
),

final as (
    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price_local,
        discount_pct,

        -- line amounts in the order currency (converted to EUR later)
        quantity * unit_price_local                                 as gross_amount_local,
        round(quantity * unit_price_local * discount_pct / 100.0, 2)
                                                                    as discount_amount_local,
        round(quantity * unit_price_local * (1 - discount_pct / 100.0), 2)
                                                                    as net_amount_local,

        -- shop times are Budapest local time -> UTC (timestamptz)
        created_at_local at time zone 'Europe/Budapest'             as created_at,

        -- Q3/Q4: a line is valid only if every rule passes
        is_known_product and is_quantity_valid and is_discount_valid
                                                                    as is_valid,
        nullif(concat_ws(', ',
            case when not is_quantity_valid then 'invalid_quantity' end,
            case when not is_discount_valid then 'invalid_discount' end,
            case when not is_known_product  then 'unknown_product' end
        ), '')                                                      as dq_issue,

        _batch_id,
        _loaded_at
    from validated
)

select * from final