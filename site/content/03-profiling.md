# Step 3 - Data profiling

## Goal

Look at the raw data before modelling it. Profiling answers three questions for every
source: how much data is there, what does it really look like, and what is wrong with it.
The answers decide what the staging layer does and what is left for the intermediate layer.

## Method

Plain SQL queries against the `raw_*` schemas, saved in
`dbt/webshop_analytics/analyses/profiling/` and run with `psql`:

| File | Looks at |
|---|---|
| `01_overview.sql` | rows, daily batches and date range of all 14 raw tables |
| `02_shop.sql` | customers, products, orders, order lines, schema drift |
| `03_payments.sql` | webhook structure, event types, retries, test transactions |
| `04_erp.sql` | Hungarian numbers and dates, VAT arithmetic, stock movements |
| `05_marketing_web_ecb.sql` | ad report gaps and delays, web event duplicates, UTM spellings, ECB calendar |

A few techniques do most of the work:

```sql
-- Completeness: count empty values and placeholders per column
count(*) filter (where lower(phone) in ('n/a', '-', 'nincs', '0'))

-- Formats: replace every digit with 9, so only the shape remains
regexp_replace(phone, '[0-9]', '9', 'g')    -- '+36 30 123 4567' -> '+99 99 999 9999'

-- Uniqueness: rows minus distinct keys = duplicates
count(*) - count(distinct order_item_id)

-- Nested JSON: read values straight from the jsonb column
payload #>> '{data,object,order_reference}'
```

## What the data looks like

About 930,000 raw rows, delivered in one batch per day since 2025-01-01. Web analytics
starts on 2025-06-01 and dominates the volume (~750k events); the shop has ~17,600 orders
behind ~68,700 status events - about four events per order.

## Findings

Numbers are from the profiling run; rates matter more than exact counts.

### Shop database

| Finding | Evidence | Issue |
|---|---|---|
| A customer appears in several rows | 7,138 rows for 5,169 customers (1.38 versions each) | grain |
| Phone numbers in 15+ shapes | `+36 30 123 4567`, `36-30/123-4567`, `0036...`, `06...` | DQ04 |
| Phone placeholders | 472 rows with `N/A`, `-`, `nincs` or `0` | DQ01 |
| Birth date missing or `N/A` | 685 empty, 379 `N/A` | DQ01 |
| E-mail casing and spaces | 386 with upper case, 226 with spaces | DQ04 |
| Invalid e-mail syntax | 67 rows, e.g. `anna@gmail` | DQ05 |
| Same person, several accounts | e-mails that differ only in casing / spaces map to 2-3 customer ids | DQ03 |
| Countries in 35 spellings | `HU`, `hu`, `HUN`, `Hungary`, `Magyarország` | DQ11 |
| Postal codes with country prefix | 58 rows like `H-1051` | DQ05 |
| Categories in 21 spellings | `Electronics`, ` ELECTRONICS`, `Elektronika` | DQ11 |
| Weights in mixed units | `350 g`, `350g`, `0,35 kg`, `n/a` | DQ07 |
| Order events without status | 258 empty statuses | DQ01 |
| Two currencies | 7,082 HUF and 10,551 EUR orders | DQ07 |
| Duplicate order lines | 158 rows | DQ02 |
| Impossible order lines | 40 with quantity <= 0, 17 with discount > 100 % | DQ09 |
| Lines for unknown products | 35 rows | DQ10 |
| Phone column renamed | `phone` until 2026-02-28, `phone_number` from 2026-03-01 | DQ15 |

### Payment provider

| Finding | Evidence | Issue |
|---|---|---|
| Everything is in one JSON document | order reference at `data.object.order_reference` | structure |
| Epoch timestamps, amounts in minor units | `created: 1735755676`, `amount: 5285` = 52.85 | DQ06, DQ07 |
| Webhook retries | 270 events delivered twice | DQ02 |
| Test transactions | 106 events with `livemode: false` and references like `WS-TEST-8244` | DQ10 |

### ERP

| Finding | Evidence | Issue |
|---|---|---|
| Hungarian dates and numbers | `2025.01.01.`, `298 818`, `42,97` | DQ06, DQ08 |
| VAT rate in four spellings | `27%`, `27`, `27,00` | DQ08 |
| Gross is not net + VAT | 82 invoices | DQ14 |
| Sales booked with the wrong sign | 66 sale movements with negative quantity | DQ09 |
| SKU casing and spaces | 320 movements like ` wsp-ele-00012` | DQ04 |

Stock-count corrections (`LELT`) are negative on purpose - shrinkage, not an error.

### Ad platforms, web analytics, ECB

| Finding | Evidence | Issue |
|---|---|---|
| Spend in EUR, USD and HUF | Google in EUR, Meta and TikTok in USD, newsletter in HUF | DQ07 |
| Reports arriving a day late | 14 Meta reports; no day is missing once they arrive | DQ13 |
| Duplicate web events | 2,993 events | DQ02 |
| Late web events | 22,569 events loaded the day after they happened | DQ12 |
| UTM spellings | 17 source / medium pairs for 6 channels: `google / CPC`, `adwords / cpc`, `fb`, `meta / paidsocial` | DQ11 |
| No rates at weekends | ECB publishes Monday to Friday only | timeliness |

## What will be fixed where

Profiling shows two kinds of work. Mechanical fixes that never lose information belong in
**staging**; anything that needs a decision, a reference list or another table belongs in
**intermediate**.

| Staging (rename, cast, flatten - nothing dropped) | Intermediate (clean, decide, conform) |
|---|---|
| English column names for the Hungarian ERP export | parse Hungarian numbers and dates |
| text to integer, numeric, timestamp, boolean | convert shop local time to UTC |
| empty string to `null` | turn placeholders (`N/A`, `nincs`) into `null` |
| one column from `phone` and `phone_number` | phone numbers to E.164, e-mails to lower case |
| JSON documents flattened into columns | map countries, categories and UTM pairs to codes |
| epoch timestamps to `timestamptz` | deduplicate order lines, webhooks and web events |
| messy values kept, marked with a `_raw` suffix | quarantine impossible lines and test payments |
| | merge duplicate customer accounts |
| | convert all amounts to EUR with daily ECB rates |
| | reconcile shop, payments and invoices |

## How to run it

```bash
docker compose exec -T postgres psql -U webshop -d warehouse \
  < dbt/webshop_analytics/analyses/profiling/02_shop.sql
```
