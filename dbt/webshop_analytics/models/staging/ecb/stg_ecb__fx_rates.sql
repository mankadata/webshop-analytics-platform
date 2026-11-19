-- Staging: ECB euro reference rates (units of currency per 1 EUR), business days only.
with source as (
    select * from {{ source('ecb', 'fx_rates') }}
),

renamed as (
    select
        cast(date as date)                          as rate_date,
        currency,
        cast(rate as numeric(18, 6))                as units_per_eur,       -- 1 EUR = 405.12 HUF
        _batch_id,
        _loaded_at
    from source
)

select * from renamed