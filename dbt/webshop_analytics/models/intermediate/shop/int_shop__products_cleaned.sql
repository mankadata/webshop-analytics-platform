-- Intermediate (silver): one row per product, latest version, cleaned.
-- Rules come from analyses/exploration/shop/stg_shop__products.sql (Q1-Q4).
-- The price history (one row per version) stays in staging for marts / snapshots.

with products as (
    select * from {{ ref('stg_shop__products') }}
),

categories as (
    select * from {{ ref('product_categories') }}
),

-- Q3: parse the weight of every version into grams
parsed as (
    select
        *,
        -- '1,45 kg' -> '1,45kg', '1451 g' -> '1451g', 'N/A' -> 'n/a'
        lower(regexp_replace(trim(weight_raw), '\s', '', 'g'))      as weight_compact
    from products
),

weights as (
    select
        product_id,
        weight_compact,
        updated_at_local,
        case
            when weight_compact ~ '^[0-9]+g$'
                then cast(regexp_replace(weight_compact, 'g$', '') as numeric)
        end                                                         as weight_from_g,
        case
            when weight_compact ~ '^[0-9]+(,[0-9]+)?kg$'
                then cast(replace(regexp_replace(weight_compact, 'kg$', ''), ',', '.') as numeric) * 1000
        end                                                         as weight_from_kg
    from parsed
),

-- one weight per product: the latest exact gram value, otherwise the latest kg value
best_weight as (
    select
        product_id,
        (array_agg(weight_from_g  order by updated_at_local desc)
            filter (where weight_from_g is not null))[1]            as latest_gram_weight,
        (array_agg(weight_from_kg order by updated_at_local desc)
            filter (where weight_from_kg is not null))[1]           as latest_kg_weight
    from weights
    group by product_id
),

-- Q1: one row per product = the latest version
latest as (
    select
        *,
        count(*) over (partition by product_id)                     as version_count,
        min(updated_at_local) over (partition by product_id)        as first_seen_at_local,
        row_number() over (
            partition by product_id
            order by updated_at_local desc, _loaded_at desc
        )                                                           as version_rank
    from products
),

final as (
    select
        latest.product_id,
        upper(trim(latest.sku))                                     as sku,
        trim(latest.product_name)                                   as product_name,

        -- Q2b: the SKU prefix is the reliable category source (WSP-ELE-00137 -> ELE)
        split_part(upper(trim(latest.sku)), '-', 2)                 as category_code,
        categories.category_name,

        trim(latest.brand)                                          as brand,
        latest.list_price_eur,
        round(coalesce(best_weight.latest_gram_weight,
                       best_weight.latest_kg_weight))               as weight_g,
        latest.warehouse_code,
        latest.supplier_code,
        latest.is_active,

        -- shop times are Budapest local time -> UTC (timestamptz)
        latest.first_seen_at_local at time zone 'Europe/Budapest'   as first_seen_at,
        latest.updated_at_local    at time zone 'Europe/Budapest'   as updated_at,
        latest.version_count,

        nullif(concat_ws(', ',
            case when categories.category_code is null then 'unknown_category' end,
            case when coalesce(best_weight.latest_gram_weight,
                               best_weight.latest_kg_weight) is null then 'missing_weight' end
        ), '')                                                      as dq_issue,

        latest._batch_id,
        latest._loaded_at
    from latest
    left join categories
        on split_part(upper(trim(latest.sku)), '-', 2) = categories.category_code
    left join best_weight
        on latest.product_id = best_weight.product_id
    where latest.version_rank = 1
)

select * from final