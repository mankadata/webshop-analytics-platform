# Step 2 - Data sources

## Goal

Raw data from every department in the warehouse, and a clear picture of what each source
delivers - formats, grain and known defects - before any model is designed.

## Synthetic, but realistic

There is no real company behind this project, so the data is **synthetic**. A deterministic
Python simulator (developed with AI assistance) runs the business day by day since
2025-01-01: customers sign up, orders move from paid to shipped to delivered, stock is
replenished, ads are bought, prices change. Each system exports its daily changes in its own
format and with its own quality problems - which is exactly what makes the downstream
modelling interesting.

Because the simulator is seeded, every run produces the same history, and the correct
answers are known - so tests can prove that the cleaning really works.

## Six systems, five departments

| System | Department | Format | What it delivers |
|---|---|---|---|
| Shop database | Sales | CSV, local time without offset | customers, products, orders (one row per status change), order lines, returns |
| Payment provider | Finance | nested JSON webhooks, epoch timestamps, amounts in cents | charges, failed payments, refunds |
| ERP | Finance, Logistics | semicolon CSV in Windows-1250, Hungarian headers and numbers (`1 299,90`) | suppliers, purchase orders, stock movements, invoices and credit notes |
| Ad platforms | Marketing | JSON with nested campaign rows, EUR and USD | daily spend, clicks and impressions per campaign |
| Web analytics | Marketing | gzipped JSON lines, ISO-8601 UTC | page views, product views, cart, checkout, purchase |
| ECB | Finance | CSV, business days only | EUR exchange rates for HUF and USD |

## How the raw layer looks

The ingestion job loads every daily file into a `raw_<source>` schema:

```text
raw_shop        customers, products, orders, order_items, returns
raw_payments    events
raw_erp         suppliers, purchase_orders, purchase_order_lines, stock_movements, invoices
raw_marketing   ad_reports
raw_web         events
raw_ecb         fx_rates
```

- **Every CSV column is stored as text** and every JSON record as one `jsonb` value. Typing
  and parsing happen in dbt, where they are versioned and tested - a bad value upstream
  never breaks the load.
- **Lineage columns on every row:** `_batch_id` (which daily export), `_source_file`,
  `_loaded_at`.
- **Idempotent loads:** re-loading a day replaces that day's rows instead of duplicating them.
- **Schema drift is handled:** when the shop export renamed `phone` to `phone_number` in
  March 2026, the loader added the new column instead of failing.

## Known data-quality issues

The sources contain these defects on purpose, at realistic rates. The intermediate layer
has to detect and handle each of them; the categories follow the DAMA-DMBOK data quality
dimensions.

| Code | Issue | Dimension | Example |
|---|---|---|---|
| DQ01 | Missing or placeholder values | Completeness | phone `N/A`, `-`, `nincs`; order event without status |
| DQ02 | Exact duplicates | Uniqueness | order line delivered twice, webhook retried |
| DQ03 | Fuzzy duplicates | Uniqueness | same person registered twice as `ANNA.KISS@Gmail.com ` |
| DQ04 | Inconsistent formatting | Consistency | six phone formats, e-mail casing, `KISS anna` |
| DQ05 | Invalid formats | Validity | `anna@gmail`, postal code `H-1051` |
| DQ06 | Mixed date formats and time zones | Consistency | local time, epoch seconds, UTC, `2026.11.05.` |
| DQ07 | Mixed currencies and units | Consistency | HUF / EUR / USD, cents, `350 g` vs `0,35 kg` |
| DQ08 | Locale-specific numbers | Validity | `1 299,90`, VAT as `27%`, `27`, `27,00` |
| DQ09 | Impossible values | Validity | quantity 0 or negative, 120 % discount |
| DQ10 | Orphan records | Integrity | order line for an unknown product, sandbox payments |
| DQ11 | Non-standard codes | Validity | `Magyarország`, `Hungary`, `hu`; 15+ category spellings |
| DQ12 | Late-arriving data | Timeliness | web events delivered a day late |
| DQ13 | Missing or delayed loads | Timeliness | an ad report missing for a day |
| DQ14 | Cross-system inconsistencies | Consistency | paid amount differs from order total; stock below zero |
| DQ15 | Schema drift | Consistency | `phone` renamed to `phone_number` |
| DQ16 | Personal data (GDPR) | Privacy | names, e-mails, phones, birth dates |

## How I verified it

```bash
python -m webshop_pipeline bootstrap      # simulate and load 2025-01-01 .. yesterday
docker compose exec postgres psql -U webshop -d warehouse -c "\dn"   # six raw_* schemas
docker compose exec postgres psql -U webshop -d warehouse \
  -c "select * from raw_shop.orders limit 3;"                       # text columns + lineage
```
## Declaring the sources in dbt

dbt does not build the raw tables, so it has to be told about them. All six systems are
declared in `models/staging/_sources.yml`:

```yaml
sources:
  - name: shop
    schema: raw_shop
    loaded_at_field: _loaded_at
    config:
      freshness:
        warn_after: {count: 26, period: hour}
        error_after: {count: 50, period: hour}
    tables:
      - name: customers
      - name: orders
      # ...
```

- Models read raw data only through `{{ source('shop', 'orders') }}`, never through a
  hard-coded table name. If a schema or table is renamed, only this file changes, and dbt
  draws the lineage from raw table to report.
- **Freshness checks** use the `_loaded_at` lineage column. Data arrives once a day, so a
  warning after 26 hours and an error after 50 hours; the ECB source allows a weekend gap.

```bash
dbt ls --resource-type source     # 14 raw tables are visible to dbt
dbt source freshness              # PASS for all 14
```

## Next

Staging models: one view per raw table that renames, casts and flattens - nothing dropped.