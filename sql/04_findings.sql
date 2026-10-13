-- =============================================================================
-- 04_findings.sql
-- The queries behind every number in the README "Findings" section.
-- Run after 02_data_cleaning.sql. Revenue = net of line discount, excluding
-- cancelled orders. Reference date for recency = last order in the data
-- (2024-12-31), because the dataset is historical.
-- =============================================================================

-- Shared line-level view: one row per order line, with revenue and cost.
CREATE OR REPLACE VIEW v_order_lines AS
SELECT
    oi.order_item_id,
    oi.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.region,
    p.category_id,
    oi.quantity,
    oi.discount_pct,
    oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)  AS net_revenue,
    oi.quantity * p.cost_price                                   AS line_cost
FROM order_items oi
INNER JOIN orders o   ON o.order_id = oi.order_id
INNER JOIN products p ON p.product_id = oi.product_id;


-- -----------------------------------------------------------------------------
-- F1. Revenue, orders, AOV and gross margin by year: is the business growing?
-- -----------------------------------------------------------------------------
SELECT
    EXTRACT(YEAR FROM order_date)::INT                                   AS year,
    COUNT(DISTINCT order_id)                                             AS orders,
    COUNT(DISTINCT customer_id)                                          AS active_customers,
    ROUND(SUM(net_revenue))                                              AS revenue,
    ROUND(SUM(net_revenue) / COUNT(DISTINCT order_id), 2)                AS avg_order_value,
    ROUND(100 * (SUM(net_revenue) - SUM(line_cost)) / SUM(net_revenue), 1) AS gross_margin_pct
FROM v_order_lines
WHERE order_status <> 'cancelled'
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------------------
-- F2. Customer concentration: share of revenue by customer decile
-- -----------------------------------------------------------------------------
WITH customer_spend AS (
    SELECT customer_id, SUM(net_revenue) AS spend
    FROM v_order_lines
    WHERE order_status <> 'cancelled'
    GROUP BY customer_id
),
deciles AS (
    SELECT spend, NTILE(10) OVER (ORDER BY spend DESC) AS decile
    FROM customer_spend
)
SELECT
    decile,
    COUNT(*)                                               AS customers,
    ROUND(100 * SUM(spend) / SUM(SUM(spend)) OVER (), 1)   AS pct_of_revenue
FROM deciles
GROUP BY decile
ORDER BY decile;


-- -----------------------------------------------------------------------------
-- F3. Lapsed customers (no order in the last 180 days), top 10% vs. the rest
-- -----------------------------------------------------------------------------
WITH customer_stats AS (
    SELECT customer_id, SUM(net_revenue) AS spend, MAX(order_date) AS last_order
    FROM v_order_lines
    WHERE order_status <> 'cancelled'
    GROUP BY customer_id
),
ranked AS (
    SELECT *, NTILE(10) OVER (ORDER BY spend DESC) AS decile
    FROM customer_stats
)
SELECT
    CASE WHEN decile = 1 THEN 'Top 10% by spend' ELSE 'Other 90%' END     AS customer_group,
    COUNT(*)                                                               AS customers,
    COUNT(*) FILTER (WHERE last_order < TIMESTAMP '2024-12-31' - INTERVAL '180 days') AS lapsed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE last_order < TIMESTAMP '2024-12-31' - INTERVAL '180 days')
          / COUNT(*), 1)                                                   AS lapsed_pct
FROM ranked
GROUP BY 1
UNION ALL
SELECT 'All buyers', COUNT(*),
       COUNT(*) FILTER (WHERE last_order < TIMESTAMP '2024-12-31' - INTERVAL '180 days'),
       ROUND(100.0 * COUNT(*) FILTER (WHERE last_order < TIMESTAMP '2024-12-31' - INTERVAL '180 days')
             / COUNT(*), 1)
FROM customer_stats;


-- -----------------------------------------------------------------------------
-- F4. Discounts: do they buy volume, and what do they cost in margin?
-- (Observational: discounts were not randomly assigned, so this shows an
-- association, not the causal effect of a discount.)
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN discount_pct = 0   THEN '1. No discount'
        WHEN discount_pct <= 10 THEN '2. 1-10%'
        ELSE                         '3. 11-20%'
    END                                                                     AS discount_band,
    COUNT(*)                                                                AS order_lines,
    ROUND(AVG(quantity), 2)                                                 AS avg_units_per_line,
    ROUND(100 * (SUM(net_revenue) - SUM(line_cost)) / SUM(net_revenue), 1)  AS gross_margin_pct,
    ROUND(SUM(net_revenue))                                                 AS revenue
FROM v_order_lines
WHERE order_status <> 'cancelled'
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------------------------------
-- F5. Category gross margin (see also Q29)
-- -----------------------------------------------------------------------------
SELECT
    c.category_name,
    ROUND(SUM(v.net_revenue))                                                     AS revenue,
    ROUND(100 * SUM(v.net_revenue) / SUM(SUM(v.net_revenue)) OVER (), 1)          AS revenue_share_pct,
    ROUND(100 * (SUM(v.net_revenue) - SUM(v.line_cost)) / SUM(v.net_revenue), 1)  AS gross_margin_pct
FROM v_order_lines v
INNER JOIN categories c ON c.category_id = v.category_id
WHERE v.order_status <> 'cancelled'
GROUP BY c.category_name
ORDER BY gross_margin_pct;


-- -----------------------------------------------------------------------------
-- F6. Payment reconciliation: delivered orders with no completed payment,
--     and orders where completed payments are short of the order total
-- -----------------------------------------------------------------------------
SELECT
    o.order_status,
    COUNT(*) AS orders_without_completed_payment
FROM orders o
WHERE NOT EXISTS (
    SELECT 1 FROM payments p
    WHERE p.order_id = o.order_id AND p.payment_status = 'completed'
)
GROUP BY o.order_status
ORDER BY 2 DESC;

WITH item_totals AS (
    SELECT order_id, SUM(quantity * unit_price * (1 - discount_pct / 100.0)) AS items_total
    FROM order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT order_id, SUM(payment_amount) AS paid_total
    FROM payments
    WHERE payment_status = 'completed'
    GROUP BY order_id
)
SELECT
    COUNT(*)                                                        AS orders_compared,
    COUNT(*) FILTER (WHERE it.items_total - pt.paid_total > 1)      AS underpaid_orders,
    COUNT(*) FILTER (WHERE pt.paid_total - it.items_total > 1)      AS overpaid_orders,
    ROUND(SUM(it.items_total - pt.paid_total)
          FILTER (WHERE it.items_total - pt.paid_total > 1))        AS total_shortfall
FROM item_totals it
INNER JOIN payment_totals pt ON pt.order_id = it.order_id;


-- -----------------------------------------------------------------------------
-- F7. Payment failure rate by method (counts feed a chi-square test, see README)
-- -----------------------------------------------------------------------------
SELECT
    payment_method,
    COUNT(*) FILTER (WHERE payment_status = 'failed')    AS failed,
    COUNT(*) FILTER (WHERE payment_status <> 'failed')   AS not_failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE payment_status = 'failed') / COUNT(*), 2) AS failure_rate_pct
FROM payments
GROUP BY payment_method
ORDER BY failure_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- F8. Region and segment: is there a meaningful difference? (Answer: no)
-- -----------------------------------------------------------------------------
SELECT
    region,
    COUNT(DISTINCT order_id)                                AS orders,
    ROUND(SUM(net_revenue))                                 AS revenue,
    ROUND(SUM(net_revenue) / COUNT(DISTINCT order_id), 2)   AS avg_order_value
FROM v_order_lines
WHERE order_status <> 'cancelled'
GROUP BY region
ORDER BY revenue DESC;

SELECT
    c.customer_segment,
    COUNT(DISTINCT v.customer_id)                              AS customers,
    ROUND(SUM(v.net_revenue))                                  AS revenue,
    ROUND(SUM(v.net_revenue) / COUNT(DISTINCT v.order_id), 2)  AS avg_order_value
FROM v_order_lines v
INNER JOIN customers c ON c.customer_id = v.customer_id
WHERE v.order_status <> 'cancelled'
GROUP BY c.customer_segment
ORDER BY revenue DESC;


-- =============================================================================
-- DATA-QUALITY CHECKS on the cleaned tables
-- =============================================================================

-- DQ1. Orders dated before the customer signed up (should be 0)
SELECT COUNT(*) AS orders_before_signup,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders), 1) AS pct_of_orders
FROM orders o
INNER JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_date::DATE < c.signup_date;

-- DQ2. Registered customers who never placed a (non-cancelled) order
SELECT COUNT(*) AS customers_never_purchased
FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id AND o.order_status <> 'cancelled'
);
