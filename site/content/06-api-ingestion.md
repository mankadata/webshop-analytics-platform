# Step 6 - Own Python ingestion from the ECB API

## Goal

Replace a simulated source with a real one, written by hand: euro reference rates from the
public [ECB Data Portal API](https://data.ecb.europa.eu/help/api/data), loaded into the raw layer
with the same columns as the simulated table.

## How it works

`api_ingestion/ecb_rates.py` - about 100 lines of Python (`requests`, `psycopg2`):

```python
API_URL = "https://data-api.ecb.europa.eu/service/data/EXR/D.{currencies}.EUR.SP00.A"

response = requests.get(url, params={"startPeriod": ..., "format": "csvdata"}, timeout=60)
response.raise_for_status()                      # stop on HTTP errors
rows = [{"date": r["TIME_PERIOD"], "currency": r["CURRENCY"], "rate": r["OBS_VALUE"]}
        for r in csv.DictReader(io.StringIO(response.text)) if r["OBS_VALUE"]]
```

- **Raw-layer rules:** every value is stored as text, plus lineage columns
  (`_batch_id`, `_source_file`, `_loaded_at`).
- **Idempotent:** the period is deleted and reloaded in one transaction - running it twice
  still gives 974 rates for 487 business days, never duplicates.
- **No secrets in code:** the connection uses the same environment variables as dbt.

> **Why idempotent?** A scheduler retries failed jobs and people re-run loads by hand.
> A load that can run any number of times with the same result is safe to automate.

## Real vs simulated rates

| Month | Simulated HUF / EUR | Real ECB | Difference |
|---|---:|---:|---:|
| 2025-01 | 401.90 | 411.73 | -2.4 % |
| 2025-06 | 383.42 | 402.08 | -4.6 % |
| 2025-09 | 364.39 | 391.63 | -7.0 % |
| 2025-12 | 369.43 | 384.97 | -4.0 % |

The simulator follows the real trend but runs 2-7 % lower. **Decision:** the models keep the
simulated rates, because the synthetic company priced its HUF orders with them - switching
would shift every HUF amount and create false differences in the finance reconciliation.
The real loader stays in the project: swapping a source in the raw layer needs no change in
staging or intermediate.
