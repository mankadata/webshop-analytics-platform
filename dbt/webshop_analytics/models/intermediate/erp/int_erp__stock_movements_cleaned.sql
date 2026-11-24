-- Intermediate (silver): one row per stock movement, parsed and signed.
-- Rules come from analyses/exploration/erp/stg_erp__stock_movements.sql (Q1-Q2).
-- The ERP stores quantities as positive numbers; the direction comes from the code:
--   ELAD = sale (out), BEV = goods receipt (in), VISSZ = customer return (in),
--   LELT = stock count adjustment (signed: shrinkage is negative on purpose).

with movements as (
    select * from {{ ref('stg_erp__stock_movements') }}
),

products as (
    select product_id, sku from {{ ref('int_shop__products_cleaned') }}
),

parsed as (
    select
        movement_id,
        to_date(movement_date_raw, 'YYYY.MM.DD.')                   as movement_date,
        warehouse_code,
        upper(trim(sku_raw))                                        as sku,
        movement_code,
        quantity,
        cast(replace(regexp_replace(unit_cost_eur_raw, '[^0-9,-]', '', 'g'), ',', '.') as numeric(12, 2))
                                                                    as unit_cost_eur,
        reference,
        note,
        sku_raw <> upper(trim(sku_raw))                             as was_sku_reformatted
    from movements
),

final as (
    select
        parsed.movement_id,
        parsed.movement_date,
        parsed.warehouse_code,
        parsed.sku,
        products.product_id,

        case parsed.movement_code
            when 'ELAD'  then 'sale'
            when 'BEV'   then 'goods_receipt'
            when 'VISSZ' then 'customer_return'
            when 'LELT'  then 'stock_count_adjustment'
        end                                                         as movement_type,

        parsed.quantity                                             as quantity_raw,

        -- signed change of the stock: sales go out, receipts and returns come in,
        -- stock count adjustments keep their own sign (Q1: 66 sales had a wrong minus)
        case parsed.movement_code
            when 'ELAD'  then -abs(parsed.quantity)
            when 'BEV'   then  abs(parsed.quantity)
            when 'VISSZ' then  abs(parsed.quantity)
            when 'LELT'  then  parsed.quantity
        end                                                         as stock_change,

        parsed.unit_cost_eur,

        -- references: 'WS-100001' = shop order, 'PO-2025-00001' = purchase order
        case when parsed.reference like 'WS-%'
             then cast(regexp_replace(parsed.reference, '\D', '', 'g') as integer)
        end                                                         as order_id,
        case when parsed.reference like 'PO-%' then parsed.reference end
                                                                    as po_number,
        parsed.note,
        parsed.was_sku_reformatted,

        nullif(concat_ws(', ',
            case when parsed.movement_code = 'ELAD' and parsed.quantity < 0
                 then 'sign_corrected' end,
            case when products.product_id is null then 'unknown_sku' end,
            case when parsed.movement_code not in ('ELAD', 'BEV', 'VISSZ', 'LELT')
                 then 'unknown_movement_code' end
        ), '')                                                      as dq_issue
    from parsed
    left join products
        on parsed.sku = products.sku
)

select * from final