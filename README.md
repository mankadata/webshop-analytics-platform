# WebShop Pro analytics platform

> **Work in progress.** This is a personal learning project that I build step by step,
> as my time and energy allow. The build log below shows what is finished and what comes next.

**Build log site:** https://mankadata.github.io/webshop-analytics-platform/

## Business context

WebShop Pro is an online retailer founded in 2025, selling ~230 products in six categories
to seven Central-European countries, in HUF and EUR. Its data lives in six systems: the shop
database, a payment provider, an ERP, ad platforms, web analytics and ECB exchange rates.
Every team used its own spreadsheet, so "orders last month" had three different answers.

This project builds the company's warehouse: one place where metrics are defined once and
reconcile across systems. The marts layer will answer four groups of questions:
- **Management & finance:** net revenue, margin, monthly P&L, payment reconciliation
- **Marketing:** customer acquisition cost, ROAS, conversion funnel by channel
- **Operations:** stock on hand, stockouts, supplier lead times
- **CRM:** customer segments, retention, repeat purchases

## How it is built

First the raw exports of the six source systems are loaded into a PostgreSQL warehouse and
profiled, because a model can only be designed well once the real data and its defects are
known. The staging layer then gives every raw table clean names and correct types without
dropping anything, so it stays a stable, one-to-one base for everything above it. The
intermediate layer does the real cleaning - deduplication, standardisation, currency
conversion and quarantining of bad rows - because these steps need business rules and
reference data. The marts layer turns the result into dimensions, facts and reports that the
business can trust, with personal data masked. Finally, tests, orchestration and CI make the
whole pipeline run every day and stop bad data before it reaches a report.

```mermaid
flowchart LR
    SRC[6 source systems] --> RAW[(raw)] --> STG[(staging)] --> INT[(intermediate)] --> MRT[(marts)] --> BI[Reports]
```

## Progress

| Step | Topic | Status |
|---|---|---|
| 1 | Setup: warehouse and dbt project | done |
| 2 | Data sources: raw data and source declarations | done |
| 3 | Data profiling: what the raw data looks like | done |
| 4 | Staging models | in progress |
| 5 | Intermediate: cleaning, keys, deduplication, quarantine | planned |
| 6 | Marts: dimensions, facts, business marts | planned |
| 7 | Data quality and tests | planned |
| 8 | Orchestration and CI | planned |

## Technologies and why

| Technology | Role | Why |
|---|---|---|
| **PostgreSQL 16** | data warehouse | free, runs anywhere, and supports warehouse-style SQL (window functions, JSON, grants); the SQL moves to Snowflake or BigQuery with few changes |
| **Docker Compose** | runs the database (and later Airflow) | the same environment on every machine and in CI, nothing installed by hand |
| **dbt Core** | transformations, tests, documentation | the industry standard for analytics engineering: SQL models, dependency graph, built-in tests and lineage |
| **Python** | source simulator and raw loader | the usual language for ingestion; reads CSV, JSON and Hungarian-encoded files |
| **Apache Airflow** | daily orchestration | the most widely used scheduler; runs each layer in order and stops on failed tests |
| **GitHub Actions** | CI and publishing | runs checks on every change and publishes the build log site |
| **GitHub Codespaces + VS Code** | development environment | everything runs in the cloud - no installs or disk space on my own computer |
| **Git + GitHub Pages** | version control and project site | every step is a reviewed commit, and the build log is public |

## Acknowledgements

- **Data:** all data is synthetic, produced by a deterministic Python simulator written for
  this project. There are no real customers or transactions.
- **AI assistance:** the code and documentation are developed with the help of an AI
  assistant (Claude by Anthropic). I define the scope, make the design decisions, and
  review, run and test every step.

## License

© 2026 mankadata. All rights reserved.

You are welcome to read this code. Please do not copy, redistribute or reuse substantial parts of it without permission. The code is provided
"as is", without warranty of any kind, and I accept no liability for its use.
