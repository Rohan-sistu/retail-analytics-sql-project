-- =============================================================================
-- 02_data_cleaning.sql
-- Transforms the messy staging_* tables into the clean, typed, constrained
-- production tables defined in 01_schema.sql.
--
-- Data quality issues handled here (all genuinely present in the raw data,
-- not decorative):
--   1. Exact duplicate rows            -> ROW_NUMBER() dedup, keep first
--   2. Inconsistent casing (emails,
--      order_status)                   -> LOWER() + TRIM()
--   3. Empty-string "nulls"            -> NULLIF(..., '')
--   4. Sign errors (negative prices/
--      quantities from entry mistakes) -> ABS()
--   5. Missing required fields
--      (e.g. blank order_date)         -> filtered out, logged to console
--   6. Out-of-range values
--      (ratings outside 1-5)           -> filtered out (unrecoverable)
--   7. Orphaned foreign keys (child
--      row references a parent row
--      that was dropped/never existed) -> filtered via NOT EXISTS
--
-- Run order matters: parents before children (categories -> customers ->
-- products -> orders -> order_items -> payments -> reviews) so the orphan
-- checks below always have a populated parent table to check against.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. categories  (no known issues in source, but dedupe defensively)
-- -----------------------------------------------------------------------------
INSERT INTO categories (category_id, category_name)
SELECT category_id::SMALLINT, TRIM(category_name)
FROM (
    SELECT DISTINCT ON (category_id::SMALLINT)
        category_id, category_name
    FROM staging_categories
    ORDER BY category_id::SMALLINT
) d;

-- -----------------------------------------------------------------------------
-- 2. customers
--    - trims whitespace, lowercases + nulls-out blank emails
--    - keeps first occurrence of each duplicated customer_id
-- -----------------------------------------------------------------------------
INSERT INTO customers (customer_id, first_name, last_name, email, city, region,
                        country, signup_date, customer_segment)
SELECT customer_id, first_name, last_name, email, city, region, country,
       signup_date, customer_segment
FROM (
    SELECT
        customer_id::INTEGER              AS customer_id,
        TRIM(first_name)                  AS first_name,
        TRIM(last_name)                   AS last_name,
        NULLIF(LOWER(TRIM(email)), '')    AS email,
        NULLIF(TRIM(city), '')            AS city,
        region,
        country,
        signup_date::DATE                 AS signup_date,
        customer_segment,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id::INTEGER ORDER BY ctid
        ) AS rn
    FROM staging_customers
) dedup
WHERE rn = 1;

-- -----------------------------------------------------------------------------
-- 3. products
--    - a small number of unit_price values were entered as negative
--      (point-of-sale sign error). We ASSUME the magnitude is correct and
--      the sign is the only error, so we take ABS(). This is a judgment
--      call worth calling out explicitly in an interview.
-- -----------------------------------------------------------------------------
INSERT INTO products (product_id, product_name, category_id, brand, unit_price, cost_price)
SELECT product_id, product_name, category_id, brand, unit_price, cost_price
FROM (
    SELECT
        product_id::INTEGER      AS product_id,
        TRIM(product_name)       AS product_name,
        category_id::SMALLINT    AS category_id,
        brand,
        ABS(unit_price::NUMERIC) AS unit_price,
        ABS(cost_price::NUMERIC) AS cost_price,
        ROW_NUMBER() OVER (
            PARTITION BY product_id::INTEGER ORDER BY ctid
        ) AS rn
    FROM staging_products
) dedup
WHERE rn = 1;

-- -----------------------------------------------------------------------------
-- 4. orders
--    - order_status casing normalized to lowercase
--    - rows with a blank order_date are dropped: order_date is required
--      for virtually every downstream analysis (monthly revenue, cohorts,
--      etc.), so a row with no date has no analytical value and cannot be
--      safely defaulted without inventing a fact.
-- -----------------------------------------------------------------------------
INSERT INTO orders (order_id, customer_id, order_date, order_status, region)
SELECT order_id, customer_id, order_date, order_status, region
FROM (
    SELECT
        order_id::INTEGER                    AS order_id,
        customer_id::INTEGER                 AS customer_id,
        NULLIF(TRIM(order_date), '')::TIMESTAMP AS order_date,
        LOWER(TRIM(order_status))            AS order_status,
        region,
        ROW_NUMBER() OVER (
            PARTITION BY order_id::INTEGER ORDER BY ctid
        ) AS rn
    FROM staging_orders
) dedup
WHERE rn = 1
  AND order_date IS NOT NULL
  AND EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = dedup.customer_id);

-- -----------------------------------------------------------------------------
-- 5. order_items
--    - a handful of quantities were entered as negative (scanner/entry
--      error at checkout); ABS() corrects the sign
--    - unit_price here is captured at time of sale from the products table,
--      so it inherited the same sign-entry errors found in products (a
--      classic case of one upstream bug propagating into multiple tables) -
--      same ABS() fix applies, same assumption applies
--    - rows pointing at an order_id or product_id that didn't survive
--      cleaning above are dropped (orphaned foreign keys)
-- -----------------------------------------------------------------------------
INSERT INTO order_items (order_item_id, order_id, product_id, quantity, unit_price, discount_pct)
SELECT order_item_id, order_id, product_id, quantity, unit_price, discount_pct
FROM (
    SELECT
        order_item_id::INTEGER    AS order_item_id,
        order_id::INTEGER         AS order_id,
        product_id::INTEGER       AS product_id,
        ABS(quantity::INTEGER)    AS quantity,
        ABS(unit_price::NUMERIC)  AS unit_price,
        discount_pct::NUMERIC     AS discount_pct,
        ROW_NUMBER() OVER (
            PARTITION BY order_item_id::INTEGER ORDER BY ctid
        ) AS rn
    FROM staging_order_items
) dedup
WHERE rn = 1
  AND EXISTS (SELECT 1 FROM orders o WHERE o.order_id = dedup.order_id)
  AND EXISTS (SELECT 1 FROM products p WHERE p.product_id = dedup.product_id);

-- -----------------------------------------------------------------------------
-- 6. payments
--    - orphaned order_id references dropped
-- -----------------------------------------------------------------------------
INSERT INTO payments (payment_id, order_id, payment_method, payment_amount,
                       payment_date, payment_status)
SELECT payment_id, order_id, payment_method, payment_amount, payment_date, payment_status
FROM (
    SELECT
        payment_id::INTEGER          AS payment_id,
        order_id::INTEGER            AS order_id,
        payment_method,
        payment_amount::NUMERIC      AS payment_amount,
        NULLIF(TRIM(payment_date), '')::TIMESTAMP AS payment_date,
        payment_status,
        ROW_NUMBER() OVER (
            PARTITION BY payment_id::INTEGER ORDER BY ctid
        ) AS rn
    FROM staging_payments
) dedup
WHERE rn = 1
  AND EXISTS (SELECT 1 FROM orders o WHERE o.order_id = dedup.order_id);

-- -----------------------------------------------------------------------------
-- 7. reviews
--    - ratings outside the valid 1-5 range are dropped as unrecoverable
--      (no safe way to infer the intended value)
--    - orphaned order_item_id / customer_id references dropped
-- -----------------------------------------------------------------------------
INSERT INTO reviews (review_id, order_item_id, customer_id, rating, review_date, review_text)
SELECT review_id, order_item_id, customer_id, rating, review_date, review_text
FROM (
    SELECT
        review_id::INTEGER      AS review_id,
        order_item_id::INTEGER  AS order_item_id,
        customer_id::INTEGER    AS customer_id,
        rating::SMALLINT        AS rating,
        review_date::DATE       AS review_date,
        NULLIF(TRIM(review_text), '') AS review_text,
        ROW_NUMBER() OVER (
            PARTITION BY review_id::INTEGER ORDER BY ctid
        ) AS rn
    FROM staging_reviews
) dedup
WHERE rn = 1
  AND rating BETWEEN 1 AND 5
  AND EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_item_id = dedup.order_item_id)
  AND EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = dedup.customer_id);

-- -----------------------------------------------------------------------------
-- Sanity check: report how many rows were dropped at each stage
-- -----------------------------------------------------------------------------
SELECT
    'customers'   AS table_name, (SELECT COUNT(*) FROM staging_customers)   AS raw_rows, (SELECT COUNT(*) FROM customers)   AS clean_rows
UNION ALL
SELECT 'products',    (SELECT COUNT(*) FROM staging_products),    (SELECT COUNT(*) FROM products)
UNION ALL
SELECT 'orders',      (SELECT COUNT(*) FROM staging_orders),      (SELECT COUNT(*) FROM orders)
UNION ALL
SELECT 'order_items', (SELECT COUNT(*) FROM staging_order_items), (SELECT COUNT(*) FROM order_items)
UNION ALL
SELECT 'payments',    (SELECT COUNT(*) FROM staging_payments),    (SELECT COUNT(*) FROM payments)
UNION ALL
SELECT 'reviews',     (SELECT COUNT(*) FROM staging_reviews),     (SELECT COUNT(*) FROM reviews);
