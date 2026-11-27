-- Mart (gold): calendar dimension, one row per day.
-- Covers the whole life of the company so every fact can join on a date.

with days as (
    select cast(day as date) as date_day
    from generate_series(date '2025-01-01', date '2026-12-31', interval '1 day') as day
)

select
    date_day,
    cast(extract(year    from date_day) as integer)                 as year,
    cast(extract(quarter from date_day) as integer)                 as quarter,
    cast(extract(month   from date_day) as integer)                 as month,
    to_char(date_day, 'YYYY-MM')                                    as year_month,
    to_char(date_day, 'FMMonth')                                    as month_name,
    cast(extract(isoyear from date_day) as integer)                 as iso_year,
    cast(extract(week    from date_day) as integer)                 as iso_week,
    cast(extract(isodow  from date_day) as integer)                 as day_of_week,   -- 1 = Monday
    to_char(date_day, 'FMDay')                                      as day_name,
    extract(isodow from date_day) in (6, 7)                         as is_weekend,
    cast(date_trunc('month', date_day) as date)                     as first_day_of_month
from days
