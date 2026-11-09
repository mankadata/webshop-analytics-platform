"""Export gold-layer metrics (and dbt run metadata) as JSON for the static site."""

from __future__ import annotations

import json
import logging
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path

from .config import DBT_TARGET_DIR
from .load import connect

log = logging.getLogger(__name__)

QUERIES: dict[str, str] = {
    "kpis": """
        with b as (select max(date_day) as d from gold.rpt_daily_kpis),
        w as (
            select
                case when date_day > b.d - 30 then 'cur' else 'prev' end as period,
                sum(net_revenue_eur) as revenue, sum(orders) as orders, sum(new_customers) as new_customers,
                sum(gross_margin_eur) as margin, sum(sessions) as sessions
            from gold.rpt_daily_kpis, b
            where date_day > b.d - 60
            group by 1
        )
        select
            (select d from b) as data_through,
            max(revenue) filter (where period = 'cur') as revenue_30d,
            max(revenue) filter (where period = 'prev') as revenue_prev_30d,
            max(orders) filter (where period = 'cur') as orders_30d,
            max(orders) filter (where period = 'prev') as orders_prev_30d,
            max(new_customers) filter (where period = 'cur') as new_customers_30d,
            max(new_customers) filter (where period = 'prev') as new_customers_prev_30d,
            round(max(margin / nullif(revenue, 0)) filter (where period = 'cur'), 4) as margin_pct_30d,
            round(max(margin / nullif(revenue, 0)) filter (where period = 'prev'), 4) as margin_pct_prev_30d,
            round(max(orders / nullif(sessions, 0)) filter (where period = 'cur'), 4) as conversion_30d,
            round(max(orders / nullif(sessions, 0)) filter (where period = 'prev'), 4) as conversion_prev_30d
        from w
    """,
    "daily": """
        select date_day, net_revenue_eur, net_revenue_7d_avg_eur, orders
        from gold.rpt_daily_kpis
        where date_day > (select max(date_day) from gold.rpt_daily_kpis) - 180
        order by date_day
    """,
    "pnl": """
        select month, orders, net_revenue_eur, cogs_eur, gross_margin_eur, gross_margin_pct,
               marketing_spend_eur, contribution_margin_eur
        from gold.mart_finance_pnl_monthly order by month
    """,
    "marketing": """
        select channel, sum(spend_eur) as spend_eur, sum(sessions) as sessions, sum(orders) as orders,
               sum(new_customers) as new_customers, sum(revenue_eur) as revenue_eur,
               round(sum(spend_eur) / nullif(sum(new_customers), 0), 2) as cac_eur,
               round(sum(revenue_eur) / nullif(sum(spend_eur), 0), 2) as roas
        from gold.mart_marketing_performance_monthly
        where month > (select max(month) from gold.mart_marketing_performance_monthly) - interval '12 months'
        group by channel order by revenue_eur desc
    """,
    "funnel": """
        select sum(sessions) as sessions, sum(sessions_with_view_item) as view_item,
               sum(sessions_with_add_to_cart) as add_to_cart, sum(sessions_with_checkout) as checkout,
               sum(sessions_with_purchase) as purchase
        from gold.mart_funnel_daily
        where session_date > (select max(session_date) from gold.mart_funnel_daily) - 30
    """,
    "inventory_status": """
        select stock_status, count(*) as products, sum(inventory_value_eur) as value_eur
        from gold.mart_inventory_health where is_active group by 1 order by 2 desc
    """,
    "inventory_watchlist": """
        select sku, product_name, on_hand, days_of_cover, stockout_days_90d, stock_status
        from gold.mart_inventory_health
        where is_active and stock_status in ('negative_stock', 'stockout', 'low')
        order by days_of_cover nulls first limit 8
    """,
    "reconciliation": """
        select reconciliation_status, count(*) as orders
        from gold.mart_payment_reconciliation group by 1 order by 2 desc
    """,
    "dq_summary": """
        select issue_code, issue_name, dama_dimension, iso_25012_characteristic, handling,
               affected_rows_total, affected_rows_30d, actions_taken
        from gold.rpt_dq_issue_summary order by issue_code
    """,
    "dq_daily": """
        select batch_date, issue_code, sum(affected_rows) as affected_rows
        from gold.rpt_dq_scorecard
        where batch_date > (select max(batch_date) from gold.rpt_dq_scorecard) - 30
        group by 1, 2 order by 1, 2
    """,
    "quarantine": """
        select 'shop.order_items' as source_table, reason_code, count(*) as rows
        from quarantine.qtn_order_items group by 2
        union all
        select 'payments.events', reason_code, count(*) from quarantine.qtn_payment_events group by 2
        union all
        select 'shop.orders', reason_code, count(*) from quarantine.qtn_order_events group by 2
    """,
    "cohorts": """
        select cohort_month, months_since_first_order, cohort_customers, retention_rate
        from gold.rpt_customer_cohorts
        where cohort_month >= (select max(cohort_month) from gold.rpt_customer_cohorts) - interval '11 months'
          and months_since_first_order <= 11
        order by 1, 2
    """,
    "layers": """
        select 'raw' as layer, 'shop.orders' as model, count(*) as row_count from raw_shop.orders
        union all select 'bronze', 'stg_shop__orders', count(*) from bronze.stg_shop__orders
        union all select 'silver', 'int_orders', count(*) from silver.int_orders
        union all select 'gold', 'fct_orders', count(*) from gold.fct_orders
        union all select 'raw', 'web.events', count(*) from raw_web.events
        union all select 'silver', 'int_web_sessions', count(*) from silver.int_web_sessions
        union all select 'gold', 'fct_web_sessions', count(*) from gold.fct_web_sessions
        union all select 'raw', 'erp.stock_movements', count(*) from raw_erp.stock_movements
        union all select 'gold', 'fct_inventory_daily', count(*) from gold.fct_inventory_daily
    """,
}


def _jsonable(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def _query(cur, sql: str) -> list[dict]:
    cur.execute(sql)
    cols = [c.name for c in cur.description]
    return [{c: _jsonable(v) for c, v in zip(cols, row, strict=True)} for row in cur.fetchall()]


def _dbt_metadata() -> dict:
    meta: dict = {}
    manifest_path = DBT_TARGET_DIR / "manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        nodes = manifest["nodes"].values()
        meta["dbt_version"] = manifest["metadata"].get("dbt_version")
        meta["counts"] = {
            rtype: sum(1 for n in nodes if n["resource_type"] == rtype)
            for rtype in ("model", "test", "seed", "snapshot")
        }
        meta["counts"]["unit_test"] = len(manifest.get("unit_tests", {}))
        meta["counts"]["source"] = len(manifest.get("sources", {}))
    results_path = DBT_TARGET_DIR / "run_results.json"
    if results_path.exists():
        results = json.loads(results_path.read_text())
        statuses: dict[str, int] = {}
        for r in results["results"]:
            statuses[r["status"]] = statuses.get(r["status"], 0) + 1
        meta["last_run"] = {
            "generated_at": results["metadata"]["generated_at"],
            "command": results.get("args", {}).get("which"),
            "elapsed_seconds": round(results.get("elapsed_time", 0), 1),
            "statuses": statuses,
        }
    return meta


def export_site_data(out_dir: Path | str) -> Path:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    payload: dict = {"generated_at": datetime.now(UTC).isoformat(timespec="seconds")}
    with connect() as conn, conn.cursor() as cur:
        for name, sql in QUERIES.items():
            payload[name] = _query(cur, sql)
    payload["kpis"] = payload["kpis"][0]
    payload["funnel"] = payload["funnel"][0]
    payload["dbt"] = _dbt_metadata()
    target = out / "metrics.json"
    target.write_text(json.dumps(payload, indent=1, ensure_ascii=False))
    log.info("Wrote %s (%d bytes)", target, target.stat().st_size)
    return target
