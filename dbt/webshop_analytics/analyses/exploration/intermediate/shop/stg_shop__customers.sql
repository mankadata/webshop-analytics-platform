-- Exploration: stg_shop__customers
-- Goal: understand the dirty columns before writing int_shop__customers_cleaned.

select * from staging.stg_shop__customers limit 10;



-- Phone number shapes
select
    regexp_replace(phone_raw, '[0-9]', '9', 'g')  as phone_shape,
    count(*)                                      as row_count,
    min(phone_raw)                                as example
from staging.stg_shop__customers
group by 1
order by row_count desc;

-- Finding:
--          Phone numbers come in 20+ shapes. The same Hungarian (+36) or Czech (+420)
--          number is written with or without '+', with spaces, dashes and slashes,
--          with the '00' international prefix, or with the Hungarian '06' domestic
--          prefix. 478 rows hold a placeholder instead of a number ('-', 'nincs',
--          'N/A', '0'); 124 rows are null.
-- Fix in intermediate:
--          1. placeholders -> null
--          2. keep digits only (remove spaces, '-', '/', '+')
--          3. leading '00' -> remove it
--          4. leading '06' -> replace with '36'
--          5. add '+' in front -> E.164 format, e.g. '+36151002155'
--          Rule check after the fix: every phone is null or matches '^\+[0-9]{10,14}$'.



-------

-- Q2: E-mail quality - casing, spaces and invalid syntax
select
    case
        when email_raw is null                              then '1 null'
        when email_raw <> trim(email_raw)                   then '2 leading or trailing space'
        when email_raw <> lower(email_raw)                  then '3 upper case letters'
        when email_raw !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'    then '4 invalid syntax'
        else                                                     '5 valid'
    end                     as email_check,
    count(*)                as row_count,
    min(email_raw)          as example
from staging.stg_shop__customers
group by 1
order by 1;

--Finding: 
--Every customer has an e-mail address (no nulls). 594 rows differ only
--          in formatting: leading or trailing spaces (212) or upper case letters (382).
--          63 rows have invalid syntax, e.g. a double '@@' or a missing domain ending.
--          (Each row is counted in its first matching group only.)
-- Fix in intermediate:
--          1. email = lower(trim(email_raw))
--          2. if the result still fails the syntax check -> email = null,
--             flagged with dq_issue 'invalid_email'. Not repaired: guessing the
--             right address is risky, the original stays in email_raw.
--          Rule check after the fix: every email is null or matches
--          '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'


-----
--Same person, several customer accounts
-- After normalising the e-mail, how many customer ids share one address?

with emails as (
    select distinct
        customer_id,
        lower(trim(email_raw))  as email
    from staging.stg_shop__customers
)

select
    ids_per_email,
    count(*)                    as email_count,
    min(email)                  as example
from (
    select email, count(*) as ids_per_email
    from emails
    group by email
) as per_email
group by ids_per_email
order by ids_per_email;

--check
select
    lower(trim(email_raw))          as email,
    customer_id,
    email_raw
from staging.stg_shop__customers
where lower(trim(email_raw)) = 'angela.riepl39@gmail.com'
order by customer_id;

-- Finding: Once the e-mail is normalised (lower case, no spaces), 87 addresses
--          belong to 2 or 3 customer ids: the same person registered several times.
--          That is 91 surplus accounts, which would inflate the customer count and
--          hide repeat purchases.
-- Fix in intermediate: new model int_shop__customer_identity maps every customer_id
--          to a master_customer_id = the oldest (lowest) customer_id with the same
--          valid, normalised e-mail. Invalid e-mails are not matched (each keeps its
--          own id). Original customer_ids are kept, so orders still join.


----
-- Name formatting - casing and extra spaces
select
    case
        when first_name_raw is null or last_name_raw is null                     then '1 missing'
        when first_name_raw <> trim(first_name_raw)
          or last_name_raw  <> trim(last_name_raw)                               then '2 leading or trailing space'
        when first_name_raw = upper(first_name_raw)
          or last_name_raw  = upper(last_name_raw)                               then '3 all upper case'
        when first_name_raw = lower(first_name_raw)
          or last_name_raw  = lower(last_name_raw)                               then '4 all lower case'
        else                                                                          '5 looks fine'
    end                                         as name_check,
    count(*)                                    as row_count,
    min(first_name_raw || ' ' || last_name_raw) as example
from staging.stg_shop__customers
group by 1
order by 1;


-- Finding: No missing names and no extra spaces. 134 rows have wrong casing:
--          a name part typed in all capitals or all lower case, often mixed within
--          one row (e.g. 'adrian GRIESSER').
-- Fix in intermediate: initcap() a name part only when it is all upper or all
--          lower case; otherwise keep it as typed (protects names like 'McDonald').
--          Check accented letters after the fix


----
-- Country spellings
select
    country_raw,
    count(*)        as row_count
from staging.stg_shop__customers
group by country_raw
order by lower(trim(country_raw)), row_count desc;

-- Finding: 7 countries are written in 35 ways: ISO 2-letter code (upper or lower
--          case), ISO 3-letter code, English name, local or Hungarian name.
--          No nulls - the total matches the row count of the table.
-- Fix in intermediate: seed country_codes.csv (spelling -> ISO 3166-1 alpha-2 code),
--          joined on lower(trim(country_raw)). A spelling missing from the seed gives
--          country_code = null and dq_issue 'unknown_country', so a test catches
--          any new spelling in tomorrow's data.


----
-- Postal code shapes per country (digits -> 9, letters -> A)
select
    upper(left(trim(country_raw), 2))                               as country_hint,
    regexp_replace(
        regexp_replace(postal_code_raw, '[0-9]', '9', 'g'),
        '[A-Za-z]', 'A', 'g')                                       as postal_shape,
    count(*)                                                        as row_count,
    min(postal_code_raw)                                            as example
from staging.stg_shop__customers
group by 1, 2
order by 1, row_count desc;

-- Finding: The rough country hint (AU, GE, MA, LE, PO, SL, SV, SZ, ÖS) shows why a
--          mapping seed is needed. Each country has one dominant postal code length
--          (AT and HU 4 digits, the others 5). 59 Hungarian codes carry the 'H-'
--          country prefix. 96 codes have the wrong length for their country.
--          Real RO (6 digits) and PL (00-950) formats differ; the rule follows the data.
-- Fix in intermediate: strip a letter prefix such as 'H-', keep digits only.
--          Expected length per country goes into the country seed. Wrong length ->
--          postal_code = null and dq_issue 'invalid_postal_code' (original kept in
--          postal_code_raw)


----
-- Birth date - placeholders, formats and impossible ages
select
    case
        when birth_date_raw is null or trim(birth_date_raw) = ''        then '1 empty'
        when upper(trim(birth_date_raw)) in ('N/A', 'NA', '-', 'NINCS') then '2 placeholder'
        else regexp_replace(birth_date_raw, '[0-9]', '9', 'g')
    end                         as birth_date_shape,
    count(*)                    as row_count,
    min(birth_date_raw)         as example_min,
    max(birth_date_raw)         as example_max
from staging.stg_shop__customers
group by 1
order by row_count desc;

--check:  Impossible birth dates (only rows that look like a date)
with dates as (
    select cast(birth_date_raw as date) as birth_date
    from staging.stg_shop__customers
    where birth_date_raw ~ '^\d{4}-\d{2}-\d{2}$'
)

select
    case
        when birth_date = date '1900-01-01'                        then '1 default 1900-01-01'
        when birth_date > current_date                             then '2 in the future'
        when birth_date > current_date - interval '16 years'       then '3 younger than 16'
        when birth_date < current_date - interval '100 years'      then '4 older than 100'
        else                                                            '5 plausible'
    end                     as age_check,
    count(*)                as row_count,
    min(birth_date)         as example_min,
    max(birth_date)         as example_max
from dates
group by 1
order by 1;

-- Finding: One date format (ISO YYYY-MM-DD), so no parsing problem. 6,101 of 7,192
--          rows (85 %) have a plausible birth date. 1,091 rows are unusable:
--          690 empty, 380 'N/A', 7 system default 1900-01-01, 9 in the future and
--          5 born this year (most likely the signup date typed in). Nobody is over 100.
-- Fix in intermediate: empty and placeholder -> null; cast to date; 1900-01-01,
--          dates after signup and age under 16 at signup -> null with dq_issue
--          'invalid_birth_date'. The age limits (16, 100) are a business rule.
--          Compare to signup_at, not current_date, so the result is stable over time.



----
-- Customer type and VAT number
select
    customer_type,
    case
        when vat_number_raw is null or trim(vat_number_raw) = ''   then '(empty)'
        else regexp_replace(
                 regexp_replace(vat_number_raw, '[0-9]', '9', 'g'),
                 '[A-Za-z]', 'A', 'g')
    end                         as vat_shape,
    count(*)                    as row_count,
    min(vat_number_raw)         as example
from staging.stg_shop__customers
group by 1, 2
order by 1, row_count desc;

-- Finding: Every company (B2B) has a VAT number and no private customer (B2C) has
--          one. Two valid formats: EU VAT number with country prefix (209) and the
--          Hungarian tax number 12345678-1-12 (160). 19 numbers are truncated.
-- Fix in intermediate: remove spaces, upper case. Valid if it matches the EU VAT
--          pattern or '^\d{8}-\d-\d{2}$'; otherwise null with dq_issue
--          'invalid_vat_number'. Test: B2B rows must have a VAT number, B2C must not


-- Versions per customer - why does one customer appear in several rows?
select
    versions,
    count(*)                        as customer_count,
    min(customer_id)                as example_customer_id
from (
    select
        customer_id,
        count(*)                    as versions
    from staging.stg_shop__customers
    group by customer_id
) as per_customer
group by versions
order by versions;

--check: 
select
    _batch_id,
    updated_at_local,
    email_raw,
    phone_raw,
    country_raw,
    postal_code_raw,
    city,
    loyalty_tier,
    is_marketing_opt_in
from staging.stg_shop__customers
where customer_id = 164
order by updated_at_local;

--Finding: One row = one state of a customer: the source sends a new row on
--          every change (change data capture). Customer 164 really changed city
--          twice, phone number once and marketing consent twice; loyalty_tier
--          appears from the 2026-03-01 schema change (DQ15). Other "changes" are
--          formatting only (same phone in three formats, HU vs Hungary) and vanish
--          after cleaning.
-- Fix in intermediate: int_shop__customers_cleaned keeps every version, cleaned.
--          int_shop__customers_latest keeps one row per customer (latest version).
--          Customer history (valid_from / valid_to) is built later in marts with
--          lead(); versions identical after cleaning are collapsed.
