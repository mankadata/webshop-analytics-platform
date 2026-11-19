-- Staging: shop customers. One row per customer version (every profile change is a new row).
-- Values that need real cleaning keep a _raw suffix; they are standardised in intermediate.
with source as (
    select * from {{ source('shop', 'customers') }}
),

renamed as (
    select
        cast(customer_id as integer)            as customer_id,
        first_name                              as first_name_raw,
        last_name                               as last_name_raw,
        email                                   as email_raw,
        coalesce(phone_number, phone)           as phone_raw,           -- column renamed on 2026-03-01 (DQ15)
        country                                 as country_raw,         -- 'HU', 'hu', 'Hungary', 'Magyarország' (DQ11)
        postal_code                             as postal_code_raw,
        city,
        street,
        birth_date                              as birth_date_raw,      -- may be 'N/A' or impossible (DQ01, DQ09)
        customer_type,
        vat_number                              as vat_number_raw,
        cast(signup_at as timestamp)            as signup_at_local,
        cast(marketing_opt_in as boolean)       as is_marketing_opt_in, -- '1' / '0'
        loyalty_tier,                                                   -- new column since 2026-03-01
        cast(updated_at as timestamp)           as updated_at_local,
        _batch_id,
        _loaded_at
    from source
)

select * from renamed