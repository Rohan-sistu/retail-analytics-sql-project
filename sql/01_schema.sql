-- =============================================================================
-- 01_schema.sql
-- Final, clean, production-style schema for the Retail Analytics project.
-- Run this AFTER 00_staging_schema.sql exists but BEFORE loading data.
-- =============================================================================

DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

CREATE TABLE categories (
    category_id     SMALLINT PRIMARY KEY,
    category_name   VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE customers (
    customer_id      INTEGER PRIMARY KEY,
    first_name       VARCHAR(100) NOT NULL,
    last_name        VARCHAR(100) NOT NULL,
    email            VARCHAR(255),
    city             VARCHAR(100),
    region           VARCHAR(50),
    country          VARCHAR(100),
    signup_date      DATE NOT NULL,
    customer_segment VARCHAR(50) NOT NULL
);

CREATE TABLE products (
    product_id     INTEGER PRIMARY KEY,
    product_name   VARCHAR(255) NOT NULL,
    category_id    SMALLINT NOT NULL REFERENCES categories(category_id),
    brand          VARCHAR(150),
    unit_price     NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    cost_price     NUMERIC(10,2) NOT NULL CHECK (cost_price >= 0)
);

CREATE TABLE orders (
    order_id       INTEGER PRIMARY KEY,
    customer_id    INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date     TIMESTAMP NOT NULL,
    order_status   VARCHAR(20) NOT NULL
                   CHECK (order_status IN ('completed','shipped','processing','cancelled','returned')),
    region         VARCHAR(50)
);

CREATE TABLE order_items (
    order_item_id  INTEGER PRIMARY KEY,
    order_id       INTEGER NOT NULL REFERENCES orders(order_id),
    product_id     INTEGER NOT NULL REFERENCES products(product_id),
    quantity       INTEGER NOT NULL CHECK (quantity > 0),
    unit_price     NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_pct   NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 100)
);

CREATE TABLE payments (
    payment_id      INTEGER PRIMARY KEY,
    order_id        INTEGER NOT NULL REFERENCES orders(order_id),
    payment_method  VARCHAR(30) NOT NULL,
    payment_amount  NUMERIC(10,2) NOT NULL,
    payment_date    TIMESTAMP,
    payment_status  VARCHAR(20) NOT NULL
                    CHECK (payment_status IN ('completed','failed','refunded'))
);

CREATE TABLE reviews (
    review_id       INTEGER PRIMARY KEY,
    order_item_id   INTEGER NOT NULL REFERENCES order_items(order_item_id),
    customer_id     INTEGER NOT NULL REFERENCES customers(customer_id),
    rating          SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_date     DATE NOT NULL,
    review_text     TEXT
);

-- ---------------------------------------------------------------------------
-- Indexes to support the query workload (joins, date filters, lookups)
-- ---------------------------------------------------------------------------
CREATE INDEX idx_orders_customer_id   ON orders(customer_id);
CREATE INDEX idx_orders_order_date    ON orders(order_date);
CREATE INDEX idx_orders_status        ON orders(order_status);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product  ON order_items(product_id);
CREATE INDEX idx_payments_order_id    ON payments(order_id);
CREATE INDEX idx_reviews_item_id      ON reviews(order_item_id);
CREATE INDEX idx_products_category    ON products(category_id);
