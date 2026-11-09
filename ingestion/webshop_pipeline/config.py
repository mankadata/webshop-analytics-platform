"""Central configuration, read from environment variables (12-factor style)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

# Global seed: same seed + same date => identical source files.
RANDOM_SEED = int(os.getenv("WEBSHOP_SEED", "42"))

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = Path(os.getenv("DATA_DIR", REPO_ROOT / "data"))
LANDING_DIR = Path(os.getenv("LANDING_DIR", DATA_DIR / "landing"))
STATE_DIR = Path(os.getenv("STATE_DIR", DATA_DIR / "state"))
SITE_DATA_DIR = Path(os.getenv("SITE_DATA_DIR", REPO_ROOT / "site" / "data"))
DBT_TARGET_DIR = Path(os.getenv("DBT_TARGET_DIR", REPO_ROOT / "dbt" / "webshop_analytics" / "target"))

SOURCES = ("shop", "payments", "erp", "marketing", "web", "ecb")


def raw_schema(source: str) -> str:
    return f"raw_{source}"


@dataclass(frozen=True)
class WarehouseConfig:
    host: str = field(default_factory=lambda: os.getenv("WAREHOUSE_HOST", "localhost"))
    port: int = field(default_factory=lambda: int(os.getenv("WAREHOUSE_PORT", "5432")))
    user: str = field(default_factory=lambda: os.getenv("WAREHOUSE_USER", "webshop"))
    password: str = field(default_factory=lambda: os.getenv("WAREHOUSE_PASSWORD", "webshop"))
    dbname: str = field(default_factory=lambda: os.getenv("WAREHOUSE_DB", "warehouse"))

    def dsn(self) -> str:
        return f"host={self.host} port={self.port} user={self.user} password={self.password} dbname={self.dbname}"
