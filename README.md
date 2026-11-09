# WebShop Pro analytics platform

## Business context

WebShop Pro is an online retailer founded in 2025, selling ~230 products in six categories
to seven Central-European countries, in HUF and EUR. Its data lives in six systems: the shop
database, a payment provider, an ERP, ad platforms, web analytics and ECB exchange rates.
Every team used its own spreadsheet, so "orders last month" had three different answers.

This project builds the company's warehouse: one place where metrics are defined once and
reconcile across systems. The gold layer answers four groups of questions:
- **Management & finance:** net revenue, margin, monthly P&L, payment reconciliation
- **Marketing:** customer acquisition cost, ROAS, conversion funnel by channel
- **Operations:** stock on hand, stockouts, supplier lead times
- **CRM:** customer segments, retention, repeat purchases