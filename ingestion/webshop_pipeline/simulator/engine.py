"""WebShop Pro business simulator.

One call to `Simulator.step(day)` advances the company by one day and returns
the *changes* that each of the six source systems would export for that day:

    shop       e-commerce database (customers, products, orders, order_items, returns)  CSV
    payments   payment provider webhooks (nested JSON, epoch timestamps, minor units)    JSONL
    erp        ERP export: suppliers, purchase orders, stock movements, invoices         CSV ; cp1250
    marketing  ad platform daily reports (google, meta, tiktok)                          JSON
    web        web analytics event stream                                                JSONL
    ecb        reference FX rates, business days only                                    CSV

The simulation itself is clean and internally consistent. Data-quality defects
are injected only when rows are *rendered* for export (see `dq.py`), each one
tagged with an issue code DQ01-DQ15 so it can be traced end-to-end.

Everything is driven by a RNG seeded with (global seed, date), so the same day
always produces the same output, whichever way the state was reached.
"""

from __future__ import annotations

import math
import random
from bisect import bisect_right
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from itertools import accumulate

from faker import Faker

from . import dq
from . import reference as ref

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #


@dataclass
class Customer:
    customer_id: int
    first_name: str
    last_name: str
    email: str
    country: str
    phone: str  # digits incl. country prefix, e.g. 36301234567
    postal_code: str
    city: str
    street: str
    birth_date: date | None
    is_b2b: bool
    vat_number: str | None
    signup_at: datetime
    marketing_opt_in: bool
    loyalty_tier: str
    updated_at: datetime


@dataclass
class Product:
    product_id: int
    sku: str
    name: str
    category: str
    category_raw: str
    brand: str
    list_price_eur: float
    unit_cost_eur: float
    weight_g: int
    warehouse: str
    supplier: str
    is_active: bool
    updated_at: datetime
    popularity: float


@dataclass
class OrderLine:
    order_item_id: int
    product_id: int
    quantity: int
    unit_price: float  # local currency, VAT included
    discount_pct: int

    def gross(self) -> float:
        return round(self.quantity * self.unit_price * (1 - self.discount_pct / 100), 2)


@dataclass
class Order:
    order_id: int
    customer_id: int
    ordered_at: datetime
    currency: str
    payment_method: str
    sales_channel: str
    shipping_country: str
    shipping_fee: float
    lines: list[OrderLine]
    status: str = "pending"
    status_since: date | None = None
    paid: bool = False
    invoiced: bool = False
    pay_due: date | None = None

    @property
    def total(self) -> float:
        return round(sum(line.gross() for line in self.lines) + self.shipping_fee, 2)


@dataclass
class PurchaseOrder:
    po_number: str
    supplier: str
    order_date: date
    expected_date: date
    lines: list[tuple[int, int, float]]  # product_id, qty, unit cost in supplier currency


@dataclass
class SimState:
    last_day: date | None = None
    customers: dict[int, Customer] = field(default_factory=dict)
    customer_ids: list[int] = field(default_factory=list)
    customer_cum_weights: list[float] = field(default_factory=list)
    emails_seen: dict[str, int] = field(default_factory=dict)
    products: dict[int, Product] = field(default_factory=dict)
    stock: dict[int, int] = field(default_factory=dict)
    on_order: dict[int, int] = field(default_factory=lambda: defaultdict(int))
    open_pos: list[PurchaseOrder] = field(default_factory=list)
    open_orders: dict[int, Order] = field(default_factory=dict)
    delivered_orders: dict[int, tuple[Order, date]] = field(default_factory=dict)
    fx: dict[str, float] = field(default_factory=lambda: dict(ref.FX_START))
    late_web_events: list[dict] = field(default_factory=list)
    delayed_ad_reports: list[dict] = field(default_factory=list)
    counters: dict[str, int] = field(
        default_factory=lambda: {
            "customer": 1,
            "product": 1,
            "order": 100_001,
            "order_item": 1,
            "return": 1,
            "po": 1,
            "movement": 1,
            "invoice": 1,
            "session": 1,
        }
    )

    def next_id(self, name: str) -> int:
        value = self.counters[name]
        self.counters[name] += 1
        return value


# --------------------------------------------------------------------------- #
# Batch container
# --------------------------------------------------------------------------- #


@dataclass
class Batch:
    rows: dict[tuple[str, str], list[dict]] = field(default_factory=lambda: defaultdict(list))

    def add(self, source: str, entity: str, row: dict) -> None:
        self.rows[(source, entity)].append(row)

    def extend(self, other: Batch) -> None:
        for key, rows in other.rows.items():
            self.rows[key].extend(rows)

    def counts(self) -> dict[str, int]:
        return {f"{s}.{e}": len(r) for (s, e), r in sorted(self.rows.items())}


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def poisson(rng: random.Random, lam: float) -> int:
    if lam <= 0:
        return 0
    if lam > 30:
        return max(0, round(rng.gauss(lam, math.sqrt(lam))))
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def at(day: date, rng: random.Random, start_h: int = 0, end_h: int = 24) -> datetime:
    """Random local (Europe/Budapest) wall-clock time on `day`."""
    return datetime.combine(day, time()) + timedelta(seconds=rng.randint(start_h * 3600, end_h * 3600 - 1))


def demand_multiplier(day: date) -> float:
    """Growth trend x seasonality x weekday pattern."""
    growth = 1 + 0.6 * (day - ref.HISTORY_START).days / 365
    season = {11: 1.5, 12: 1.75, 1: 0.8, 2: 0.85, 7: 0.9, 8: 0.9}.get(day.month, 1.0)
    if day.month == 11 and 24 <= day.day <= 30:  # Black Friday week
        season = 2.6
    weekday = [0.95, 0.95, 1.0, 1.0, 1.05, 1.15, 1.1][day.weekday()]
    return growth * season * weekday


def vat_rate(country: str, day: date) -> int:
    rates = {"HU": 27, "AT": 20, "DE": 19, "SK": 23, "CZ": 21, "PL": 23}
    if country == "RO":
        return 19 if day < date(2025, 8, 1) else 21
    return rates[country]


# --------------------------------------------------------------------------- #
# Simulator
# --------------------------------------------------------------------------- #


class Simulator:
    BASE_ORDERS_PER_DAY = 16

    def __init__(self, seed: int, state: SimState | None = None):
        self.seed = seed
        self.state = state or SimState()
        self._fakers: dict[str, Faker] = {}

    def faker(self, country: str, day: date) -> Faker:
        fk = self._fakers.get(country)
        if fk is None:
            fk = self._fakers[country] = Faker(ref.COUNTRIES[country][0])
        fk.seed_instance(f"{self.seed}-{country}-{day.isoformat()}")
        return fk

    # ------------------------------------------------------------------ #
    def step(self, day: date) -> Batch:
        s = self.state
        if s.last_day is not None and day != s.last_day + timedelta(days=1):
            raise ValueError(f"state is at {s.last_day}, cannot simulate {day}")
        rng = random.Random(f"{self.seed}-{day.isoformat()}")
        batch = Batch()
        demand = demand_multiplier(day)

        self._fx(day, rng, batch)
        if not s.products:
            self._bootstrap_company(day, rng, batch)
        self._catalogue(day, rng, batch)
        signups = self._customers(day, rng, batch, demand)
        self._receive_purchase_orders(day, rng, batch)
        self._progress_orders(day, rng, batch)
        new_orders = self._new_orders(day, rng, batch, demand, signups)
        self._web_sessions(day, rng, batch, demand, new_orders)
        self._marketing(day, rng, batch, demand)
        self._replenish(day, rng, batch, demand)
        if day.day == 1:
            self._stock_count(day, rng, batch)

        key = ("payments", "events")
        if key in batch.rows:
            batch.rows[key] = dq.duplicate_webhooks(batch.rows[key], rng)
        s.last_day = day
        return batch

    # ------------------------------------------------------------------ #
    # ECB reference rates (business days only)
    # ------------------------------------------------------------------ #
    def _fx(self, day: date, rng: random.Random, batch: Batch) -> None:
        s = self.state
        s.fx["HUF"] = round(s.fx["HUF"] * (1 + rng.gauss(0, 0.0035)) - 0.01, 2)
        s.fx["USD"] = round(s.fx["USD"] * (1 + rng.gauss(0, 0.004)) + 0.00015, 4)
        if day.weekday() < 5:
            for currency, rate in s.fx.items():
                batch.add("ecb", "fx_rates", {"date": day.isoformat(), "currency": currency, "rate": rate})

    # ------------------------------------------------------------------ #
    # Company bootstrap: suppliers, initial catalogue, opening stock
    # ------------------------------------------------------------------ #
    def _bootstrap_company(self, day: date, rng: random.Random, batch: Batch) -> None:
        for code, name, country, currency, terms, _ in ref.SUPPLIERS:
            batch.add(
                "erp",
                "suppliers",
                {
                    "szallito_kod": code,
                    "nev": name,
                    "orszag": country,
                    "penznem": currency,
                    "fizetesi_hatarido_nap": terms,
                    "rogzitve": dq.hu_date(day),
                },
            )
        for _ in range(150):
            product = self._new_product(day, rng, batch)
            qty = 40 + int(product.popularity * 25)
            self.state.stock[product.product_id] = qty
            self._movement(batch, rng, day, product, "LELT", qty, product.unit_cost_eur, note="NYITO")

    def _new_product(self, day: date, rng: random.Random, batch: Batch) -> Product:
        s = self.state
        category = rng.choice(list(ref.CATEGORIES))
        spellings, (low, high), warehouse = ref.CATEGORIES[category]
        pid = s.next_id("product")
        price = round(rng.uniform(low, high), 2)
        product = Product(
            product_id=pid,
            sku=f"WSP-{category[:3].upper()}-{pid:05d}",
            name=f"{rng.choice(ref.BRANDS)} {rng.choice(ref.ADJECTIVES)} {rng.choice(ref.NOUNS[category])}",
            category=category,
            category_raw=rng.choice(spellings),
            brand="",
            list_price_eur=price,
            unit_cost_eur=round(price * rng.uniform(0.48, 0.68), 2),
            weight_g=rng.randint(*ref.WEIGHT_RANGE_G[category]),
            warehouse=warehouse,
            supplier=ref.SUPPLIER_BY_CATEGORY[category],
            is_active=True,
            updated_at=datetime.combine(day, time()),
            popularity=min(random.Random(f"pop-{pid}").paretovariate(1.3), 30.0),
        )
        product.brand = product.name.split(" ")[0]
        s.products[pid] = product
        s.stock.setdefault(pid, 0)
        batch.add("shop", "products", dq.render_product(product, rng))
        return product

    def _catalogue(self, day: date, rng: random.Random, batch: Batch) -> None:
        s = self.state
        if rng.random() < 0.12:
            self._new_product(day, rng, batch)
        active = [p for p in s.products.values() if p.is_active and p.updated_at.date() < day]
        for product in rng.sample(active, k=min(len(active), poisson(rng, len(active) * 0.005))):
            if rng.random() < 0.08:
                product.is_active = False
            else:
                product.list_price_eur = round(product.list_price_eur * rng.choice([0.9, 0.95, 1.05, 1.1]), 2)
            product.updated_at = datetime.combine(day, time())
            batch.add("shop", "products", dq.render_product(product, rng))

    # ------------------------------------------------------------------ #
    # Customers
    # ------------------------------------------------------------------ #
    def _register(self, customer: Customer) -> None:
        s = self.state
        s.customers[customer.customer_id] = customer
        weight = min(random.Random(f"cust-{customer.customer_id}").paretovariate(1.4), 25.0)
        s.customer_ids.append(customer.customer_id)
        s.customer_cum_weights.append((s.customer_cum_weights[-1] if s.customer_cum_weights else 0) + weight)
        s.emails_seen.setdefault(customer.email, customer.customer_id)

    def _new_customer(self, day: date, rng: random.Random) -> Customer:
        s = self.state
        codes = list(ref.COUNTRIES)
        country = rng.choices(codes, weights=[ref.COUNTRIES[c][1] for c in codes])[0]
        fk = self.faker(country, day)
        first, last = fk.first_name(), fk.last_name()
        cid = s.next_id("customer")
        local = dq.ascii_fold(f"{first}.{last}").lower().replace(" ", "")
        domain = rng.choice(["gmail.com", "freemail.hu", "outlook.com", "gmx.net", "yahoo.com", "citromail.hu"])
        is_b2b = rng.random() < 0.05
        signup = at(day, rng, 6, 23)
        return Customer(
            customer_id=cid,
            first_name=first,
            last_name=last,
            email=f"{local}{cid % 97}@{domain}",
            country=country,
            phone=ref.PHONE_PREFIX[country]
            + str(rng.choice([20, 30, 70, 664, 151, 602, 721]))
            + f"{rng.randint(0, 9_999_999):07d}",
            postal_code=f"{rng.randint(1011, 9985)}" if country in ("HU", "AT") else f"{rng.randint(10000, 99999)}",
            city=fk.city(),
            street=fk.street_address(),
            birth_date=None
            if rng.random() < 0.15
            else date(rng.randint(1950, 2006), rng.randint(1, 12), rng.randint(1, 28)),
            is_b2b=is_b2b,
            vat_number=f"{rng.randint(10_000_000, 29_999_999)}-{rng.choice([1, 2])}-{rng.randint(2, 44):02d}"
            if is_b2b and country == "HU"
            else (f"{country}U{rng.randint(10_000_000, 99_999_999)}" if is_b2b else None),
            signup_at=signup,
            marketing_opt_in=rng.random() < 0.55,
            loyalty_tier="bronze",
            updated_at=signup,
        )

    def _customers(self, day: date, rng: random.Random, batch: Batch, demand: float) -> list[Customer]:
        s = self.state
        n_new = 250 if not s.customers else poisson(rng, 4.5 * demand)
        signups = []
        for _ in range(n_new):
            customer = self._new_customer(day, rng)
            # DQ03 fuzzy duplicates: ~2% are existing customers registering again
            if s.customers and rng.random() < 0.02:
                original = s.customers[rng.choice(s.customer_ids)]
                customer.first_name, customer.last_name = original.first_name, original.last_name
                customer.email, customer.country = original.email, original.country
                customer.phone = original.phone
                batch.add("shop", "customers", dq.render_customer(customer, rng, day, fuzzy_duplicate=True))
            else:
                batch.add("shop", "customers", dq.render_customer(customer, rng, day))
            self._register(customer)
            signups.append(customer)

        existing = [c for c in s.customer_ids if s.customers[c].updated_at.date() < day]
        for cid in rng.sample(existing, k=min(len(existing), poisson(rng, len(existing) * 0.0012))):
            customer = s.customers[cid]
            roll = rng.random()
            if roll < 0.5:
                fk = self.faker(customer.country, day)
                customer.city, customer.street = fk.city(), fk.street_address()
            elif roll < 0.8:
                customer.marketing_opt_in = not customer.marketing_opt_in
            else:
                customer.phone = customer.phone[:-4] + f"{rng.randint(0, 9999):04d}"
            customer.updated_at = at(day, rng, 6, 23)
            batch.add("shop", "customers", dq.render_customer(customer, rng, day))
        return signups

    # ------------------------------------------------------------------ #
    # Orders
    # ------------------------------------------------------------------ #
    def _new_orders(
        self, day: date, rng: random.Random, batch: Batch, demand: float, signups: list[Customer]
    ) -> list[Order]:
        s = self.state
        products = [p for p in s.products.values() if p.is_active]
        cum = list(accumulate(p.popularity for p in products))
        orders = []
        for _ in range(poisson(rng, self.BASE_ORDERS_PER_DAY * demand)):
            if signups and rng.random() < 0.3:
                customer = rng.choice(signups)
            else:
                idx = bisect_right(s.customer_cum_weights, rng.random() * s.customer_cum_weights[-1])
                customer = s.customers[s.customer_ids[min(idx, len(s.customer_ids) - 1)]]
            ordered_at = max(at(day, rng, 6, 24), customer.signup_at + timedelta(minutes=4))
            if ordered_at.date() != day:
                continue
            currency = "HUF" if customer.country == "HU" and rng.random() < 0.88 else "EUR"
            fx = s.fx["HUF"] if currency == "HUF" else 1.0
            lines = []
            for _ in range(rng.choices([1, 2, 3, 4], weights=[0.55, 0.27, 0.12, 0.06])[0]):
                product = products[bisect_right(cum, rng.random() * cum[-1])]
                price = round(product.list_price_eur * fx, -1) if currency == "HUF" else product.list_price_eur
                lines.append(
                    OrderLine(
                        order_item_id=s.next_id("order_item"),
                        product_id=product.product_id,
                        quantity=rng.choices([1, 2, 3, 5], weights=[0.8, 0.14, 0.04, 0.02])[0],
                        unit_price=price,
                        discount_pct=rng.choices([0, 5, 10, 20], weights=[0.72, 0.1, 0.12, 0.06])[0],
                    )
                )
            subtotal_eur = sum(line.gross() for line in lines) / fx
            fee_eur = 0.0 if subtotal_eur >= 50 else 4.99
            order = Order(
                order_id=s.next_id("order"),
                customer_id=customer.customer_id,
                ordered_at=ordered_at,
                currency=currency,
                payment_method=rng.choices(*ref.PAYMENT_METHODS)[0],
                sales_channel=rng.choices(*ref.SALES_CHANNELS)[0],
                shipping_country=customer.country,
                shipping_fee=round(fee_eur * fx, -1) if currency == "HUF" else fee_eur,
                lines=lines,
                status_since=day,
            )
            s.open_orders[order.order_id] = order
            orders.append(order)
            batch.add("shop", "orders", dq.render_order(order, ordered_at, rng))
            for line in lines:
                for row in dq.render_order_item(line, order, rng):
                    batch.add("shop", "order_items", row)

            if order.payment_method in ("card", "paypal"):
                if rng.random() < 0.03:  # first attempt declined
                    batch.add("payments", "events", dq.payment_event("charge.failed", order, ordered_at, rng))
                self._capture(order, ordered_at + timedelta(seconds=rng.randint(20, 400)), rng, batch)
            elif order.payment_method == "bank_transfer":
                order.pay_due = day + timedelta(days=rng.choice([1, 1, 2, 3, 9]))

        # DQ10: the payment provider also sends sandbox / test transactions
        if rng.random() < 0.15:
            batch.add("payments", "events", dq.test_payment_event(day, rng))
        return orders

    def _capture(self, order: Order, when: datetime, rng: random.Random, batch: Batch) -> None:
        order.paid = True
        batch.add("payments", "events", dq.payment_event("charge.succeeded", order, when, rng))
        if order.status == "pending":
            order.status, order.status_since = "paid", when.date()
            batch.add("shop", "orders", dq.render_order(order, when, rng))
        if not order.invoiced:
            self._invoice(order, when.date(), rng, batch)

    def _invoice(self, order: Order, day: date, rng: random.Random, batch: Batch, credit_note: bool = False) -> None:
        order.invoiced = True
        number = self.state.next_id("invoice")
        batch.add(
            "erp",
            "invoices",
            dq.render_invoice(order, day, number, vat_rate(order.shipping_country, day), credit_note, rng),
        )

    def _progress_orders(self, day: date, rng: random.Random, batch: Batch) -> None:
        s = self.state
        for order in list(s.open_orders.values()):
            event_time = at(day, rng, 7, 20)
            changed = False
            if order.status == "pending":
                if order.payment_method == "bank_transfer":
                    if order.pay_due and day >= order.pay_due:
                        if (day - order.status_since).days > 7:
                            order.status, changed = "cancelled", True
                        else:
                            self._capture(order, event_time, rng, batch)
                elif order.payment_method == "cash_on_delivery" and rng.random() < 0.85:
                    order.status, changed = "shipped", True
                    self._ship(order, day, rng, batch)
                elif rng.random() < 0.02:
                    order.status, changed = "cancelled", True
            elif order.status == "paid" and rng.random() < 0.7:
                order.status, changed = "shipped", True
                self._ship(order, day, rng, batch)
            elif order.status == "shipped" and rng.random() < 0.55:
                order.status, changed = "delivered", True
                if order.payment_method == "cash_on_delivery":
                    self._capture(order, event_time, rng, batch)

            if changed:
                order.status_since = day
                batch.add("shop", "orders", dq.render_order(order, event_time, rng))
                if order.status == "cancelled":
                    if order.paid:
                        batch.add("payments", "events", dq.payment_event("refund.succeeded", order, event_time, rng))
                    del s.open_orders[order.order_id]
                elif order.status == "delivered":
                    s.delivered_orders[order.order_id] = (order, day)
                    del s.open_orders[order.order_id]

        # returns within 14 days of delivery
        for order_id, (order, delivered_on) in list(s.delivered_orders.items()):
            if (day - delivered_on).days > 14:
                del s.delivered_orders[order_id]
            elif rng.random() < 0.004:
                self._return(order, day, rng, batch)
                del s.delivered_orders[order_id]

    def _ship(self, order: Order, day: date, rng: random.Random, batch: Batch) -> None:
        for line in order.lines:
            product = self.state.products[line.product_id]
            self.state.stock[product.product_id] -= line.quantity  # may go negative: oversell (DQ14)
            self._movement(batch, rng, day, product, "ELAD", line.quantity, None, reference=f"WS-{order.order_id}")

    def _return(self, order: Order, day: date, rng: random.Random, batch: Batch) -> None:
        when = at(day, rng, 8, 18)
        order.status = "returned"
        batch.add("shop", "orders", dq.render_order(order, when, rng))
        reason = rng.choice(ref.RETURN_REASONS)
        for line in order.lines:
            batch.add(
                "shop",
                "returns",
                {
                    "return_id": self.state.next_id("return"),
                    "order_id": order.order_id,
                    "order_item_id": line.order_item_id,
                    "quantity": line.quantity,
                    "reason_code": reason,
                    "requested_at": dq.local_ts(when),
                },
            )
            product = self.state.products[line.product_id]
            if reason != "DAMAGED":
                self.state.stock[product.product_id] += line.quantity
                self._movement(batch, rng, day, product, "VISSZ", line.quantity, None, reference=f"WS-{order.order_id}")
        batch.add("payments", "events", dq.payment_event("refund.succeeded", order, when + timedelta(hours=2), rng))
        self._invoice(order, day, rng, batch, credit_note=True)

    # ------------------------------------------------------------------ #
    # Inventory & purchasing (ERP)
    # ------------------------------------------------------------------ #
    def _movement(
        self,
        batch: Batch,
        rng: random.Random,
        day: date,
        product: Product,
        movement_type: str,
        qty: int,
        unit_cost_eur: float | None,
        reference: str = "",
        note: str = "",
    ) -> None:
        batch.add(
            "erp",
            "stock_movements",
            dq.render_movement(
                self.state.next_id("movement"), day, product, movement_type, qty, unit_cost_eur, reference, note, rng
            ),
        )

    def _replenish(self, day: date, rng: random.Random, batch: Batch, demand: float) -> None:
        s = self.state
        active = [p for p in s.products.values() if p.is_active]
        total_pop = sum(p.popularity for p in active)
        units_per_day = self.BASE_ORDERS_PER_DAY * demand * 1.75 * 1.3
        by_supplier: dict[str, list[tuple[Product, int]]] = defaultdict(list)
        for p in active:
            daily = units_per_day * p.popularity / total_pop
            reorder_point = daily * 14 + 2
            if s.stock[p.product_id] + s.on_order[p.product_id] < reorder_point:
                qty = max(5, math.ceil(daily * 30 / 5) * 5)
                by_supplier[p.supplier].append((p, qty))
        suppliers = {code: (cur, lead) for code, _, _, cur, _, lead in ref.SUPPLIERS}
        for supplier, items in sorted(by_supplier.items()):
            currency, (lo, hi) = suppliers[supplier]
            fx = s.fx["HUF"] if currency == "HUF" else 1.0
            po = PurchaseOrder(
                po_number=f"PO-{day.year}-{s.next_id('po'):05d}",
                supplier=supplier,
                order_date=day,
                expected_date=day + timedelta(days=rng.randint(lo, hi)),
                lines=[
                    (p.product_id, qty, round(p.unit_cost_eur * rng.uniform(0.97, 1.04) * fx, 2)) for p, qty in items
                ],
            )
            s.open_pos.append(po)
            for pid, qty, _ in po.lines:
                s.on_order[pid] += qty
            for row in dq.render_purchase_order(po, currency, "NYITOTT", day, s.products):
                batch.add("erp", row.pop("_entity"), row)

    def _receive_purchase_orders(self, day: date, rng: random.Random, batch: Batch) -> None:
        s = self.state
        suppliers = {code: cur for code, _, _, cur, _, _ in ref.SUPPLIERS}
        for po in [p for p in s.open_pos if p.expected_date <= day]:
            currency = suppliers[po.supplier]
            fx = s.fx["HUF"] if currency == "HUF" else 1.0
            for pid, qty, unit_cost in po.lines:
                product = s.products[pid]
                s.stock[pid] += qty
                s.on_order[pid] -= qty
                product.unit_cost_eur = round(unit_cost / fx, 2)
                self._movement(batch, rng, day, product, "BEV", qty, product.unit_cost_eur, reference=po.po_number)
            s.open_pos.remove(po)
            for row in dq.render_purchase_order(po, currency, "TELJESITVE", day, s.products, header_only=True):
                batch.add("erp", row.pop("_entity"), row)

    def _stock_count(self, day: date, rng: random.Random, batch: Batch) -> None:
        """Monthly stock count: shrinkage corrections for a few products."""
        s = self.state
        products = list(s.products.values())
        for product in rng.sample(products, k=max(1, len(products) // 25)):
            delta = -rng.randint(1, 3)
            s.stock[product.product_id] += delta
            self._movement(batch, rng, day, product, "LELT", delta, None, note="LELTAR")

    # ------------------------------------------------------------------ #
    # Web analytics
    # ------------------------------------------------------------------ #
    def _web_sessions(self, day: date, rng: random.Random, batch: Batch, demand: float, orders: list[Order]) -> None:
        s = self.state
        if day < ref.WEB_TRACKING_START:
            return
        events: list[dict] = list(s.late_web_events)  # DQ12: yesterday's late events arrive today
        s.late_web_events = []
        channels = {k: v for k, v in ref.CHANNELS.items() if k != "tiktok" or day >= ref.TIKTOK_START}
        names = list(channels)
        shares = [channels[c][0] for c in names]
        blended = sum(channels[c][0] * channels[c][1] for c in names) / sum(shares)

        tracked_orders = [o for o in orders if o.sales_channel != "phone"]
        products = [p for p in s.products.values() if p.is_active]
        for order in tracked_orders:
            conv_weights = [channels[c][0] * channels[c][1] for c in names]
            channel = rng.choices(names, weights=conv_weights)[0]
            start = order.ordered_at - timedelta(minutes=rng.randint(3, 40))
            events += dq.session_events(s.next_id("session"), channel, start, rng, products, order=order)

        n_sessions = poisson(rng, len(tracked_orders) / blended * (1 - blended)) if tracked_orders else 0
        for _ in range(n_sessions):
            channel = rng.choices(names, weights=shares)[0]
            events += dq.session_events(s.next_id("session"), channel, at(day, rng), rng, products)

        for event in events:
            if event.pop("_late", False) and rng.random() < 0.03:
                s.late_web_events.append(event)
                continue
            batch.add("web", "events", event)
            if rng.random() < 0.004:  # DQ02 duplicate delivery
                batch.add("web", "events", dict(event))

    # ------------------------------------------------------------------ #
    # Marketing
    # ------------------------------------------------------------------ #
    def _marketing(self, day: date, rng: random.Random, batch: Batch, demand: float) -> None:
        s = self.state
        daily_budget_eur = 140 * demand
        for report in s.delayed_ad_reports:  # DQ13: yesterday's missing report arrives a day late
            batch.add("marketing", "ad_reports", report)
        s.delayed_ad_reports = []

        for platform, (_channel, currency, share) in ref.AD_PLATFORMS.items():
            if platform == "tiktok_ads" and day < ref.TIKTOK_START:
                continue
            report = dq.ad_report(platform, currency, day, daily_budget_eur * share, s.fx, rng)
            if platform == "meta_ads" and rng.random() < 0.03:
                s.delayed_ad_reports.append(report)
            else:
                batch.add("marketing", "ad_reports", report)
        if day.day == 1:  # newsletter tool: fixed monthly subscription booked on the 1st, in HUF
            batch.add("marketing", "ad_reports", dq.newsletter_cost(day))
