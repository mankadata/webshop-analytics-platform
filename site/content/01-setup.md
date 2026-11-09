# Step 1 - Setup: warehouse and dbt project

## Goal

A running PostgreSQL warehouse and an empty dbt project that can connect to it, with the
layer structure decided before the first model is written.

## What I built

| File | Purpose |
|---|---|
| `docker-compose.yml` | PostgreSQL 16 warehouse in a container |
| `requirements.txt` | pinned Python packages (dbt and its Postgres adapter) |
| `dbt/webshop_analytics/dbt_project.yml` | project settings and the layer configuration |
| `dbt/webshop_analytics/profiles.yml` | connection settings, without secrets |
| `dbt/webshop_analytics/macros/generate_schema_name.sql` | clean schema names per layer |

### The warehouse

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: webshop
      POSTGRES_PASSWORD: webshop        # local development only
      POSTGRES_DB: warehouse
    ports: ["5432:5432"]
    volumes:
      - pgdata:/var/lib/postgresql/data # data survives container restarts
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U webshop -d warehouse"]
```

### dbt and its adapter

```text
dbt-core~=1.12.0       # dbt engine and command line tool
dbt-postgres~=1.11.0   # adapter: lets dbt talk to PostgreSQL
```

### Layers are decided by folders

```yaml
models:
  webshop_analytics:
    staging:
      +schema: staging
      +materialized: view
    intermediate:
      +schema: intermediate
      +materialized: view
    marts:
      +schema: marts
      +materialized: table
```

### A connection without secrets

```yaml
webshop_analytics:
  target: dev
  outputs:
    dev:
      type: postgres
      host: "{{ env_var('WAREHOUSE_HOST', 'localhost') }}"
      user: "{{ env_var('WAREHOUSE_USER', 'webshop') }}"
      password: "{{ env_var('WAREHOUSE_PASSWORD', 'webshop') }}"
      dbname: "{{ env_var('WAREHOUSE_DB', 'warehouse') }}"
      schema: analytics
      threads: 4
```

## Decisions

**PostgreSQL in Docker.** Free, identical on every machine and in CI, and rich enough for
warehouse-style SQL (window functions, JSON, constraints, grants). The dbt code moves to
Snowflake or BigQuery with few changes.

**Pinned versions.** `pip install dbt-core` would install whatever is newest today. Pinning
(`~=1.12.0`) means bug fixes arrive automatically, but a breaking new version does not.

**dbt layer names, medallion in comments.** `staging / intermediate / marts` is the dbt
convention most teams use; the bronze / silver / gold equivalents are noted for readers from
the lakehouse world.

**Views in staging and intermediate, tables in marts.** Views are always up to date and cost
nothing to rebuild while the logic still changes. Marts are queried by people and tools, so
they are stored as tables. A heavy intermediate model can switch to a table in its own
`config()` block.

**One schema per layer.** Without `+schema` every model would land in one schema. Separate
schemas make the layers visible in the database and allow access rules per layer - analysts
will only be granted the marts. The `generate_schema_name` macro keeps the names clean
(`marts` instead of dbt's default `analytics_marts`).

**`profiles.yml` in the repository, but without secrets.** The usual advice is to keep this
file out of git. Here every value comes from an environment variable via `env_var()`; the
second argument is only the local development default. Nothing secret is committed, and the
project works right after cloning. CI and Airflow pass the real values as environment
variables.

## How I verified it

```bash
docker compose up -d --wait        # container reports "Healthy"
docker compose exec postgres psql -U webshop -d warehouse -c "select version();"
dbt --version                      # Core 1.12.x, postgres 1.11.x
dbt debug                          # Connection test: OK ... All checks passed!
