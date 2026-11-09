"""Write simulated batches in each source system's native file format, and
persist simulator state between daily runs."""

from __future__ import annotations

import csv
import gzip
import json
import logging
import pickle
from datetime import date
from pathlib import Path

from .engine import Batch, SimState

log = logging.getLogger(__name__)

# (source, entity) -> file name and format.  This is the "contract" with the loader.
FILE_FORMATS: dict[tuple[str, str], dict] = {
    ("shop", "customers"): {"file": "customers.csv", "kind": "csv"},
    ("shop", "products"): {"file": "products.csv", "kind": "csv"},
    ("shop", "orders"): {"file": "orders.csv", "kind": "csv"},
    ("shop", "order_items"): {"file": "order_items.csv", "kind": "csv"},
    ("shop", "returns"): {"file": "returns.csv", "kind": "csv"},
    ("payments", "events"): {"file": "webhook_events.jsonl", "kind": "jsonl"},
    ("erp", "suppliers"): {"file": "szallitok.csv", "kind": "csv", "delimiter": ";", "encoding": "cp1250"},
    ("erp", "purchase_orders"): {"file": "beszerzes_fej.csv", "kind": "csv", "delimiter": ";", "encoding": "cp1250"},
    ("erp", "purchase_order_lines"): {
        "file": "beszerzes_tetel.csv",
        "kind": "csv",
        "delimiter": ";",
        "encoding": "cp1250",
    },
    ("erp", "stock_movements"): {"file": "keszletmozgas.csv", "kind": "csv", "delimiter": ";", "encoding": "cp1250"},
    ("erp", "invoices"): {"file": "szamlak.csv", "kind": "csv", "delimiter": ";", "encoding": "cp1250"},
    ("marketing", "ad_reports"): {"file": "ad_reports.json", "kind": "json_array"},
    ("web", "events"): {"file": "events.jsonl.gz", "kind": "jsonl_gz"},
    ("ecb", "fx_rates"): {"file": "eurofxref.csv", "kind": "csv"},
}


def write_batch(batch: Batch, landing_dir: Path, batch_id: str) -> list[Path]:
    """Write landing/<source>/<batch_id>/<file> for every entity with rows."""
    written = []
    for (source, entity), rows in sorted(batch.rows.items()):
        if not rows:
            continue
        spec = FILE_FORMATS[(source, entity)]
        folder = landing_dir / source / batch_id
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / spec["file"]
        kind = spec["kind"]
        if kind == "csv":
            columns: list[str] = []
            for row in rows:  # union of keys keeps schema drift visible in the file
                columns.extend(k for k in row if k not in columns)
            with open(path, "w", newline="", encoding=spec.get("encoding", "utf-8"), errors="replace") as fh:
                writer = csv.DictWriter(
                    fh,
                    fieldnames=columns,
                    delimiter=spec.get("delimiter", ","),
                    lineterminator="\r\n" if spec.get("encoding") == "cp1250" else "\n",
                )
                writer.writeheader()
                writer.writerows({k: ("" if v is None else v) for k, v in row.items()} for row in rows)
        elif kind == "jsonl":
            with open(path, "w", encoding="utf-8") as fh:
                fh.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
        elif kind == "jsonl_gz":
            with gzip.open(path, "wt", encoding="utf-8") as fh:
                fh.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
        elif kind == "json_array":
            path.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
        written.append(path)
    return written


# --------------------------------------------------------------------------- #
# State snapshots: data/state/state_<date>.pkl.gz
# --------------------------------------------------------------------------- #


def save_state(state: SimState, state_dir: Path, keep: int = 7) -> Path:
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / f"state_{state.last_day.isoformat()}.pkl.gz"
    with gzip.open(path, "wb") as fh:
        pickle.dump(state, fh)
    for old in sorted(state_dir.glob("state_*.pkl.gz"))[:-keep]:
        old.unlink()
    return path


def load_state(state_dir: Path, as_of: date) -> SimState | None:
    path = state_dir / f"state_{as_of.isoformat()}.pkl.gz"
    if not path.exists():
        return None
    with gzip.open(path, "rb") as fh:
        return pickle.load(fh)  # noqa: S301 - our own file
