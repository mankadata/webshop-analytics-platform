-- Intermediate (silver): one row per customer, latest state, cleaned.
-- Every rule below comes from analyses/exploration/stg_shop__customers.sql (Q1-Q9).
-- Values that cannot be repaired become null and are listed in dq_issue.

with customers as (
    select * from {{ ref('stg_shop__customers') }}
),

countries as (
    select * from {{ ref('country_codes') }}
),

-- Step 1: prepare helper values (still one row per customer version)
prepared as (
    select
        customers.*,
        countries.country_code,
        countries.postal_code_length,

        -- Q1: placeholders -> null, otherwise keep digits only
        case
            when upper(trim(customers.phone_raw)) in ('N/A', '-', 'NINCS', '0') then null
            else nullif(regexp_replace(customers.phone_raw, '[^0-9]', '', 'g'), '')
        end                                                         as phone_digits,

        -- Q2: lower case, no spaces
        lower(trim(customers.email_raw))                            as email_normalized,

        -- Q6: remove a letter prefix such as 'H-'
        regexp_replace(upper(trim(customers.postal_code_raw)), '^[A-Z]+-', '')
                                                                    as postal_code_trimmed,

        -- Q7: only values that look like a date are cast
        case
            when customers.birth_date_raw ~ '^\d{4}-\d{2}-\d{2}$'
                then cast(customers.birth_date_raw as date)
        end                                                         as birth_date_parsed,

        -- Q8: no spaces, upper case
        upper(regexp_replace(customers.vat_number_raw, '\s', '', 'g'))
                                                                    as vat_number_normalized

    from customers
    -- Q5: country spelling -> ISO code (both sides lower case, so 'hu' = 'HU')
    left join countries
        on lower(trim(customers.country_raw)) = lower(countries.spelling)
),

-- Step 2: apply the rules
cleaned as (
    select
        customer_id,

        -- Q4: fix casing only when a name part is all upper or all lower case
        case
            when trim(first_name_raw) in (upper(trim(first_name_raw)), lower(trim(first_name_raw)))
                then initcap(trim(first_name_raw))
            else trim(first_name_raw)
        end                                                         as first_name,
        case
            when trim(last_name_raw) in (upper(trim(last_name_raw)), lower(trim(last_name_raw)))
                then initcap(trim(last_name_raw))
            else trim(last_name_raw)
        end                                                         as last_name,

        email_normalized,
        email_normalized ~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'           as is_email_valid,

        -- Q1: '00' prefix removed, Hungarian '06' -> '36', then '+' in front (E.164)
        '+' || case
                   when phone_digits like '00%' then substr(phone_digits, 3)
                   when phone_digits like '06%' then '36' || substr(phone_digits, 3)
                   else phone_digits
               end                                                  as phone_e164,
        phone_digits,

        country_code,
        postal_code_trimmed,
        postal_code_trimmed ~ '^\d+$'
            and length(postal_code_trimmed) = postal_code_length    as is_postal_code_valid,
        trim(city)                                                  as city,
        trim(street)                                                as street,

        -- Q7: impossible dates are rejected; compared to signup, so stable over time
        birth_date_parsed,
        birth_date_parsed is not null
            and birth_date_parsed <> date '1900-01-01'
            and birth_date_parsed <= cast(signup_at_local as date) - interval '16 years'
                                                                    as is_birth_date_valid,

        upper(trim(customer_type))                                  as customer_type,
        vat_number_normalized,
        vat_number_normalized ~ '^[A-Z]{2}[A-Z0-9]{8,12}$'
            or vat_number_normalized ~ '^\d{8}-\d-\d{2}$'           as is_vat_number_valid,

        is_marketing_opt_in,
        loyalty_tier,

        -- shop times are Budapest local time -> UTC (timestamptz)
        signup_at_local at time zone 'Europe/Budapest'              as signup_at,
        updated_at_local at time zone 'Europe/Budapest'             as updated_at,

        _batch_id,
        _loaded_at
    from prepared
),

-- Step 3: keep the latest version per customer (Q9)
latest as (
    select
        *,
        count(*) over (partition by customer_id)                    as version_count,
        row_number() over (
            partition by customer_id
            order by updated_at desc, _loaded_at desc
        )                                                           as version_rank
    from cleaned
),

final as (
    select
        customer_id,
        first_name,
        last_name,
        case when is_email_valid then email_normalized end          as email,
        case
            when phone_digits is not null and phone_e164 ~ '^\+[0-9]{10,14}$'
                then phone_e164
        end                                                         as phone,
        country_code,
        case when is_postal_code_valid then postal_code_trimmed end as postal_code,
        city,
        street,
        case when is_birth_date_valid then birth_date_parsed end    as birth_date,
        customer_type,
        case when is_vat_number_valid then vat_number_normalized end as vat_number,
        is_marketing_opt_in,
        loyalty_tier,
        signup_at,
        updated_at,
        version_count,

        -- every rule that failed, comma separated; null = clean row
        nullif(concat_ws(', ',
            case when not is_email_valid then 'invalid_email' end,
            case when phone_digits is not null
                  and phone_e164 !~ '^\+[0-9]{10,14}$' then 'invalid_phone' end,
            case when country_code is null then 'unknown_country' end,
            case when postal_code_trimmed is not null and country_code is not null
                  and not is_postal_code_valid then 'invalid_postal_code' end,
            case when birth_date_parsed is not null
                  and not is_birth_date_valid then 'invalid_birth_date' end,
            case when vat_number_normalized is not null
                  and not coalesce(is_vat_number_valid, false) then 'invalid_vat_number' end
        ), '')                                                      as dq_issue,

        _batch_id,
        _loaded_at
    from latest
    where version_rank = 1
)

select * from final