-- Check 1: idempotent load? (both numbers should be 974)
select count(*) as rows, count(distinct (date, currency)) as distinct_rates
from raw_ecb.fx_rates_live;

-- ECB API vs simulated exchange rates
-- --------------------------------------------------------------------------------
-- The real euro reference rates are loaded from the ECB Data Portal API by
-- api_ingestion/ecb_rates.py into raw_ecb.fx_rates_live (same columns as the
-- simulated raw_ecb.fx_rates). The load is idempotent: running it twice keeps
-- 974 rates for 487 business days (check 1).
--
-- Finding (check 2): the simulated HUF rate follows the real trend - the forint
--          strengthened from about 412 to 385 per EUR in 2025 - but it is 2-7 %
--          lower than the real rate every month (e.g. 2025-09: 364.39 simulated vs
--          391.63 real, -7.0 %).
--
-- Decision: the models keep using the SIMULATED rates. The synthetic company
--          priced its HUF orders, invoices and payments with its own rates;
--          switching to the real rates would shift every HUF amount by 2-7 % in
--          EUR and create false differences in the finance reconciliation.
--          The API loader stays in the project to show the ingestion pattern:
--          a real source can replace the simulated one in the raw layer without
--          changing the staging or intermediate models.
-- --------------------------------------------------------------------------------


-- Check 2: simulated vs real ECB rates, monthly average
select
    s.currency,
    to_char(cast(s.date as date), 'YYYY-MM')                     as month,
    round(avg(cast(s.rate as numeric)), 2)                       as simulated,
    round(avg(cast(l.rate as numeric)), 2)                       as real_ecb,
    round(100 * (avg(cast(s.rate as numeric)) / avg(cast(l.rate as numeric)) - 1), 1)
                                                                 as difference_pct
from raw_ecb.fx_rates as s
join raw_ecb.fx_rates_live as l
    on l.date = s.date and l.currency = s.currency
group by 1, 2
order by 1, 2;