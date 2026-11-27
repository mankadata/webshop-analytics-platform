{{ config(severity='warn') }}

-- Singular test (warning): no product ends the last day with negative stock.
-- Known case: 4 products were sold before a goods receipt was recorded (DQ14) -
-- the warning keeps the list visible for the warehouse team.

select product_id, date_day, stock_on_hand
from {{ ref('fct_stock_daily') }}
where date_day = (select max(date_day) from {{ ref('fct_stock_daily') }})
  and stock_on_hand < 0
