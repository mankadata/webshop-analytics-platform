-- Staging: ad platform reports. Each raw row is one daily report holding a JSON array of
-- campaigns; it is unnested to one row per platform, day and campaign. Spend stays in the
-- account currency (EUR, USD or HUF - DQ07).
with source as (
    select * from {{ source('marketing', 'ad_reports') }}
),

unnested as (
    select
        source.payload ->> 'platform'                       as platform,
        cast(source.payload ->> 'report_date' as date)      as report_date,
        source.payload ->> 'account_currency'               as currency,
        campaign.value ->> 'campaign_id'                    as campaign_id,
        campaign.value ->> 'campaign_name'                  as campaign_name,
        cast(campaign.value ->> 'impressions' as integer)   as impressions,
        cast(campaign.value ->> 'clicks' as integer)        as clicks,
        cast(campaign.value ->> 'spend' as numeric(14, 2))  as spend_local,
        source._batch_id,
        source._loaded_at
    from source
    cross join lateral jsonb_array_elements(source.payload -> 'rows') as campaign
)

select * from unnested