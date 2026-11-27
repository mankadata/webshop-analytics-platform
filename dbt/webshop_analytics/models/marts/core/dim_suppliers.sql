-- Mart (gold): supplier dimension, one row per supplier, with delivery performance.

with suppliers as (
    select distinct on (supplier_code) *
    from {{ ref('stg_erp__suppliers') }}
    order by supplier_code, recorded_on_raw desc
),

purchase_orders as (
    select * from {{ ref('int_erp__purchase_orders_cleaned') }}
)

select
    suppliers.supplier_code,
    suppliers.supplier_name,
    suppliers.country_code,
    suppliers.currency,
    suppliers.payment_terms_days,
    count(purchase_orders.po_number)                                as purchase_orders,
    count(purchase_orders.po_number) filter (where purchase_orders.po_status = 'open')
                                                                    as open_purchase_orders,
    round(avg(purchase_orders.lead_time_days), 1)                   as avg_lead_time_days,
    max(purchase_orders.lead_time_days)                             as max_lead_time_days,
    count(purchase_orders.po_number) filter (where purchase_orders.delay_days > 0)
                                                                    as late_deliveries,
    round(sum(purchase_orders.order_value_eur), 2)                  as purchase_value_eur
from suppliers
left join purchase_orders
    on purchase_orders.supplier_code = suppliers.supplier_code
group by 1, 2, 3, 4, 5
