-- =============================================================================
-- 00_staging_schema.sql
-- "Landing zone" tables that mirror the raw CSVs exactly, with loose/TEXT
-- typing and no constraints. This mimics how data actually arrives from
-- source systems (messy) before any cleaning happens.
-- =============================================================================

DROP TABLE IF EXISTS staging_reviews;
DROP TABLE IF EXISTS staging_payments;
DROP TABLE IF EXISTS staging_order_items;
DROP TABLE IF EXISTS staging_orders;
DROP TABLE IF EXISTS staging_products;
DROP TABLE IF EXISTS staging_customers;
DROP TABLE IF EXISTS staging_categories;

CREATE TABLE staging_categories (
    category_id     TEXT,
    category_name   TEXT
);

CREATE TABLE staging_customers (
    customer_id      TEXT,
    first_name       TEXT,
    last_name        TEXT,
    email            TEXT,
    city             TEXT,
    region           TEXT,
    country          TEXT,
    signup_date      TEXT,
    customer_segment TEXT
);

CREATE TABLE staging_products (
    product_id     TEXT,
    product_name   TEXT,
    category_id    TEXT,
    brand          TEXT,
    unit_price     TEXT,
    cost_price     TEXT
);

CREATE TABLE staging_orders (
    order_id       TEXT,
    customer_id    TEXT,
    order_date     TEXT,
    order_status   TEXT,
    region         TEXT
);

CREATE TABLE staging_order_items (
    order_item_id  TEXT,
    order_id       TEXT,
    product_id     TEXT,
    quantity       TEXT,
    unit_price     TEXT,
    discount_pct   TEXT
);

CREATE TABLE staging_payments (
    payment_id      TEXT,
    order_id        TEXT,
    payment_method  TEXT,
    payment_amount  TEXT,
    payment_date    TEXT,
    payment_status  TEXT
);

CREATE TABLE staging_reviews (
    review_id       TEXT,
    order_item_id   TEXT,
    customer_id     TEXT,
    rating          TEXT,
    review_date     TEXT,
    review_text     TEXT
);
