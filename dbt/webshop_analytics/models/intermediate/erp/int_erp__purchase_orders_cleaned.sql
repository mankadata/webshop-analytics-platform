-- Intermediate (silver): one row per purchase order, latest status, with lines,
-- goods receipts and supplier lead time.
-- Rules come from analyses/exploration/erp/stg_erp__purchase_orders.sql (Q1-Q3).
-- The ERP exports a new version when an order is completed: NYITOTT -> TELJESITVE.

with purchase_orders as (
    select * from {{ ref('stg_erp__purchase_orders') }}
),

order_lines as (
    select * from {{ ref('stg_erp__purchase_order_lines') }}
),

receipts as (
    select * from {{ ref('int_erp__stock_movements_cleaned') }}
    where movement_type = 'goods_receipt'
),

fx_rates as (
    select * from {{ ref('int_ecb__fx_rates_daily') }}
),

-- Q3: one row per purchase order = the latest version
latest as (
    select
        po_number,
        supplier_code,
        to_date(order_date_raw,    'YYYY.MM.DD.')                   as order_date,
        to_date(expected_date_raw, 'YYYY.MM.DD.')                   as expected_date,
        status_code,
        row_number() over (
            partition by po_number
            order by to_date(modified_on_raw, 'YYYY.MM.DD.') desc,
                     case status_code when 'TELJESITVE' then 1 else 2 end
        )                                                           as version_rank
    from purchase_orders
),

-- Q2: lines in Hungarian number format, one currency per supplier
lines as (
    select
        po_number,
        min(currency)                                               as currency,
        count(*)                                                    as line_count,
        sum(quantity)                                               as ordered_units,
        sum(quantity * cast(replace(regexp_replace(unit_cost_raw, '[^0-9,-]', '', 'g'), ',', '.') as numeric))
                                                                    as order_value_local
    from order_lines
    group by po_number
),

received as (
    select
        po_number,
        min(movement_date)                                          as first_received_date,
        max(movement_date)                                          as last_received_date,
        sum(stock_change)                                           as received_units
    from receipts
    group by po_number
),

final as (
    select
        latest.po_number,
        latest.supplier_code,
        case latest.status_code
            when 'NYITOTT'    then 'open'
            when 'TELJESITVE' then 'completed'
        end                                                         as po_status,
        latest.order_date,
        latest.expected_date,

        lines.line_count,
        lines.ordered_units,
        lines.currency,
        round(lines.order_value_local, 2)                           as order_value_local,
        round(lines.order_value_local / fx_rates.units_per_eur, 2)  as order_value_eur,

        received.first_received_date,
        received.last_received_date,
        received.received_units,

        -- supplier lead time: order to first goods receipt; delay against the promise
        received.first_received_date - latest.order_date            as lead_time_days,
        received.first_received_date - latest.expected_date         as delay_days,

        nullif(concat_ws(', ',
            case when latest.status_code = 'TELJESITVE' and received.po_number is null
                 then 'completed_without_receipt' end,
            case when received.received_units <> lines.ordered_units
                 then 'received_units_differ' end
        ), '')                                                      as dq_issue
    from latest
    left join lines    on lines.po_number    = latest.po_number
    left join received on received.po_number = latest.po_number
    left join fx_rates
        on  fx_rates.currency  = lines.currency
        and fx_rates.rate_date = latest.order_date
    where latest.version_rank = 1
)

select * from final