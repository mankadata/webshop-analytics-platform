-- Check: every day has a rate for every currency (missing_rate should be 0)
select
    currency,
    count(*)                                            as days,
    count(*) filter (where units_per_eur is null)       as missing_rate,
    count(*) filter (where is_carried_forward)          as carried_forward_days
from intermediate.int_ecb__fx_rates_daily
group by currency
order by currency;

-- Result: EUR / HUF / USD - 693 days each, missing_rate 0,
--         carried forward: HUF 210, USD 210 (= 693 calendar days - 483 published days).