-- Exploration: stg_erp__suppliers, stg_erp__purchase_orders, stg_erp__purchase_order_lines
-- Q1: Purchase orders - formats, statuses, links
select
    po.status_code,
    regexp_replace(po.order_date_raw,    '[0-9]', '9', 'g')    as order_date_shape,
    regexp_replace(po.expected_date_raw, '[0-9]', '9', 'g')    as expected_date_shape,
    count(distinct po.po_number)                                as purchase_orders,
    count(*) - count(distinct po.po_number)                     as duplicate_rows,
    count(distinct po.po_number) filter (where s.supplier_code is null)
                                                                as unknown_supplier,
    min(po.order_date_raw)                                      as example_order_date
from staging.stg_erp__purchase_orders as po
left join (select distinct supplier_code from staging.stg_erp__suppliers) as s
    on po.supplier_code = s.supplier_code
group by 1, 2, 3
order by purchase_orders desc;

-- Finding: Statuses in Hungarian. The two groups probably overlap: a purchase order
--          is exported again when it is completed (versioned table) - checked in Q3.

-- Q2: Purchase order lines - SKU, quantity and cost formats
select
    case
        when sku_raw = upper(trim(sku_raw))                                         then '1 clean'
        when upper(trim(sku_raw)) in (select sku from intermediate.int_shop__products_cleaned)
                                                                                    then '2 messy, but matches'
        else                                                                             '3 no matching product'
    end                                                     as sku_check,
    regexp_replace(unit_cost_raw, '[0-9]', '9', 'g')        as cost_shape,
    currency,
    count(*)                                                as lines,
    count(*) filter (where quantity <= 0)                   as invalid_quantity,
    min(unit_cost_raw)                                      as example_cost
from staging.stg_erp__purchase_order_lines
group by 1, 2, 3
order by lines desc;

-- Finding: Clean lines; unit cost in Hungarian number format, EUR or HUF depending
--          on the supplier. 1,512 lines vs 1,443 goods receipts - see the PO statuses.
-- Fix in intermediate: parse the cost like the invoices; convert HUF to EUR with the
--          ECB rate of the order date.

-- Q3: Versions per purchase order, modified_on format, link to goods receipts
with po as (
    select
        po_number,
        count(*)                                                    as versions,
        string_agg(status_code, ' > ' order by modified_on_raw)     as status_path,
        min(regexp_replace(modified_on_raw, '[0-9]', '9', 'g'))     as modified_on_shape
    from staging.stg_erp__purchase_orders
    group by po_number
),

receipts as (
    select po_number, count(*) as receipt_movements
    from intermediate.int_erp__stock_movements_cleaned
    where movement_type = 'goods_receipt'
    group by po_number
)

select
    po.versions,
    po.status_path,
    po.modified_on_shape,
    count(*)                                                as purchase_orders,
    count(*) filter (where r.po_number is not null)         as with_goods_receipt,
    min(po.po_number)                                       as example_po
from po
left join receipts as r
    on r.po_number = po.po_number
group by 1, 2, 3
order by purchase_orders desc;

-- Finding: The table is versioned: a purchase order is exported again when it is
--          completed. 1,056 purchase orders: 1,027 completed - each with a goods
--          receipt in the warehouse - and 29 still open (not yet received).
-- Fix in intermediate: one row per purchase order (latest version), with order
--          value, goods receipt dates and supplier lead time.

