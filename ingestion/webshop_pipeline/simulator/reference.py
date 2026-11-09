"""Static reference data and tuning knobs for the WebShop Pro simulation."""

from __future__ import annotations

from datetime import date

HISTORY_START = date(2025, 1, 1)
WEB_TRACKING_START = date(2025, 6, 1)  # the analytics tag went live mid-2025
TIKTOK_START = date(2025, 9, 1)
SCHEMA_DRIFT_DATE = date(2026, 3, 1)  # shop export: phone -> phone_number, + loyalty_tier

# country code -> (faker locale, customer share, accepted aliases seen in the shop export)
COUNTRIES = {
    "HU": ("hu_HU", 0.46, ["HU", "hu", "Hungary", "Magyarország", "HUN"]),
    "AT": ("de_AT", 0.12, ["AT", "at", "Austria", "Österreich", "AUT"]),
    "DE": ("de_DE", 0.13, ["DE", "de", "Germany", "Deutschland", "DEU"]),
    "SK": ("sk_SK", 0.09, ["SK", "sk", "Slovakia", "Szlovákia", "SVK"]),
    "CZ": ("cs_CZ", 0.08, ["CZ", "cz", "Czechia", "Czech Republic", "CZE"]),
    "RO": ("ro_RO", 0.07, ["RO", "ro", "Romania", "Románia", "ROU"]),
    "PL": ("pl_PL", 0.05, ["PL", "pl", "Poland", "Lengyelország", "POL"]),
}
PHONE_PREFIX = {"HU": "36", "AT": "43", "DE": "49", "SK": "421", "CZ": "420", "RO": "40", "PL": "48"}

# canonical category -> (raw spellings, list price range EUR, warehouse)
CATEGORIES = {
    "Electronics": (["Electronics", "electronics", " ELECTRONICS", "Elektronika"], (25, 700), "BUD-01"),
    "Home & Kitchen": (["Home & Kitchen", "home and kitchen", "Home&Kitchen", "Otthon"], (8, 220), "BUD-01"),
    "Books": (["Books", "books ", "Könyv"], (6, 45), "DEB-01"),
    "Sports & Outdoors": (["Sports & Outdoors", "sports", "Sport"], (10, 350), "DEB-01"),
    "Beauty": (["Beauty", "beauty & care", "BEAUTY", "Szépség"], (5, 90), "DEB-01"),
    "Toys & Games": (["Toys & Games", "toys", "Játék"], (7, 120), "BUD-01"),
}
WEIGHT_RANGE_G = {
    "Electronics": (150, 4000),
    "Home & Kitchen": (200, 6000),
    "Books": (150, 1200),
    "Sports & Outdoors": (200, 9000),
    "Beauty": (50, 600),
    "Toys & Games": (100, 2500),
}

SUPPLIERS = [
    # code, name, country, currency, payment terms, lead time days (min, max)
    ("SUP-001", "Pannon Elektronika Kft.", "HU", "HUF", 30, (4, 9)),
    ("SUP-002", "Donau Haushalt GmbH", "AT", "EUR", 45, (6, 12)),
    ("SUP-003", "Tisza Könyvkereskedés Zrt.", "HU", "HUF", 15, (3, 6)),
    ("SUP-004", "Karpaty Sport s.r.o.", "SK", "EUR", 30, (7, 14)),
    ("SUP-005", "Vela Cosmetics Sp. z o.o.", "PL", "EUR", 30, (6, 11)),
    ("SUP-006", "Mátra Játékgyártó Kft.", "HU", "HUF", 30, (5, 10)),
]
SUPPLIER_BY_CATEGORY = {
    "Electronics": "SUP-001",
    "Home & Kitchen": "SUP-002",
    "Books": "SUP-003",
    "Sports & Outdoors": "SUP-004",
    "Beauty": "SUP-005",
    "Toys & Games": "SUP-006",
}

BRANDS = ["Nordline", "Danubio", "Kestrel", "Vela", "Orbis", "Tamarack", "Lumio", "Pannon"]
ADJECTIVES = ["Classic", "Pro", "Mini", "Eco", "Max", "Smart", "Lite", "Plus", "Air", "Duo"]
NOUNS = {
    "Electronics": ["Headphones", "Speaker", "Charger", "Smartwatch", "Keyboard", "Webcam"],
    "Home & Kitchen": ["Kettle", "Blender", "Pan Set", "Lamp", "Knife Block", "Toaster"],
    "Books": ["Cookbook", "Novel", "Travel Guide", "Atlas", "Workbook", "Biography"],
    "Sports & Outdoors": ["Yoga Mat", "Backpack", "Tent", "Water Bottle", "Dumbbell Set", "Bike Light"],
    "Beauty": ["Face Cream", "Shampoo", "Serum", "Lip Balm", "Hair Dryer", "Perfume"],
    "Toys & Games": ["Puzzle", "Board Game", "Building Set", "Plush Bear", "RC Car", "Card Game"],
}

PAYMENT_METHODS = (["card", "paypal", "bank_transfer", "cash_on_delivery"], [0.6, 0.18, 0.12, 0.10])
SALES_CHANNELS = (["web", "app", "phone"], [0.72, 0.23, 0.05])
RETURN_REASONS = ["DAMAGED", "WRONG_ITEM", "NOT_AS_DESCRIBED", "CHANGED_MIND", "TOO_LATE"]

# marketing / web: channel -> (share of sessions, conversion rate, utm variants, medium)
CHANNELS = {
    "organic_search": (0.30, 0.035, [("google", "organic"), ("bing", "organic")]),
    "direct": (0.22, 0.050, [(None, None)]),
    "paid_search": (0.20, 0.030, [("google", "cpc"), ("Google", "cpc"), ("google", "CPC"), ("adwords", "cpc")]),
    "paid_social": (
        0.13,
        0.020,
        [
            ("facebook", "paid_social"),
            ("Facebook", "paid_social"),
            ("fb", "paid_social"),
            ("instagram", "paid_social"),
            ("meta", "paidsocial"),
        ],
    ),
    "tiktok": (0.05, 0.012, [("tiktok", "paid_social"), ("TikTok", "paid_social"), ("tt", "paid")]),
    "email": (0.08, 0.060, [("newsletter", "email"), ("Newsletter", "email"), ("mailchimp", "email")]),
}
AD_PLATFORMS = {
    # platform -> (channel, account currency, share of the paid budget)
    "google_ads": ("paid_search", "EUR", 0.50),
    "meta_ads": ("paid_social", "USD", 0.38),
    "tiktok_ads": ("tiktok", "USD", 0.12),
}

# opening FX rates (units per 1 EUR), random-walked daily
FX_START = {"HUF": 405.0, "USD": 1.04}

DEVICE_MIX = (["mobile", "desktop", "tablet"], [0.62, 0.32, 0.06])
