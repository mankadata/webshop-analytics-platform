"""Integration tests against a real Postgres. Enabled with RUN_DB_TESTS=1 (CI does this)."""

import os
from datetime import date

import pytest

from conftest import simulate

pytestmark = pytest.mark.skipif(os.getenv("RUN_DB_TESTS") != "1", reason="needs Postgres")


@pytest.fixture
def loader(monkeypatch):
    from webshop_pipeline import load

    monkeypatch.setattr(load, "raw_schema", lambda source: f"pytest_raw_{source}")
    yield load
    with load.connect() as conn, conn.cursor() as cur:
        for source in ("shop", "payments", "erp", "marketing", "web", "ecb"):
            cur.execute(f"drop schema if exists pytest_raw_{source} cascade")


def test_load_is_idempotent_and_handles_every_format(tmp_path, loader):
    from webshop_pipeline.simulator import write_batch

    _, batch = simulate(date(2025, 6, 1), date(2025, 6, 2))
    write_batch(batch, tmp_path, "b1")
    first = loader.load_batch(tmp_path, "b1")
    second = loader.load_batch(tmp_path, "b1")
    assert first == second
    assert {"shop.orders", "payments.events", "erp.invoices", "web.events", "marketing.ad_reports"} <= set(first)
    with loader.connect() as conn, conn.cursor() as cur:
        cur.execute("select count(*) from pytest_raw_shop.orders")
        assert cur.fetchone()[0] == first["shop.orders"]
        cur.execute("select count(*) from pytest_raw_erp.invoices where kelt ~ '^[0-9]{4}[.]'")
        assert cur.fetchone()[0] == first["erp.invoices"]  # cp1250 file decoded correctly


def test_schema_drift_adds_columns(tmp_path, loader):
    (tmp_path / "shop" / "d1").mkdir(parents=True)
    (tmp_path / "shop" / "d2").mkdir(parents=True)
    (tmp_path / "shop" / "d1" / "returns.csv").write_text("return_id,order_id\n1,10\n")
    (tmp_path / "shop" / "d2" / "returns.csv").write_text("return_id,order_id,reason_code\n2,11,DAMAGED\n")
    loader.load_batch(tmp_path, "d1")
    loader.load_batch(tmp_path, "d2")
    with loader.connect() as conn, conn.cursor() as cur:
        cur.execute("select return_id, reason_code from pytest_raw_shop.returns order by 1")
        assert cur.fetchall() == [("1", None), ("2", "DAMAGED")]
