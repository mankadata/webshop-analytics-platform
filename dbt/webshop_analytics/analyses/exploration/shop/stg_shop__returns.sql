-- Exploration: stg_shop__returns
-- Goal: check grain, links and quantities before writing int_shop__returns_cleaned.

-- Q1: Overview - duplicates, links to orders / order lines, quantities
select
    count(*)                                                    as row_count,
    count(distinct return_id)                                   as distinct_return_ids,
    count(*) filter (where o.order_id is null)                  as unknown_order,
    count(*) filter (where i.order_item_id is null)             as unknown_order_item,
    count(*) filter (where r.quantity > i.quantity)             as returned_more_than_bought,
    count(*) filter (where r.quantity <= 0)                     as invalid_quantity,
    count(distinct r.order_id)                                  as orders_with_returns
from staging.stg_shop__returns as r
left join intermediate.int_shop__orders_cleaned as o
    on r.order_id = o.order_id
left join intermediate.int_shop__order_items_cleaned as i
    on r.order_item_id = i.order_item_id;

    -- Finding: Returns are clean and fully linked to orders and order lines.
--          4 returns exceed the purchased quantity (DQ09), probably lines with an
--          invalid quantity. 994 orders have returns vs 992 with status 'returned'.
-- Fix in intermediate: flag 'returned_more_than_bought' and 'invalid_order_line';
--          value each return with the order line price and discount.

