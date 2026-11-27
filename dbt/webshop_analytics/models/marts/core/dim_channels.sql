-- Mart (gold): marketing channel dimension, one row per channel.
-- Built from the utm_channels seed plus the two channels without UTM tags.

with seed_channels as (
    select
        channel,
        string_agg(distinct platform, ', ' order by platform)       as ad_platforms,
        string_agg(distinct utm_source, ', ' order by utm_source)   as utm_sources
    from {{ ref('utm_channels') }}
    group by channel
),

all_channels as (
    select channel, ad_platforms, utm_sources from seed_channels
    union all
    select 'direct',      null, null    -- visit without UTM tags
    union all
    select 'not_tracked', null, null    -- order without a web session (app, phone)
)

select
    channel,
    case channel
        when 'paid_search'    then 'Paid search'
        when 'paid_social'    then 'Paid social'
        when 'email'          then 'E-mail / newsletter'
        when 'organic_search' then 'Organic search'
        when 'direct'         then 'Direct'
        when 'not_tracked'    then 'Not tracked (app, phone)'
    end                                                             as channel_name,
    -- paid = bought media, owned = own audience, earned = found us for free
    case
        when channel in ('paid_search', 'paid_social') then 'paid'
        when channel = 'email'                         then 'owned'
        when channel in ('organic_search', 'direct')   then 'earned'
        else                                                'unknown'
    end                                                             as channel_group,
    ad_platforms is not null                                        as has_ad_spend,
    ad_platforms,
    utm_sources
from all_channels