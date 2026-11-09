import gzip
import json
import pickle
import re
from datetime import date, timedelta

from conftest import simulate
from webshop_pipeline.simulator import Simulator, demand_multiplier, write_batch
from webshop_pipeline.simulator.reference import SCHEMA_DRIFT_DATE


def rows(batch, source, entity):
    return batch.rows[(source, entity)]


def test_simulation_is_deterministic():
    _, a = simulate(date(2025, 1, 1), date(2025, 1, 10))
    _, b = simulate(date(2025, 1, 1), date(2025, 1, 10))
    assert a.rows == b.rows


def test_state_snapshot_round_trip_gives_identical_next_day():
    sim, _ = simulate(date(2025, 1, 1), date(2025, 2, 1))
    restored = Simulator(seed=7, state=pickle.loads(pickle.dumps(sim.state)))
    day = date(2025, 2, 2)
    assert sim.step(day).rows == restored.step(day).rows


def test_days_must_be_simulated_in_order():
    sim, _ = simulate(date(2025, 1, 1), date(2025, 1, 3))
    try:
        sim.step(date(2025, 1, 10))
    except ValueError:
        return
    raise AssertionError("skipping days must fail")


def test_all_six_sources_deliver(history):
    _, batch = history
    sources = {source for source, _ in batch.rows}
    assert sources == {"shop", "payments", "erp", "marketing", "web", "ecb"}


def test_orders_reference_known_customers(history):
    sim, batch = history
    assert {int(r["customer_id"]) for r in rows(batch, "shop", "orders")} <= set(sim.state.customers)


def test_ecb_rates_only_on_business_days(history):
    _, batch = history
    assert all(date.fromisoformat(r["date"]).weekday() < 5 for r in rows(batch, "ecb", "fx_rates"))


def test_web_tracking_starts_in_june_2025(history):
    _, batch = history
    first = min(r["event_timestamp"] for r in rows(batch, "web", "events"))
    assert first.startswith("2025-05-31T2") or first >= "2025-06-01"


# --------------------------------------------------------------------------- #
# Injected data-quality issues (see docs/data-quality.md)
# --------------------------------------------------------------------------- #


def test_dq01_placeholders_and_missing_status(history):
    _, batch = history
    assert {"N/A", "-", "nincs"} & {r["phone"] for r in rows(batch, "shop", "customers")}
    assert any(r["status"] == "" for r in rows(batch, "shop", "orders"))


def test_dq02_duplicates(history):
    _, batch = history
    item_ids = [r["order_item_id"] for r in rows(batch, "shop", "order_items")]
    event_ids = [r["id"] for r in rows(batch, "payments", "events")]
    assert len(item_ids) > len(set(item_ids))
    assert len(event_ids) > len(set(event_ids))


def test_dq03_fuzzy_duplicate_customers(history):
    _, batch = history
    normalised = [re.sub(r"\s", "", r["email"]).lower() for r in rows(batch, "shop", "customers")]
    ids_per_email = {}
    for r, email in zip(rows(batch, "shop", "customers"), normalised, strict=True):
        ids_per_email.setdefault(email, set()).add(r["customer_id"])
    assert any(len(ids) > 1 for ids in ids_per_email.values())


def test_dq04_dq05_formatting_and_invalid_values(history):
    _, batch = history
    customers = rows(batch, "shop", "customers")
    assert any(r["phone"].startswith("06") for r in customers)
    assert any(r["email"] != r["email"].strip() for r in customers)
    assert any(r["postal_code"].startswith("H-") for r in customers)


def test_dq06_dq08_erp_uses_hungarian_formats(history):
    _, batch = history
    invoice = rows(batch, "erp", "invoices")[0]
    assert re.fullmatch(r"\d{4}\.\d{2}\.\d{2}\.", invoice["kelt"])
    assert "," in invoice["brutto"] or invoice["penznem"] == "HUF"


def test_dq07_multiple_currencies(history):
    _, batch = history
    assert {r["currency"] for r in rows(batch, "shop", "orders")} == {"EUR", "HUF"}
    assert {r["account_currency"] for r in rows(batch, "marketing", "ad_reports")} >= {"EUR", "USD"}


def test_dq09_dq10_impossible_and_orphan_values(history):
    _, batch = history
    items = rows(batch, "shop", "order_items")
    assert any(r["quantity"] <= 0 or r["discount_pct"] > 100 for r in items)
    assert any(not e["livemode"] for e in rows(batch, "payments", "events"))


def test_dq11_country_aliases(history):
    _, batch = history
    assert {"Magyarország", "Hungary", "hu"} & {r["country"] for r in rows(batch, "shop", "customers")}


def test_dq15_schema_drift_after_cutover():
    sim, _ = simulate(SCHEMA_DRIFT_DATE - timedelta(days=2), SCHEMA_DRIFT_DATE - timedelta(days=1))
    before = sim.state.customers
    batch = sim.step(SCHEMA_DRIFT_DATE)
    after = rows(batch, "shop", "customers")
    assert before and after
    assert "phone_number" in after[0] and "phone" not in after[0] and "loyalty_tier" in after[0]


def test_black_friday_peak():
    assert demand_multiplier(date(2025, 11, 28)) > 2 * demand_multiplier(date(2025, 10, 15))


# --------------------------------------------------------------------------- #
# File formats
# --------------------------------------------------------------------------- #


def test_files_are_written_in_native_formats(tmp_path):
    _, batch = simulate(date(2025, 6, 1), date(2025, 6, 2))
    write_batch(batch, tmp_path, "2025-06-02")
    erp = (tmp_path / "erp" / "2025-06-02" / "keszletmozgas.csv").read_bytes()
    assert b";" in erp.splitlines()[0] and b"\r\n" in erp
    erp.decode("cp1250")  # must decode as Windows-1250
    with gzip.open(tmp_path / "web" / "2025-06-02" / "events.jsonl.gz", "rt") as fh:
        assert json.loads(fh.readline())["event_name"]
    reports = json.loads((tmp_path / "marketing" / "2025-06-02" / "ad_reports.json").read_text())
    assert reports[0]["rows"]
