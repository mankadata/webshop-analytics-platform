"""Load landing files into the warehouse `raw_<source>` schemas (EL of ELT).

Design choices
--------------
* CSV sources land as all-TEXT tables; JSON sources land as one `jsonb`
  column. Typing and parsing are tested dbt concerns, so an upstream format
  change never breaks ingestion.
* Schema evolution (DQ15): a CSV column that the table does not have yet is
  added with `ALTER TABLE ... ADD COLUMN` and logged - nothing is dropped.
* Encodings are handled by Postgres itself (`COPY ... ENCODING 'WIN1250'`).
* Lineage columns on every row: _batch_id, _source_file, _loaded_at.
* Idempotent per batch: rows of a batch are deleted and re-inserted in a
  single transaction, so re-running an Airflow task never duplicates data.
"""

from __future__ import annotations

import csv
import gzip
import io
import json
import logging
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import psycopg2

from .config import SOURCES, WarehouseConfig, raw_schema
from .simulator.io import FILE_FORMATS

log = logging.getLogger(__name__)

LINEAGE_DDL = "_batch_id text not null, _source_file text not null, _loaded_at timestamptz not null default now()"
PG_ENCODING = {"cp1250": "WIN1250", "utf-8": "UTF8"}


@contextmanager
def connect(cfg: WarehouseConfig | None = None):
    conn = psycopg2.connect((cfg or WarehouseConfig()).dsn())
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _existing_columns(cur, schema: str, table: str) -> list[str]:
    cur.execute(
        "select column_name from information_schema.columns "
        "where table_schema = %s and table_name = %s order by ordinal_position",
        (schema, table),
    )
    return [r[0] for r in cur.fetchall()]


def _ensure_csv_table(cur, schema: str, table: str, columns: list[str]) -> None:
    cur.execute(f"create schema if not exists {schema}")
    existing = _existing_columns(cur, schema, table)
    if not existing:
        cols = ", ".join(f'"{c}" text' for c in columns)
        cur.execute(f"create table {schema}.{table} ({cols}, {LINEAGE_DDL})")
        cur.execute(f"create index on {schema}.{table} (_batch_id)")
        return
    for col in columns:
        if col not in existing:
            log.warning("Schema drift in %s.%s: new column %r added", schema, table, col)
            cur.execute(f'alter table {schema}.{table} add column "{col}" text')


def _ensure_json_table(cur, schema: str, table: str) -> None:
    cur.execute(f"create schema if not exists {schema}")
    cur.execute(f"create table if not exists {schema}.{table} (payload jsonb not null, {LINEAGE_DDL})")
    cur.execute(f"create index if not exists {table}_batch_idx on {schema}.{table} (_batch_id)")


def _json_lines(path: Path, kind: str) -> Iterator[str]:
    if kind == "json_array":
        for item in json.loads(path.read_text(encoding="utf-8")):
            yield json.dumps(item, ensure_ascii=False)
        return
    opener = gzip.open if kind == "jsonl_gz" else open
    with opener(path, "rt", encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                yield line.rstrip("\n")


def load_file(cur, source: str, entity: str, path: Path, batch_id: str) -> int:
    spec = FILE_FORMATS[(source, entity)]
    schema, table = raw_schema(source), entity
    rel_path = f"{source}/{batch_id}/{path.name}"

    if spec["kind"] == "csv":
        encoding = spec.get("encoding", "utf-8")
        delimiter = spec.get("delimiter", ",")
        with open(path, encoding=encoding, newline="") as fh:
            header = next(csv.reader(fh, delimiter=delimiter))
        _ensure_csv_table(cur, schema, table, header)
        cur.execute(f"delete from {schema}.{table} where _batch_id = %s", (batch_id,))
        cols = ", ".join(f'"{c}"' for c in header)
        cur.execute(f"create temp table _stage on commit drop as select {cols} from {schema}.{table} with no data")
        with open(path, "rb") as fh:
            cur.copy_expert(
                f"copy _stage ({cols}) from stdin with (format csv, header true, "
                f"delimiter '{delimiter}', encoding '{PG_ENCODING[encoding]}')",
                fh,
            )
        cur.execute(
            f"insert into {schema}.{table} ({cols}, _batch_id, _source_file) select {cols}, %s, %s from _stage",
            (batch_id, rel_path),
        )
    else:
        _ensure_json_table(cur, schema, table)
        cur.execute(f"delete from {schema}.{table} where _batch_id = %s", (batch_id,))
        cur.execute("create temp table _stage (payload text) on commit drop")
        buffer = io.StringIO("".join(line + "\n" for line in _json_lines(path, spec["kind"])))
        # CSV mode with control characters as quote/delimiter = raw line-by-line copy
        cur.copy_expert(
            "copy _stage (payload) from stdin with (format csv, quote e'\\x01', delimiter e'\\x02')", buffer
        )
        cur.execute(
            f"insert into {schema}.{table} (payload, _batch_id, _source_file) "
            "select payload::jsonb, %s, %s from _stage",
            (batch_id, rel_path),
        )
    count = cur.rowcount
    cur.execute("drop table _stage")
    return count


def load_batches(
    landing_dir: Path, batch_ids: list[str], source: str | None = None, cfg: WarehouseConfig | None = None
) -> dict[str, int]:
    """Load batches (optionally one source only) in a single transaction."""
    loaded: dict[str, int] = {}
    with connect(cfg) as conn, conn.cursor() as cur:
        for batch_id in batch_ids:
            for (src, entity), spec in FILE_FORMATS.items():
                if source and src != source:
                    continue
                path = landing_dir / src / batch_id / spec["file"]
                if path.exists():
                    key = f"{src}.{entity}"
                    loaded[key] = loaded.get(key, 0) + load_file(cur, src, entity, path, batch_id)
    log.info("Loaded %s: %s", batch_ids[0] if len(batch_ids) == 1 else f"{batch_ids[0]}..{batch_ids[-1]}", loaded)
    return loaded


def load_batch(
    landing_dir: Path, batch_id: str, source: str | None = None, cfg: WarehouseConfig | None = None
) -> dict[str, int]:
    return load_batches(landing_dir, [batch_id], source, cfg)


def raw_is_empty(cfg: WarehouseConfig | None = None) -> bool:
    with connect(cfg) as conn, conn.cursor() as cur:
        cur.execute("select to_regclass('raw_shop.orders') is null")
        if cur.fetchone()[0]:
            return True
        cur.execute("select not exists (select 1 from raw_shop.orders)")
        return cur.fetchone()[0]


def drop_raw(cfg: WarehouseConfig | None = None) -> None:
    with connect(cfg) as conn, conn.cursor() as cur:
        for source in SOURCES:
            cur.execute(f"drop schema if exists {raw_schema(source)} cascade")
