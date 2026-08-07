"""
generate_data.py
Generates a realistic, referentially-correct e-commerce dataset with
INTENTIONAL data quality issues (duplicates, nulls, bad casing, invalid
values) so that the cleaning.sql script in this project solves a real
problem instead of a decorative one.

Output: CSV files in data/raw/ (messy, "as received from source systems")
Run:    python3 generate_data.py
"""

import csv
import random
from datetime import datetime, timedelta
from pathlib import Path

from faker import Faker

fake = Faker()
Faker.seed(42)
random.seed(42)

OUT = Path(__file__).resolve().parent.parent / "data" / "raw"
OUT.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Config / scale
# ---------------------------------------------------------------------------
N_CUSTOMERS = 4000
N_CATEGORIES = 12
N_PRODUCTS = 250
N_ORDERS = 22000
START_DATE = datetime(2022, 1, 1)
END_DATE = datetime(2024, 12, 31)

REGIONS = ["North", "South", "East", "West", "Central"]
COUNTRIES = ["Germany", "France", "Netherlands", "Poland", "Spain", "Italy", "Austria"]
ORDER_STATUSES = ["completed", "shipped", "processing", "cancelled", "returned"]
ORDER_STATUS_WEIGHTS = [0.55, 0.20, 0.10, 0.08, 0.07]
PAYMENT_METHODS = ["credit_card", "paypal", "bank_transfer", "debit_card", "gift_card"]
CATEGORY_NAMES = [
    "Electronics", "Home & Kitchen", "Clothing", "Sports & Outdoors",
    "Books", "Toys & Games", "Beauty & Personal Care", "Office Supplies",
    "Garden & Patio", "Automotive", "Pet Supplies", "Health & Household",
]


def random_date(start, end):
    delta = end - start
    return start + timedelta(days=random.randint(0, delta.days),
                              seconds=random.randint(0, 86399))


def messy_case(text, p=0.15):
    """Randomly mangle casing to simulate inconsistent source systems."""
    if random.random() < p:
        r = random.random()
        if r < 0.33:
            return text.upper()
        elif r < 0.66:
            return text.lower()
    return text


def with_whitespace(text, p=0.08):
    if random.random() < p:
        return f"  {text}  "
    return text


# ---------------------------------------------------------------------------
# 1. Categories
# ---------------------------------------------------------------------------
categories = []
for i, name in enumerate(CATEGORY_NAMES[:N_CATEGORIES], start=1):
    categories.append({"category_id": i, "category_name": name})

# ---------------------------------------------------------------------------
# 2. Products
# ---------------------------------------------------------------------------
products = []
for pid in range(1, N_PRODUCTS + 1):
    cat = random.choice(categories)
    cost = round(random.uniform(3, 400), 2)
    margin = random.uniform(1.2, 2.8)
    price = round(cost * margin, 2)
    # inject ~0.5% invalid prices (data entry errors)
    if random.random() < 0.005:
        price = round(random.uniform(-50, 0), 2)
    products.append({
        "product_id": pid,
        "product_name": with_whitespace(fake.unique.catch_phrase()),
        "category_id": cat["category_id"],
        "brand": fake.company(),
        "unit_price": price,
        "cost_price": cost,
    })

# inject duplicate product rows (~1%)
dup_products = random.sample(products, k=int(N_PRODUCTS * 0.01) or 1)
products_out = products + dup_products

# Reserve a slice of the catalog as genuine "dead stock" - newly listed or
# discontinued products that never appear in order_items. Without this,
# at 65k+ order_items across only ~250 products, statistically every
# product sells at least once, which makes the "products never ordered"
# query (RIGHT JOIN demo) return an empty (but technically correct) result.
NEVER_ORDERED_IDS = set(p["product_id"] for p in products[-15:])
ORDERABLE_PRODUCTS = [p for p in products if p["product_id"] not in NEVER_ORDERED_IDS]

# Reserve a second slice: products that sell reasonably well but are
# deliberately excluded from reviews (e.g. review-request emails never
# fired for this category) - keeps the "sold but never reviewed" query
# meaningful too.
NEVER_REVIEWED_IDS = set(p["product_id"] for p in products[-30:-15])

# ---------------------------------------------------------------------------
# 3. Customers
# ---------------------------------------------------------------------------
customers = []
for cid in range(1, N_CUSTOMERS + 1):
    first = fake.first_name()
    last = fake.last_name()
    email = f"{first}.{last}{random.randint(1,999)}@{fake.free_email_domain()}"
    signup = random_date(START_DATE - timedelta(days=200), END_DATE)
    row = {
        "customer_id": cid,
        "first_name": first,
        "last_name": last,
        "email": email if random.random() > 0.02 else "",  # ~2% missing email
        "city": with_whitespace(fake.city()) if random.random() > 0.01 else "",
        "region": random.choice(REGIONS),
        "country": random.choice(COUNTRIES),
        "signup_date": signup.strftime("%Y-%m-%d"),
        "customer_segment": random.choice(["Consumer", "Business", "Enterprise"]),
    }
    # inject casing inconsistency in email
    if row["email"] and random.random() < 0.1:
        row["email"] = messy_case(row["email"], p=1.0)
    customers.append(row)

dup_customers = random.sample(customers, k=int(N_CUSTOMERS * 0.02) or 1)
customers_out = customers + dup_customers

# ---------------------------------------------------------------------------
# 4. Orders  (skewed so ~15% of customers generate ~50% of orders -> realistic
#    for cohort / retention / top-customer analysis)
# ---------------------------------------------------------------------------
power_customers = random.sample(customers, k=int(N_CUSTOMERS * 0.15))
orders = []
oid = 1
while oid <= N_ORDERS:
    cust = random.choice(power_customers) if random.random() < 0.5 else random.choice(customers)
    order_date = random_date(START_DATE, END_DATE)
    status = random.choices(ORDER_STATUSES, weights=ORDER_STATUS_WEIGHTS)[0]
    row = {
        "order_id": oid,
        "customer_id": cust["customer_id"],
        "order_date": order_date.strftime("%Y-%m-%d %H:%M:%S"),
        "order_status": messy_case(status),
        "region": random.choice(REGIONS),
    }
    # ~0.3% missing order_date (data entry failure upstream)
    if random.random() < 0.003:
        row["order_date"] = ""
    orders.append(row)
    oid += 1

dup_orders = random.sample(orders, k=int(N_ORDERS * 0.01) or 1)
orders_out = orders + dup_orders

# ---------------------------------------------------------------------------
# 5. Order items (the main fact table -> target 50,000+ rows)
# ---------------------------------------------------------------------------
order_items = []
item_id = 1
for o in orders:
    n_items = random.choices([1, 2, 3, 4, 5, 6], weights=[0.20, 0.24, 0.22, 0.16, 0.11, 0.07])[0]
    chosen_products = random.sample(ORDERABLE_PRODUCTS, k=min(n_items, len(ORDERABLE_PRODUCTS)))
    for prod in chosen_products:
        qty = random.randint(1, 6)
        discount = random.choices([0, 5, 10, 15, 20], weights=[0.55, 0.15, 0.15, 0.10, 0.05])[0]
        row = {
            "order_item_id": item_id,
            "order_id": o["order_id"],
            "product_id": prod["product_id"],
            "quantity": qty,
            "unit_price": prod["unit_price"],
            "discount_pct": discount,
        }
        # inject ~0.3% negative/invalid quantity (scanner / entry error)
        if random.random() < 0.003:
            row["quantity"] = -abs(qty)
        order_items.append(row)
        item_id += 1

dup_items = random.sample(order_items, k=int(len(order_items) * 0.015) or 1)
order_items_out = order_items + dup_items

# ---------------------------------------------------------------------------
# 6. Payments (mostly 1 per order, ~5% split into 2)
# ---------------------------------------------------------------------------
payments = []
pid = 1
for o in orders:
    if o["order_status"].strip().lower() == "cancelled" and random.random() < 0.7:
        continue  # many cancelled orders never got a completed payment
    order_total = sum(
        i["quantity"] * i["unit_price"] * (1 - i["discount_pct"] / 100)
        for i in order_items if i["order_id"] == o["order_id"]
    )
    if random.random() < 0.05:
        # split payment
        part1 = round(order_total * random.uniform(0.3, 0.7), 2)
        part2 = round(order_total - part1, 2)
        amounts = [part1, part2]
    else:
        amounts = [round(order_total, 2)]
    for amt in amounts:
        row = {
            "payment_id": pid,
            "order_id": o["order_id"],
            "payment_method": random.choice(PAYMENT_METHODS),
            "payment_amount": amt,
            "payment_date": o["order_date"],
            "payment_status": random.choices(
                ["completed", "failed", "refunded"], weights=[0.90, 0.05, 0.05]
            )[0],
        }
        payments.append(row)
        pid += 1

dup_payments = random.sample(payments, k=int(len(payments) * 0.01) or 1)
payments_out = payments + dup_payments

# ---------------------------------------------------------------------------
# 7. Reviews (~45% of delivered order_items get reviewed)
# ---------------------------------------------------------------------------
reviews = []
rid = 1
reviewable = [
    i for i in order_items
    if i["quantity"] > 0 and i["product_id"] not in NEVER_REVIEWED_IDS
]
for item in random.sample(reviewable, k=int(len(reviewable) * 0.45)):
    order = next(o for o in orders if o["order_id"] == item["order_id"])
    order_dt = order["order_date"]
    if not order_dt:
        continue
    review_date = datetime.strptime(order_dt, "%Y-%m-%d %H:%M:%S") + timedelta(
        days=random.randint(1, 21)
    )
    rating = random.choices([1, 2, 3, 4, 5], weights=[0.05, 0.07, 0.13, 0.35, 0.40])[0]
    # inject ~0.3% out-of-range ratings (bad client-side validation)
    if random.random() < 0.003:
        rating = random.choice([0, 6, -1])
    reviews.append({
        "review_id": rid,
        "order_item_id": item["order_item_id"],
        "customer_id": order["customer_id"],
        "rating": rating,
        "review_date": review_date.strftime("%Y-%m-%d"),
        "review_text": fake.sentence(nb_words=12) if random.random() > 0.1 else "",
    })
    rid += 1

dup_reviews = random.sample(reviews, k=int(len(reviews) * 0.01) or 1)
reviews_out = reviews + dup_reviews


# ---------------------------------------------------------------------------
# Write CSVs
# ---------------------------------------------------------------------------
def write_csv(filename, rows, fieldnames):
    with open(OUT / filename, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print(f"  wrote {filename}: {len(rows)} rows")


print("Generating raw (intentionally messy) CSVs...")
write_csv("categories_raw.csv", categories, ["category_id", "category_name"])
write_csv("products_raw.csv", products_out,
          ["product_id", "product_name", "category_id", "brand", "unit_price", "cost_price"])
write_csv("customers_raw.csv", customers_out,
          ["customer_id", "first_name", "last_name", "email", "city", "region",
           "country", "signup_date", "customer_segment"])
write_csv("orders_raw.csv", orders_out,
          ["order_id", "customer_id", "order_date", "order_status", "region"])
write_csv("order_items_raw.csv", order_items_out,
          ["order_item_id", "order_id", "product_id", "quantity", "unit_price", "discount_pct"])
write_csv("payments_raw.csv", payments_out,
          ["payment_id", "order_id", "payment_method", "payment_amount",
           "payment_date", "payment_status"])
write_csv("reviews_raw.csv", reviews_out,
          ["review_id", "order_item_id", "customer_id", "rating", "review_date", "review_text"])

print("\nDone. Row counts (including intentional dirty duplicates):")
print(f"  customers:   {len(customers_out)}")
print(f"  products:    {len(products_out)}")
print(f"  orders:      {len(orders_out)}")
print(f"  order_items: {len(order_items_out)}")
print(f"  payments:    {len(payments_out)}")
print(f"  reviews:     {len(reviews_out)}")
