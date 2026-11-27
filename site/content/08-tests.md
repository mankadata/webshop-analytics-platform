# Step 8 - Data quality tests

## Goal

Turn the manual checks of steps 5 and 7 into rules that dbt runs every time.
A test is a query that returns the **bad rows** - an empty result means the test passed.

## Result

```text
dbt test --select intermediate marts test_type:singular
Done. PASS=82 WARN=3 ERROR=0 TOTAL=85
```

The three warnings are known issues, kept visible on purpose: 35 order lines for unknown
products, 4 products with negative stock today, and no order in the last 7 days (the daily
load is not scheduled yet - Airflow comes in step 11).

## Data tests (built in, YAML)

| Test | Rule | Example |
|---|---|---|
| `unique`, `not_null` | every key exactly once | `order_id` in `fct_orders` |
| `accepted_values` | only known codes | `order_status`, `segment`, `buyer_type` |
| `relationships` | the referenced row exists | every order points to a customer, a date and a channel |
| grain test | a combination is unique | month + country + channel in `fct_monthly_revenue` |

## Custom tests (business rules)

| Test | Business rule |
|---|---|
| `assert_vat_rate_matches_country` | each country's VAT rate - Romania 19 % until 2025-07-31, 21 % after |
| `assert_order_lines_add_up_to_orders` | revenue allocated to lines equals the invoiced order |
| `assert_reconciliation_matched_share` | at least 95 % of paid orders reconcile across three systems |
| `assert_gross_margin_in_range` | monthly margin between 10 and 40 % - would have caught the cost bug |
| `assert_delivery_after_order` | nothing is shipped before it is ordered or delivered before it is shipped |
| `assert_recent_orders` | at least one order in the last 7 days (volume anomaly) |
| `non_negative` (generic) | costs, spend and line revenue are never negative |

> **Why test data and not only code?** The code can be right and the data still wrong: a source
> changes a format, a load stops, a supplier sends a new country spelling. Tests catch it before
> a business user does.

> **Error or warning?** An unknown problem stops the pipeline (`error`). A known, flagged problem
> is reported but does not block (`warn`) - otherwise people learn to ignore red builds.
