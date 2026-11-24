-- Exploration: stg_ecb__fx_rates
-- Q1: Currencies, date range, gaps and duplicates
select
    currency,
    count(*)                                                    as row_count,
    count(distinct rate_date)                                   as distinct_days,
    min(rate_date)                                              as first_day,
    max(rate_date)                                              as last_day,
    (max(rate_date) - min(rate_date) + 1)                       as calendar_days,
    count(*) filter (where extract(isodow from rate_date) >= 6) as weekend_rows,
    min(units_per_eur)                                          as min_rate,
    max(units_per_eur)                                          as max_rate
from staging.stg_ecb__fx_rates
group by currency
order by currency;

-- Finding: Rates for HUF and USD on every business day, no duplicates, no weekend
--          rows: the ECB publishes Monday to Friday only. 192 calendar days have no
--          rate, so an order placed on a weekend cannot be converted directly.
-- Fix in intermediate: int_ecb__fx_rates_daily - one rate per calendar day and
--          currency; weekends get the last business day's rate (is_carried_forward);
--          EUR added with rate 1.0.

