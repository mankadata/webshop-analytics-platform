-- Intermediate (silver): one EUR exchange rate for every calendar day and currency.
-- The ECB publishes rates on business days only; weekends and holidays get the
-- rate of the last business day before them (the usual accounting convention).

with rates as (
    select * from {{ ref('stg_ecb__fx_rates') }}
),

currencies as (
    select distinct currency from rates
),

calendar as (
    select cast(day as date) as rate_date
    from generate_series(
        (select min(rate_date) from rates),
        current_date,
        interval '1 day'
    ) as day
),

-- every day x every currency, with the last published rate on or before that day
filled as (
    select
        calendar.rate_date,
        currencies.currency,
        last_rate.units_per_eur,
        last_rate.rate_date                                         as published_on
    from calendar
    cross join currencies
    left join lateral (
        select rates.units_per_eur, rates.rate_date
        from rates
        where rates.currency = currencies.currency
          and rates.rate_date <= calendar.rate_date
        order by rates.rate_date desc
        limit 1
    ) as last_rate on true
),

final as (
    select
        rate_date,
        currency,
        units_per_eur,
        published_on,
        rate_date <> published_on                                   as is_carried_forward
    from filled

    union all

    -- EUR itself, so every amount can be joined the same way
    select rate_date, 'EUR', 1.0, rate_date, false
    from calendar
)

select * from final