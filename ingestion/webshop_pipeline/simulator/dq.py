"""Rendering of simulated records into source-system formats, with injected
data-quality defects.

Every defect is tagged with an issue code from the catalogue in
`docs/data-quality.md` (and the dbt seed `dq_issue_catalog.csv`):

    DQ01 missing / placeholder values      DQ09 out-of-range / impossible values
    DQ02 exact duplicates                  DQ10 orphan records (broken references)
    DQ03 fuzzy duplicates                  DQ11 non-standard codes & spellings
    DQ04 inconsistent formatting           DQ12 late-arriving data
    DQ05 invalid formats                   DQ13 missing / delayed loads
    DQ06 mixed date formats & time zones   DQ14 cross-field / cross-system inconsistencies
    DQ07 mixed currencies & units          DQ15 schema drift
    DQ08 locale-specific number formats

Rates are deliberately small (0.1-15%), like in real systems.
"""

from __future__ import annotations

import random
import unicodedata
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import TYPE_CHECKING
from zoneinfo import ZoneInfo

from . import reference as ref

if TYPE_CHECKING:  # pragma: no cover
    from .engine import Customer, Order, OrderLine, Product, PurchaseOrder

LOCAL_TZ = ZoneInfo("Europe/Budapest")


# --------------------------------------------------------------------------- #
# Format helpers
# --------------------------------------------------------------------------- #


def ascii_fold(text: str) -> str:
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()


def local_ts(dt: datetime) -> str:
    """Shop database: naive local time (Europe/Budapest), no offset."""
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def to_utc(dt: datetime) -> datetime:
    return dt.replace(tzinfo=LOCAL_TZ).astimezone(UTC)


def hu_date(d: date) -> str:
    """ERP: Hungarian date format, e.g. 2026.11.05."""  # DQ06
    return d.strftime("%Y.%m.%d.")


def hu_number(value: float, decimals: int = 2) -> str:
    """ERP: Hungarian number format with space thousands separator, e.g. 1 299,90"""  # DQ08
    text = f"{value:,.{decimals}f}"
    return text.replace(",", " ").replace(".", ",")


def _uid(rng: random.Random, prefix: str = "") -> str:
    return prefix + uuid.UUID(int=rng.getrandbits(128), version=4).hex[:24]


# --------------------------------------------------------------------------- #
# shop: products, customers, orders, order_items
# --------------------------------------------------------------------------- #


def render_product(p: Product, rng: random.Random) -> dict:
    roll = rng.random()
    if roll < 0.03:
        weight = rng.choice(["", "-", "n/a"])  # DQ01
    elif roll < 0.45:
        weight = f"{p.weight_g} g"
    elif roll < 0.6:
        weight = f"{p.weight_g}g"
    else:
        weight = f"{hu_number(p.weight_g / 1000, 2).rstrip('0').rstrip(',')} kg"  # DQ07 mixed units
    return {
        "product_id": p.product_id,
        "sku": p.sku,
        "product_name": p.name,
        "category": p.category_raw,  # DQ11
        "brand": p.brand,
        "list_price_eur": f"{p.list_price_eur:.2f}",
        "weight": weight,
        "warehouse_code": p.warehouse,
        "supplier_code": p.supplier,
        "is_active": "true" if p.is_active else "false",
        "updated_at": local_ts(p.updated_at),
    }


def _phone(digits: str, country: str, rng: random.Random) -> str:
    prefix = ref.PHONE_PREFIX[country]
    national = digits[len(prefix) :]
    style = rng.random()
    if style < 0.08:
        return rng.choice(["", "N/A", "-", "nincs", "0"])  # DQ01 placeholders
    if style < 0.45:
        return f"+{prefix}{national}"
    if style < 0.65:
        return f"+{prefix} {national[:2]} {national[2:5]} {national[5:]}"  # DQ04
    if style < 0.8 and country == "HU":
        return f"06{national}"  # DQ04 national trunk prefix
    if style < 0.9:
        return f"{prefix}-{national[:2]}/{national[2:5]}-{national[5:]}"
    return f"00{prefix}{national}"


def render_customer(c: Customer, rng: random.Random, day: date, fuzzy_duplicate: bool = False) -> dict:
    email = c.email
    first, last = c.first_name, c.last_name
    if fuzzy_duplicate:  # DQ03: same person, slightly different spelling
        email = rng.choice([email.upper(), f" {email}", email.capitalize(), email.replace("@", " @")])
        if rng.random() < 0.5:
            first, last = ascii_fold(first), ascii_fold(last)
    else:
        if rng.random() < 0.05:
            email = email.upper() if rng.random() < 0.5 else email.title()  # DQ04
        if rng.random() < 0.03:
            email = f"  {email} "  # DQ04
        if rng.random() < 0.008:  # DQ05 invalid syntax
            email = rng.choice([email.replace("@", ""), email.rsplit(".", 1)[0], email.replace("@", "@@")])
    if rng.random() < 0.02:
        first, last = first.lower(), last.upper()  # DQ04

    country = c.country
    if rng.random() < 0.15:
        country = rng.choice(ref.COUNTRIES[c.country][2])  # DQ11 aliases

    postal = c.postal_code
    if c.country == "HU" and rng.random() < 0.015:
        postal = f"H-{postal}"  # DQ05 (fixable)
    elif rng.random() < 0.005:
        postal = postal + str(rng.randint(0, 9))  # DQ05 (invalid)

    if c.birth_date is None:
        birth = rng.choice(["", "", "N/A"])  # DQ01
    elif rng.random() < 0.005:
        birth = rng.choice(["1900-01-01", (day + timedelta(days=400)).isoformat()])  # DQ09
    else:
        birth = c.birth_date.isoformat()

    vat = c.vat_number or ""
    if vat and rng.random() < 0.05:
        vat = vat.replace("-", "")[:7]  # DQ05

    row = {
        "customer_id": c.customer_id,
        "first_name": first,
        "last_name": last,
        "email": email,
        "phone": _phone(c.phone, c.country, rng),
        "country": country,
        "postal_code": postal,
        "city": c.city,
        "street": c.street,
        "birth_date": birth,
        "customer_type": "B2B" if c.is_b2b else "B2C",
        "vat_number": vat,
        "signup_at": local_ts(c.signup_at),
        "marketing_opt_in": "1" if c.marketing_opt_in else "0",
        "updated_at": local_ts(c.updated_at),
    }
    if day >= ref.SCHEMA_DRIFT_DATE:  # DQ15: column renamed + new column appears
        row["phone_number"] = row.pop("phone")
        row["loyalty_tier"] = c.loyalty_tier
    return row


def render_order(o: Order, when: datetime, rng: random.Random) -> dict:
    status = o.status if rng.random() > 0.004 else ""  # DQ01
    return {
        "order_id": o.order_id,
        "customer_id": o.customer_id,
        "ordered_at": local_ts(o.ordered_at),  # DQ06: local time, no offset
        "status": status,
        "currency": o.currency,
        "payment_method": o.payment_method,
        "sales_channel": o.sales_channel,
        "shipping_country": o.shipping_country,
        "shipping_fee": f"{o.shipping_fee:.2f}",
        "updated_at": local_ts(when),
    }


def render_order_item(line: OrderLine, o: Order, rng: random.Random) -> list[dict]:
    row = {
        "order_item_id": line.order_item_id,
        "order_id": o.order_id,
        "product_id": line.product_id,
        "quantity": line.quantity,
        "unit_price": f"{line.unit_price:.2f}",
        "discount_pct": line.discount_pct,
        "created_at": local_ts(o.ordered_at),
    }
    roll = rng.random()
    if roll < 0.001:
        row["quantity"] = rng.choice([0, -1])  # DQ09
    elif roll < 0.0015:
        row["discount_pct"] = 120  # DQ09
    elif roll < 0.0025:
        row["product_id"] = 990_000 + rng.randint(1, 999)  # DQ10 unknown product
    rows = [row]
    if rng.random() < 0.005:
        rows.append(dict(row))  # DQ02 at-least-once delivery
    return rows


# --------------------------------------------------------------------------- #
# payments: provider webhooks (JSON)
# --------------------------------------------------------------------------- #


def payment_event(event_type: str, o: Order, when_local: datetime, rng: random.Random) -> dict:
    amount = round(o.total * 100)  # minor units  (DQ07)
    if event_type == "charge.succeeded" and rng.random() < 0.004:
        amount += rng.choice([-100, 100, -5000, 1])  # DQ14: captured amount != order total
    method = {"card": "card", "paypal": "paypal", "bank_transfer": "sepa_credit_transfer", "cash_on_delivery": "cod"}
    details: dict = {"type": method[o.payment_method]}
    if o.payment_method == "card":
        details["card"] = {
            "brand": rng.choice(["visa", "mastercard", "amex"]),
            "funding": rng.choice(["debit", "credit"]),
        }
    obj = {
        "id": _uid(rng, "re_" if event_type.startswith("refund") else "ch_"),
        "order_reference": f"WS-{o.order_id}",
        "amount": amount,
        "currency": o.currency.lower(),
        "payment_method_details": details,
    }
    if event_type == "charge.failed":
        obj["failure_code"] = rng.choice(["card_declined", "insufficient_funds", "expired_card"])
    return {
        "id": _uid(rng, "evt_"),
        "object": "event",
        "type": event_type,
        "created": int(to_utc(when_local).timestamp()),  # DQ06: epoch seconds, UTC
        "livemode": True,
        "data": {"object": obj},
    }


def test_payment_event(day: date, rng: random.Random) -> dict:
    """DQ10: sandbox transactions referencing orders that do not exist."""
    when = datetime.combine(day, datetime.min.time()) + timedelta(seconds=rng.randint(0, 86_399))
    return {
        "id": _uid(rng, "evt_"),
        "object": "event",
        "type": "charge.succeeded",
        "created": int(to_utc(when).timestamp()),
        "livemode": False,
        "data": {
            "object": {
                "id": _uid(rng, "ch_"),
                "order_reference": f"WS-TEST-{rng.randint(1000, 9999)}",
                "amount": rng.choice([100, 2500, 99900]),
                "currency": "eur",
                "payment_method_details": {"type": "card"},
            }
        },
    }


def duplicate_webhooks(events: list[dict], rng: random.Random) -> list[dict]:
    """DQ02: the provider retries ~1.5% of webhooks (same event id)."""
    out = []
    for event in events:
        out.append(event)
        if rng.random() < 0.015:
            out.append(event)
    return out


# --------------------------------------------------------------------------- #
# ERP: invoices, stock movements, purchase orders (Hungarian CSV, cp1250)
# --------------------------------------------------------------------------- #


def render_invoice(o: Order, day: date, number: int, vat: int, credit_note: bool, rng: random.Random) -> dict:
    decimals = 0 if o.currency == "HUF" else 2
    gross = round(o.total * (-1 if credit_note else 1), decimals)
    net = round(gross / (1 + vat / 100), decimals)
    vat_amount = round(gross - net, decimals)
    if rng.random() < 0.005:
        vat_amount += rng.choice([-1, 1]) * (1 if decimals == 0 else 0.01)  # DQ14 rounding error
    prefix = "JV" if credit_note else "SZ"
    return {
        "szamlaszam": f"{prefix}-{day.year}-{number:06d}",
        "bizonylat_tipus": "JOVAIRAS" if credit_note else "SZAMLA",
        "rendeles_azonosito": f"WS-{o.order_id}",
        "kelt": hu_date(day),  # DQ06
        "penznem": o.currency,
        "netto": hu_number(net, decimals),  # DQ08
        "afa_kulcs": rng.choice([f"{vat}%", f"{vat}%", str(vat), f"{vat},00"]),  # DQ08
        "afa_osszeg": hu_number(vat_amount, decimals),
        "brutto": hu_number(gross, decimals),
        "vevo_orszag": o.shipping_country,
    }


def render_movement(
    movement_id: int,
    day: date,
    product: Product,
    movement_type: str,
    qty: int,
    unit_cost_eur: float | None,
    reference: str,
    note: str,
    rng: random.Random,
) -> dict:
    sku = product.sku
    if rng.random() < 0.01:
        sku = f" {sku.lower()}"  # DQ04
    quantity = qty
    if movement_type == "ELAD" and rng.random() < 0.002:
        quantity = -qty  # DQ09 sign error
    return {
        "mozgas_azon": movement_id,
        "datum": hu_date(day),
        "raktar": product.warehouse,
        "cikkszam": sku,
        "mozgasnem": movement_type,  # Hungarian codes, mapped with a seed (DQ11)
        "mennyiseg": quantity,
        "egysegar_eur": hu_number(unit_cost_eur) if unit_cost_eur is not None else "",
        "bizonylat": reference,
        "megjegyzes": note,
    }


def render_purchase_order(
    po: PurchaseOrder, currency: str, status: str, day: date, products: dict, header_only: bool = False
) -> list[dict]:
    rows = [
        {
            "_entity": "purchase_orders",
            "po_szam": po.po_number,
            "szallito_kod": po.supplier,
            "rendeles_datum": hu_date(po.order_date),
            "vart_datum": hu_date(po.expected_date),
            "statusz": status,
            "modositva": hu_date(day),
        }
    ]
    if not header_only:
        for line_no, (pid, qty, cost) in enumerate(po.lines, start=1):
            rows.append(
                {
                    "_entity": "purchase_order_lines",
                    "po_szam": po.po_number,
                    "sor": line_no,
                    "cikkszam": products[pid].sku,
                    "mennyiseg": qty,
                    "egysegar": hu_number(cost),  # DQ07: supplier currency (HUF or EUR)
                    "penznem": currency,
                }
            )
    return rows


# --------------------------------------------------------------------------- #
# marketing: ad platform reports
# --------------------------------------------------------------------------- #


def campaigns_for(platform: str, day: date) -> list[tuple[str, str]]:
    """Campaigns running on a platform on a day: (campaign_id, campaign_name)."""
    short = {"google_ads": "g", "meta_ads": "m", "tiktok_ads": "t"}[platform]
    names = ["Brand - Always On", "Prospecting - Catalogue"]
    if day.month == 11:
        names.append(f"Black Friday {day.year}")
    elif day.month == 12:
        names.append(f"Christmas {day.year}")
    elif day.month in (3, 4):
        names.append(f"Spring Sale {day.year}")
    elif day.month in (6, 7, 8):
        names.append(f"Summer Outdoor {day.year}")
    return [(f"{short}-{abs(hash_name(n)) % 100000:05d}", n) for n in names]


def hash_name(name: str) -> int:
    return sum((i + 1) * ord(ch) for i, ch in enumerate(name))


def ad_report(
    platform: str, currency: str, day: date, budget_eur: float, fx: dict[str, float], rng: random.Random
) -> dict:
    campaigns = campaigns_for(platform, day)
    weights = [rng.uniform(0.5, 1.5) * (2.2 if "Friday" in n or "Christmas" in n else 1) for _, n in campaigns]
    rate = fx["USD"] if currency == "USD" else 1.0
    rows = []
    for (cid, name), w in zip(campaigns, weights, strict=True):
        spend_eur = budget_eur * w / sum(weights)
        cpc = {"google_ads": 0.45, "meta_ads": 0.32, "tiktok_ads": 0.18}[platform] * rng.uniform(0.8, 1.25)
        clicks = max(0, round(spend_eur / cpc))
        rows.append(
            {
                "campaign_id": cid,
                "campaign_name": name,
                "impressions": clicks * rng.randint(35, 90),
                "clicks": clicks,
                "spend": f"{spend_eur * rate:.2f}",  # DQ07: account currency
            }
        )
    return {"platform": platform, "report_date": day.isoformat(), "account_currency": currency, "rows": rows}


def newsletter_cost(day: date) -> dict:
    return {
        "platform": "newsletter",
        "report_date": day.isoformat(),
        "account_currency": "HUF",
        "rows": [
            {
                "campaign_id": "nl-subscription",
                "campaign_name": "Newsletter platform subscription",
                "impressions": 0,
                "clicks": 0,
                "spend": "59990",
            }
        ],
    }


# --------------------------------------------------------------------------- #
# web: analytics events
# --------------------------------------------------------------------------- #

PAID_PLATFORM = {"paid_search": "google_ads", "paid_social": "meta_ads", "tiktok": "tiktok_ads"}


def _utm_campaign(channel: str, day: date, rng: random.Random) -> str | None:
    if channel == "email":
        return rng.choice([f"newsletter_{day:%Y_%m}", f"Newsletter {day:%Y-%m}"])
    if channel not in PAID_PLATFORM:
        return None
    _, name = rng.choice(campaigns_for(PAID_PLATFORM[channel], day))
    slug = name.lower().replace(" - ", "_").replace(" ", "_")
    return rng.choice([slug, slug, name, slug.replace("_", "-")])  # DQ11


def _iso_utc(dt_local: datetime) -> str:
    return to_utc(dt_local).strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt_local.microsecond // 1000:03d}Z"


def session_events(
    session_number: int,
    channel: str,
    start: datetime,
    rng: random.Random,
    products: list,
    order: Order | None = None,
) -> list[dict]:
    source, medium = rng.choice(ref.CHANNELS[channel][2])
    campaign = _utm_campaign(channel, start.date(), rng)
    device = rng.choices(*ref.DEVICE_MIX)[0]
    session_id = f"s{session_number:09d}"
    anonymous_id = _uid(rng, "a_")
    user_id = order.customer_id if order else None

    def event(name: str, offset_s: int, **ecommerce) -> dict:
        ts = start + timedelta(seconds=offset_s, milliseconds=rng.randint(0, 999))
        return {
            "event_id": _uid(rng),
            "event_name": name,
            "event_timestamp": _iso_utc(ts),  # DQ06: ISO-8601 UTC
            "session_id": session_id,
            "anonymous_id": anonymous_id,
            "user_id": user_id,
            "page": {"path": ecommerce.pop("path", "/")},
            "traffic_source": {"source": source, "medium": medium, "campaign": campaign},
            "device": {"category": device},
            "ecommerce": ecommerce or None,
            "_late": True,
        }

    events = [event("page_view", 0, path=rng.choice(["/", "/sale", "/c/new", "/blog"]))]
    t = rng.randint(20, 90)
    if order:
        for line in order.lines:
            events.append(event("view_item", t, path=f"/p/{line.product_id}", product_id=line.product_id))
            t += rng.randint(15, 120)
            events.append(event("add_to_cart", t, path=f"/p/{line.product_id}", product_id=line.product_id))
            t += rng.randint(10, 60)
        events.append(event("begin_checkout", t, path="/checkout"))
        events.append(
            event(
                "purchase",
                t + rng.randint(40, 200),
                path="/checkout/success",
                order_id=order.order_id,
                value=order.total,
                currency=order.currency,
            )
        )
        return events
    if rng.random() < 0.55:
        product = rng.choice(products)
        events.append(event("view_item", t, path=f"/p/{product.product_id}", product_id=product.product_id))
        if rng.random() < 0.25:
            events.append(event("add_to_cart", t + 30, path=f"/p/{product.product_id}", product_id=product.product_id))
            if rng.random() < 0.3:
                events.append(event("begin_checkout", t + 90, path="/checkout"))
    return events
