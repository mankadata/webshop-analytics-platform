"""Command line entry point: `python -m webshop_pipeline <command>`.

bootstrap  simulate the full history (2025-01-01 .. end date) and load it, month by month
generate   simulate one day and write the six source exports to data/landing/
load       load one landing batch (optionally a single source) into raw_<source>
daily      generate + load (what the Airflow DAG does, in one command)
export     export gold-layer metrics to site/data/metrics.json
prune      delete landing files older than N days (raw keeps the data; saves disk)
"""

from __future__ import annotations

import argparse
import logging
import shutil
from datetime import date, timedelta

from . import export, load
from .config import LANDING_DIR, RANDOM_SEED, SITE_DATA_DIR, SOURCES, STATE_DIR
from .simulator import Simulator, load_state, save_state, write_batch
from .simulator.reference import HISTORY_START

log = logging.getLogger("webshop_pipeline")


def _month_end(day: date) -> date:
    first_next = (day.replace(day=1) + timedelta(days=32)).replace(day=1)
    return first_next - timedelta(days=1)


def bootstrap(end_date: date, force: bool = False) -> None:
    if not load.raw_is_empty():
        if not force:
            log.info("raw already contains data - skipping bootstrap (use --force to rebuild)")
            return
        load.drop_raw()
    # One landing batch per simulated day (so timeliness issues stay measurable),
    # loaded one month per transaction.
    sim = Simulator(RANDOM_SEED)
    day = HISTORY_START
    while day <= end_date:
        batch_ids, chunk_end = [], min(_month_end(day), end_date)
        while day <= chunk_end:
            write_batch(sim.step(day), LANDING_DIR, day.isoformat())
            batch_ids.append(day.isoformat())
            day += timedelta(days=1)
        load.load_batches(LANDING_DIR, batch_ids)
    save_state(sim.state, STATE_DIR)
    log.info("Bootstrap finished at %s", end_date)


def _simulator_for(day: date) -> Simulator:
    """Simulator positioned at the end of `day - 1` (from a snapshot, or by replaying)."""
    previous = day - timedelta(days=1)
    state = load_state(STATE_DIR, previous)
    if state is not None:
        return Simulator(RANDOM_SEED, state)
    log.info("No state snapshot for %s - replaying the simulation deterministically", previous)
    sim, d = Simulator(RANDOM_SEED), HISTORY_START
    while d <= previous:
        sim.step(d)
        d += timedelta(days=1)
    return sim


def generate(day: date) -> str:
    if load.raw_is_empty():
        bootstrap(day - timedelta(days=1))
    sim = _simulator_for(day)
    batch = sim.step(day)
    write_batch(batch, LANDING_DIR, day.isoformat())
    save_state(sim.state, STATE_DIR)
    log.info("Generated %s: %s", day, batch.counts())
    return day.isoformat()


def prune(keep_days: int) -> int:
    """Remove landing batch folders older than the newest batch minus `keep_days`."""
    removed = 0
    source_dirs = [d for d in LANDING_DIR.iterdir() if d.is_dir()] if LANDING_DIR.exists() else []
    for source_dir in source_dirs:
        batches = sorted(p for p in source_dir.iterdir() if p.is_dir() and p.name[:4].isdigit())
        if not batches:
            continue
        cutoff = date.fromisoformat(batches[-1].name) - timedelta(days=keep_days)
        for batch in batches:
            if date.fromisoformat(batch.name) < cutoff:
                shutil.rmtree(batch)
                removed += 1
    log.info("Pruned %d landing batch folders (kept the last %d days)", removed, keep_days)
    return removed


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    parser = argparse.ArgumentParser(prog="webshop_pipeline")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("bootstrap", help="generate and load the full history")
    p.add_argument("--end-date", type=date.fromisoformat, default=date.today() - timedelta(days=1))
    p.add_argument("--force", action="store_true", help="drop raw schemas and rebuild")

    p = sub.add_parser("generate", help="simulate one day and write the source exports")
    p.add_argument("--date", type=date.fromisoformat, required=True)

    p = sub.add_parser("load", help="load one landing batch into raw")
    p.add_argument("--batch-id", required=True)
    p.add_argument("--source", choices=SOURCES)

    p = sub.add_parser("daily", help="generate + load one day")
    p.add_argument("--date", type=date.fromisoformat, required=True)

    p = sub.add_parser("export", help="export gold metrics for the website")
    p.add_argument("--out", default=SITE_DATA_DIR)

    p = sub.add_parser("prune", help="delete old landing files")
    p.add_argument("--keep-days", type=int, default=14)

    args = parser.parse_args(argv)
    if args.command == "bootstrap":
        bootstrap(args.end_date, args.force)
    elif args.command == "generate":
        generate(args.date)
    elif args.command == "load":
        load.load_batch(LANDING_DIR, args.batch_id, args.source)
    elif args.command == "daily":
        load.load_batch(LANDING_DIR, generate(args.date))
    elif args.command == "export":
        export.export_site_data(args.out)
    elif args.command == "prune":
        prune(args.keep_days)


if __name__ == "__main__":
    main()
