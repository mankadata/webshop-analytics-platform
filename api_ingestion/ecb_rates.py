"""Load real euro reference rates from the ECB Data Portal API into the warehouse.

The rates land in raw_ecb.fx_rates_live with the same columns as the simulated
raw_ecb.fx_rates table, so the staging model could switch to them without changes.

Usage (from the repository root):
    python api_ingestion/ecb_rates.py                      # 2025-01-01 until today
    python api_ingestion/ecb_rates.py --start 2026-11-01   # a shorter period

-----
Note: the dbt models keep using the simulated rates (raw_ecb.fx_rates), because the
synthetic company priced its orders with them. See
dbt/webshop_analytics/analyses/exploration/ecb/ecb_api_comparison.sql 
"""

import argparse
import csv
import io
import os
from datetime import date, datetime, timezone

import psycopg2
import requests
from psycopg2.extras import execute_values

# Daily (D) reference rates of HUF and USD against EUR: spot (SP00), average (A)
API_URL = "https://data-api.ecb.europa.eu/service/data/EXR/D.{currencies}.EUR.SP00.A"
CURRENCIES = ["HUF", "USD"]

CREATE_TABLE = """
    create schema if not exists raw_ecb;
    create table if not exists raw_ecb.fx_rates_live (
        date          text,          -- raw layer: everything as text, typed in dbt
        currency      text,
        rate          text,          -- units of currency per 1 EUR
        _batch_id     text,
        _source_file  text,
        _loaded_at    timestamptz
    );
"""


def fetch_rates(start: date, end: date) -> tuple[list[dict], str]:
    """Download the rates as CSV and keep the three columns we need."""
    url = API_URL.format(currencies="+".join(CURRENCIES))
    params = {
        "startPeriod": start.isoformat(),
        "endPeriod": end.isoformat(),
        "format": "csvdata",
    }
    response = requests.get(url, params=params, timeout=60)
    response.raise_for_status()  # stop on HTTP errors (404, 500 ...)

    reader = csv.DictReader(io.StringIO(response.text))
    rows = [
        {
            "date": record["TIME_PERIOD"],   # e.g. 2026-11-16
            "currency": record["CURRENCY"],  # HUF or USD
            "rate": record["OBS_VALUE"],     # e.g. 364.35
        }
        for record in reader
        if record["OBS_VALUE"]               # skip days without a value
    ]
    return rows, response.url


def connect():
    """Connect with the same settings as dbt (environment variables or defaults)."""
    return psycopg2.connect(
        host=os.getenv("WAREHOUSE_HOST", "localhost"),
        port=int(os.getenv("WAREHOUSE_PORT", "5432")),
        user=os.getenv("WAREHOUSE_USER", "webshop"),
        password=os.getenv("WAREHOUSE_PASSWORD", "webshop"),
        dbname=os.getenv("WAREHOUSE_DB", "warehouse"),
    )


def load_rates(rows: list[dict], start: date, end: date, source_url: str) -> None:
    """Replace the rates of the period, so running the script twice gives no duplicates."""
    batch_id = f"api-{date.today().isoformat()}"
    loaded_at = datetime.now(timezone.utc)

    with connect() as conn, conn.cursor() as cur:
        cur.execute(CREATE_TABLE)
        cur.execute(
            "delete from raw_ecb.fx_rates_live where date between %s and %s",
            (start.isoformat(), end.isoformat()),
        )
        execute_values(
            cur,
            """insert into raw_ecb.fx_rates_live
               (date, currency, rate, _batch_id, _source_file, _loaded_at)
               values %s""",
            [
                (row["date"], row["currency"], row["rate"], batch_id, source_url, loaded_at)
                for row in rows
            ],
        )
    # leaving the "with connect()" block commits the transaction


def main() -> None:
    parser = argparse.ArgumentParser(description="Load ECB euro reference rates.")
    parser.add_argument("--start", type=date.fromisoformat, default=date(2025, 1, 1))
    parser.add_argument("--end", type=date.fromisoformat, default=date.today())
    args = parser.parse_args()

    rows, source_url = fetch_rates(args.start, args.end)
    load_rates(rows, args.start, args.end, source_url)

    days = len({row["date"] for row in rows})
    print(f"Loaded {len(rows)} rates for {days} business days "
          f"({args.start} - {args.end}) into raw_ecb.fx_rates_live")


if __name__ == "__main__":
    main()