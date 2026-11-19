-- Profiling 01 - overview of the raw layer
-- How much data does each source deliver, over which period, in how many daily batches?

select
    source_table,
    rows,
    batches,
    first_batch,
    last_batch,
    round(rows::numeric / batches, 1) as avg_rows_per_batch
from (
    select 'shop.customers' as source_table, count(*) as rows, count(distinct _batch_id) as batches,
           min(_batch_id) as first_batch, max(_batch_id) as last_batch from raw_shop.customers
    union all select 'shop.products', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_shop.products
    union all select 'shop.orders', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_shop.orders
    union all select 'shop.order_items', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_shop.order_items
    union all select 'shop.returns', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_shop.returns
    union all select 'payments.events', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_payments.events
    union all select 'erp.suppliers', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_erp.suppliers
    union all select 'erp.purchase_orders', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_erp.purchase_orders
    union all select 'erp.purchase_order_lines', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_erp.purchase_order_lines
    union all select 'erp.stock_movements', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_erp.stock_movements
    union all select 'erp.invoices', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_erp.invoices
    union all select 'marketing.ad_reports', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_marketing.ad_reports
    union all select 'web.events', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_web.events
    union all select 'ecb.fx_rates', count(*), count(distinct _batch_id), min(_batch_id), max(_batch_id) from raw_ecb.fx_rates
) as t
order by rows desc;

