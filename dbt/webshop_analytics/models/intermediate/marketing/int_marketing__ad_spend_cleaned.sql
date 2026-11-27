-- Intermediate (silver): one row per platform, campaign and day, spend in EUR.
-- Rules come from analyses/exploration/intermediate/marketing/stg_marketing__ad_campaigns.sql (Q1).
-- Spend arrives in the currency of each platform: Google EUR, Meta and TikTok USD,
-- newsletter HUF.

with campaigns as (
    select * from {{ ref('stg_marketing__ad_campaigns') }}
),

fx_rates as (
    select * from {{ ref('int_ecb__fx_rates_daily') }}
),

final as (
    select
        campaigns.report_date,
        campaigns.platform,

        -- marketing channel, the same names the web analytics UTM mapping will use
        case campaigns.platform
            when 'google_ads' then 'paid_search'
            when 'meta_ads'   then 'paid_social'
            when 'tiktok_ads' then 'paid_social'
            when 'newsletter' then 'email'
        end                                                         as channel,

        campaigns.campaign_id,
        campaigns.campaign_name,
        campaigns.impressions,
        campaigns.clicks,

        campaigns.currency,
        campaigns.spend_local,
        fx_rates.units_per_eur,
        round(campaigns.spend_local / fx_rates.units_per_eur, 2)    as spend_eur,

        -- click-through rate and cost per click
        round(campaigns.clicks::numeric / nullif(campaigns.impressions, 0), 4)
                                                                    as click_through_rate,
        round(campaigns.spend_local / fx_rates.units_per_eur
              / nullif(campaigns.clicks, 0), 4)                     as cost_per_click_eur
    from campaigns
    left join fx_rates
        on  fx_rates.currency  = campaigns.currency
        and fx_rates.rate_date = campaigns.report_date
)

select * from final