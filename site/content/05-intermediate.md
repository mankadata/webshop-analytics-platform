# Step 5 - Intermediate

## Goal

Staging made the data readable; intermediate makes it **trustworthy**. Every source was explored
with SQL first, then cleaned by a model built from what the data really showed.

## How

1. **Explore** the staging model and write down the finding next to the query.
2. **Decide** a rule for every dirty column.
3. **Build** the model, then **check** it against the exploration numbers.

Bad values are never dropped silently: they become `null`, the row gets `is_valid = false`
and a `dq_issue` column says why. All queries and findings are in the
[exploration files on GitHub](https://github.com/mankadata/webshop-analytics-platform/tree/main/dbt/webshop_analytics/analyses/exploration).

## What was built

| Source | Models | Highlights |
|---|---|---|
| Shop | customers, customer identity, orders, order items, products, returns | 5,197 accounts = 5,106 people; order event log -> one row per order |
| ECB | daily FX rates | a rate for every calendar day (weekends carried forward) |
| Payments | events | 272 webhook retries removed, 103 test payments flagged |
| ERP | invoices, stock movements, purchase orders | Hungarian numbers and dates parsed; supplier lead time 7.8 days |
| Finance | order reconciliation | shop vs payments vs ERP for every order |
| Marketing | ad spend | EUR, USD and HUF spend in EUR |
| Web | events, sessions | 3,015 duplicate events removed; 12 UTM spellings -> 5 channels |

17 models and 3 seeds (country codes, product categories, UTM channels).

## Five findings worth telling

### 1. Three systems, one answer

Every order was compared across the shop, the payment provider and the ERP:

| Status | Orders | Share |
|---|---:|---:|
| matched | 17,202 | 97.0 % |
| not paid (cancelled or in progress) | 438 | 2.5 % |
| distorted by an invalid order line | 56 | 0.3 % |
| underpaid | 36 | 0.2 % |
| unexplained | 9 | 0.05 % |

5.5 million EUR reconciles to 1.82 EUR of rounding. **468 EUR is missing** on 36 orders:
19 paid exactly 50 less than invoiced, 17 exactly 1 EUR less.

### 2. Not every oddity is an error

Romanian invoices carry two VAT rates. The data shows 19 % until 2025-07-31 and 21 % from
2025-08-01 - the real Romanian VAT increase, not a defect. It is documented and will be
guarded by a test instead of being "fixed".

### 3. Correcting my own profiling

Profiling reported 82 invoices where gross was not net plus VAT. A closer look showed every
difference is at most 2 cents or 1.56 Ft - VAT rounded per line. With a rounding tolerance
there is no material VAT error, and the profiling page was corrected.

### 4. A better source than the dirty column

Product categories came in 21 spellings (`Electronics`, `ELECTRONICS`, `Elektronika` ...).
Instead of mapping every spelling, the category was taken from the SKU (`WSP-ELE-00137`),
which matched the category of all 235 products - and keeps working when a new spelling appears.

### 5. One table repairs another

- Two orders ended with an empty status; the returns table showed the lost status was `returned`.
- Four products end with negative stock. The 66 sales with a wrong sign were checked first -
  they were not the cause: the products were sold before a goods receipt was recorded.

## Next

Marts: dimensions and facts for finance, marketing, operations and CRM - built on these models.