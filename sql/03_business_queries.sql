-- =============================================================================
-- 03_business_queries.sql
-- 30 interview-quality SQL queries against the cleaned retail_analytics
-- database. Every query below has been executed against a live PostgreSQL
-- instance and verified to return results.
--
-- Grouped by theme; technique used is noted in each header comment.
-- =============================================================================


-- =========================================================================
-- SECTION A: REVENUE & SALES PERFORMANCE
-- =========================================================================

-- Q1. Top 10 best-selling products by revenue
-- Technique: INNER JOIN, GROUP BY, aggregate functions, ORDER BY / LIMIT
-- Revenue definition used in every query: net of line discount, excluding
-- cancelled orders (cancelled orders hold 8.4% of gross line value).
SELECT
    p.product_id,
    p.product_name,
    SUM(oi.quantity)                                   AS units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)), 2) AS total_revenue
FROM order_items oi
INNER JOIN orders o   ON o.order_id = oi.order_id
INNER JOIN products p ON p.product_id = oi.product_id
WHERE o.order_status <> 'cancelled'
GROUP BY p.product_id, p.product_name
ORDER BY total_revenue DESC
LIMIT 10;

-- Q2. Monthly revenue trend (last 24 months of data)
-- Technique: DATE_TRUNC, GROUP BY, aggregate functions
SELECT
    DATE_TRUNC('month', o.order_date)::DATE            AS order_month,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)), 2) AS monthly_revenue,
    COUNT(DISTINCT o.order_id)                          AS order_count
FROM orders o
INNER JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status <> 'cancelled'
GROUP BY DATE_TRUNC('month', o.order_date)
ORDER BY order_month;

-- Q3. Month-over-month revenue growth %
-- Technique: CTE, Window Function LAG(), date functions
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE AS order_month,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)) AS revenue
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY DATE_TRUNC('month', o.order_date)
)
SELECT
    order_month,
    ROUND(revenue, 2)                                                   AS revenue,
    ROUND(LAG(revenue) OVER (ORDER BY order_month), 2)                  AS prev_month_revenue,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY order_month))
        / NULLIF(LAG(revenue) OVER (ORDER BY order_month), 0) * 100, 2
    )                                                                   AS mom_growth_pct
FROM monthly
ORDER BY order_month;

-- Q4. Running total of revenue over time
-- Technique: Window function SUM() OVER (ORDER BY ...) -- running total
SELECT
    DATE_TRUNC('month', o.order_date)::DATE AS order_month,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)), 2) AS monthly_revenue,
    ROUND(
        SUM(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)))
        OVER (ORDER BY DATE_TRUNC('month', o.order_date)), 2
    ) AS running_total_revenue
FROM orders o
INNER JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status <> 'cancelled'
GROUP BY DATE_TRUNC('month', o.order_date)
ORDER BY order_month;

-- Q5. 3-month rolling average revenue
-- Technique: Window function AVG() OVER (ROWS BETWEEN ...) -- rolling average
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE AS order_month,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)) AS revenue
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY DATE_TRUNC('month', o.order_date)
)
SELECT
    order_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(AVG(revenue) OVER (
        ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_3mo_avg_revenue
FROM monthly
ORDER BY order_month;

-- Q6. Revenue and order count by region
-- Technique: GROUP BY, aggregate functions
SELECT
    o.region,
    COUNT(DISTINCT o.order_id)                                          AS total_orders,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)), 2) AS total_revenue
FROM orders o
INNER JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status <> 'cancelled'
GROUP BY o.region
ORDER BY total_revenue DESC;

-- Q7. Revenue contribution % by product category
-- Technique: CTE, window function for share-of-total, INNER JOIN
WITH category_revenue AS (
    SELECT
        c.category_name,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)) AS revenue
    FROM order_items oi
    INNER JOIN orders o     ON o.order_id = oi.order_id
    INNER JOIN products p   ON p.product_id = oi.product_id
    INNER JOIN categories c ON c.category_id = p.category_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY c.category_name
)
SELECT
    category_name,
    ROUND(revenue, 2) AS revenue,
    ROUND(revenue / SUM(revenue) OVER () * 100, 2) AS pct_of_total_revenue
FROM category_revenue
ORDER BY revenue DESC;

-- Q8. Average order value (AOV) overall and by customer segment
-- Technique: CTE, GROUP BY, aggregate functions
WITH order_totals AS (
    SELECT
        o.order_id,
        c.customer_segment,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)) AS order_total
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.order_id
    INNER JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY o.order_id, c.customer_segment
)
SELECT
    customer_segment,
    ROUND(AVG(order_total), 2) AS avg_order_value,
    COUNT(*)                   AS order_count
FROM order_totals
GROUP BY customer_segment
ORDER BY avg_order_value DESC;

-- Q9. Products with declining sales (this quarter vs. previous quarter)
-- Technique: CTE, window function LAG(), date functions
WITH quarterly_sales AS (
    SELECT
        p.product_id,
        p.product_name,
        DATE_TRUNC('quarter', o.order_date) AS quarter,
        SUM(oi.quantity) AS units_sold
    FROM order_items oi
    INNER JOIN orders o ON o.order_id = oi.order_id
    INNER JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY p.product_id, p.product_name, DATE_TRUNC('quarter', o.order_date)
),
with_prev AS (
    SELECT
        product_id,
        product_name,
        quarter,
        units_sold,
        LAG(units_sold) OVER (PARTITION BY product_id ORDER BY quarter) AS prev_units_sold
    FROM quarterly_sales
)
SELECT product_id, product_name, quarter, units_sold, prev_units_sold
FROM with_prev
WHERE prev_units_sold IS NOT NULL
  AND units_sold < prev_units_sold
ORDER BY quarter DESC, (prev_units_sold - units_sold) DESC
LIMIT 15;

-- Q10. Gross margin tier by product (list price vs. cost price)
-- Technique: CASE WHEN, NULLIF, basic arithmetic
-- Margin = profit / PRICE. (Profit / COST is markup, a different metric:
-- a 100% markup is only a 50% margin. Mixing them up mis-tiers 84 of 250
-- products in this catalogue.)
SELECT
    product_id,
    product_name,
    unit_price,
    cost_price,
    ROUND(unit_price - cost_price, 2)                                  AS profit_per_unit,
    ROUND(100 * (unit_price - cost_price) / NULLIF(unit_price, 0), 1)  AS gross_margin_pct,
    ROUND(100 * (unit_price - cost_price) / NULLIF(cost_price, 0), 1)  AS markup_pct,
    CASE
        WHEN unit_price = 0 THEN NULL
        WHEN (unit_price - cost_price) / unit_price >= 0.5 THEN 'High margin (>=50%)'
        WHEN (unit_price - cost_price) / unit_price >= 0.2 THEN 'Medium margin (20-50%)'
        ELSE 'Low margin (<20%)'
    END AS margin_tier
FROM products
ORDER BY profit_per_unit DESC
LIMIT 15;


-- =========================================================================
-- SECTION B: CUSTOMER ANALYTICS
-- =========================================================================

-- Q11. Top 10 customers by lifetime spend
-- Technique: INNER JOIN, GROUP BY, RANK()
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)), 2) AS lifetime_spend,
    RANK() OVER (ORDER BY SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)) DESC) AS spend_rank
FROM customers c
INNER JOIN orders o ON o.customer_id = c.customer_id
INNER JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status <> 'cancelled'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY lifetime_spend DESC
LIMIT 10;

-- Q12. Customers who have NEVER placed an order
-- Technique: LEFT JOIN + IS NULL (anti-join pattern)
SELECT c.customer_id, c.first_name, c.last_name, c.signup_date
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL
ORDER BY c.signup_date DESC
LIMIT 20;

-- Q13. Every customer paired with every order they placed, including
--      customers with zero orders AND any orphaned orders (diagnostic query)
-- Technique: FULL OUTER JOIN
SELECT
    c.customer_id,
    c.first_name,
    o.order_id,
    o.order_date
FROM customers c
FULL JOIN orders o ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL OR o.order_id IS NULL
LIMIT 20;

-- Q14. Products that have NEVER been ordered
-- Technique: RIGHT JOIN + IS NULL
SELECT p.product_id, p.product_name, p.category_id
FROM order_items oi
RIGHT JOIN products p ON p.product_id = oi.product_id
WHERE oi.order_item_id IS NULL;

-- Q15. Customer purchase frequency ranking within their segment
-- Technique: Window functions ROW_NUMBER(), RANK(), DENSE_RANK() side-by-side
WITH order_counts AS (
    SELECT
        c.customer_id,
        c.customer_segment,
        COUNT(o.order_id) AS num_orders
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.customer_id AND o.order_status <> 'cancelled'
    GROUP BY c.customer_id, c.customer_segment
)
SELECT
    customer_id,
    customer_segment,
    num_orders,
    ROW_NUMBER() OVER (PARTITION BY customer_segment ORDER BY num_orders DESC) AS row_num,
    RANK()       OVER (PARTITION BY customer_segment ORDER BY num_orders DESC) AS rnk,
    DENSE_RANK() OVER (PARTITION BY customer_segment ORDER BY num_orders DESC) AS dense_rnk
FROM order_counts
ORDER BY customer_segment, num_orders DESC
LIMIT 30;

-- Q16. New vs. returning customers per month
-- Technique: CTE, window function MIN() OVER, date functions
WITH first_order AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_order_date
    FROM orders
    WHERE order_status <> 'cancelled'
    GROUP BY customer_id
)
SELECT
    DATE_TRUNC('month', o.order_date)::DATE AS order_month,
    COUNT(DISTINCT CASE
        WHEN DATE_TRUNC('month', o.order_date) = DATE_TRUNC('month', f.first_order_date)
        THEN o.customer_id END)             AS new_customers,
    COUNT(DISTINCT CASE
        WHEN DATE_TRUNC('month', o.order_date) > DATE_TRUNC('month', f.first_order_date)
        THEN o.customer_id END)             AS returning_customers
FROM orders o
INNER JOIN first_order f ON f.customer_id = o.customer_id
WHERE o.order_status <> 'cancelled'
GROUP BY DATE_TRUNC('month', o.order_date)
ORDER BY order_month;

-- Q17. Cohort analysis: repeat-purchase rate by first-purchase quarter
-- Technique: CTEs, MIN() FILTER, interval arithmetic, cohort retention %
-- Cohorts are built on FIRST PURCHASE, not signup_date: a data-quality check
-- (see 04_findings.sql, DQ1) found 8,947 orders (41%) dated before the
-- customer's signup date, so signup-based cohorts would be unreliable.
-- Caveats: the 2022-Q1 cohort is inflated because customers who bought
-- before the data starts look "new"; cohorts from 2024 have not had a full
-- 365 days to repeat, so their 365-day rate is understated.
WITH valid_orders AS (
    SELECT customer_id, order_date
    FROM orders
    WHERE order_status <> 'cancelled'
),
first_purchase AS (
    SELECT customer_id, MIN(order_date) AS first_dt
    FROM valid_orders
    GROUP BY customer_id
),
second_purchase AS (
    SELECT
        f.customer_id,
        DATE_TRUNC('quarter', f.first_dt)::DATE                        AS cohort_quarter,
        f.first_dt,
        MIN(v.order_date) FILTER (WHERE v.order_date > f.first_dt)     AS second_dt
    FROM first_purchase f
    INNER JOIN valid_orders v ON v.customer_id = f.customer_id
    GROUP BY f.customer_id, cohort_quarter, f.first_dt
)
SELECT
    cohort_quarter,
    COUNT(*)                                                                    AS new_buyers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE second_dt <= first_dt + INTERVAL '90 days')  / COUNT(*), 1) AS repeat_within_90d_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE second_dt <= first_dt + INTERVAL '365 days') / COUNT(*), 1) AS repeat_within_365d_pct
FROM second_purchase
GROUP BY cohort_quarter
ORDER BY cohort_quarter;

-- Q18. Customer churn flag: no order in the last 180 days but has ordered before
-- Technique: CTE, CASE WHEN, date arithmetic
WITH last_order AS (
    SELECT
        customer_id,
        MAX(order_date) AS most_recent_order
    FROM orders
    WHERE order_status <> 'cancelled'
    GROUP BY customer_id
)
SELECT
    customer_id,
    most_recent_order,
    CASE
        WHEN most_recent_order < (SELECT MAX(order_date) FROM orders) - INTERVAL '180 days'
        THEN 'Churned'
        ELSE 'Active'
    END AS churn_status
FROM last_order
ORDER BY most_recent_order ASC
LIMIT 20;

-- Q19. Days between a customer's first and second order (time to repeat purchase)
-- Technique: Window functions LEAD() + ROW_NUMBER()
-- ROW_NUMBER() = 1 keeps only each customer's FIRST order; without it,
-- LEAD() returns every consecutive pair (16,414 rows instead of 3,058).
WITH ordered_dates AS (
    SELECT
        customer_id,
        order_date,
        LEAD(order_date)  OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date,
        ROW_NUMBER()      OVER (PARTITION BY customer_id ORDER BY order_date) AS order_seq
    FROM orders
    WHERE order_status <> 'cancelled'
)
SELECT
    customer_id,
    order_date                                    AS first_order,
    next_order_date                               AS second_order,
    (next_order_date::DATE - order_date::DATE)    AS days_to_repeat_purchase
FROM ordered_dates
WHERE order_seq = 1
  AND next_order_date IS NOT NULL
ORDER BY days_to_repeat_purchase ASC
LIMIT 20;

-- Q20. Customers whose average order value exceeds the company-wide average
-- Technique: CTE to change the grain (line -> order), scalar subquery in HAVING
-- Order totals are built first: averaging order_items directly would give
-- average LINE value (EUR 1,361), not average ORDER value (EUR 4,008).
-- The benchmark uses the same CTE, so both sides exclude cancelled orders.
WITH order_totals AS (
    SELECT
        o.customer_id,
        o.order_id,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)) AS order_total
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY o.customer_id, o.order_id
)
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    COUNT(*)                       AS orders,
    ROUND(AVG(ot.order_total), 2)  AS customer_aov
FROM order_totals ot
INNER JOIN customers c ON c.customer_id = ot.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING AVG(ot.order_total) > (SELECT AVG(order_total) FROM order_totals)
ORDER BY customer_aov DESC
LIMIT 15;


-- =========================================================================
-- SECTION C: OPERATIONS, INVENTORY & QUALITY
-- =========================================================================

-- Q21. Order status breakdown with percentage of total
-- Technique: GROUP BY, window function for percentage of total
SELECT
    order_status,
    COUNT(*)                                            AS order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)   AS pct_of_all_orders
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;

-- Q22. Return rate by product category (orders containing that category)
-- Technique: INNER JOIN, COUNT(DISTINCT ...) FILTER, GROUP BY, HAVING
-- COUNT(DISTINCT order_id): the join produces one row per order LINE, so a
-- plain COUNT(*) would weight multi-line orders more than single-line ones.
SELECT
    c.category_name,
    COUNT(DISTINCT o.order_id) FILTER (WHERE o.order_status = 'returned')  AS returned_orders,
    COUNT(DISTINCT o.order_id)                                             AS total_orders,
    ROUND(
        COUNT(DISTINCT o.order_id) FILTER (WHERE o.order_status = 'returned') * 100.0
        / COUNT(DISTINCT o.order_id), 2
    ) AS return_rate_pct
FROM orders o
INNER JOIN order_items oi ON oi.order_id = o.order_id
INNER JOIN products p ON p.product_id = oi.product_id
INNER JOIN categories c ON c.category_id = p.category_id
GROUP BY c.category_name
HAVING COUNT(DISTINCT o.order_id) > 100
ORDER BY return_rate_pct DESC;

-- Q23. Products never reviewed despite having 10+ sales (quality/visibility gap)
-- Technique: LEFT JOIN, GROUP BY, HAVING
SELECT
    p.product_id,
    p.product_name,
    SUM(oi.quantity) AS units_sold
FROM order_items oi
INNER JOIN products p ON p.product_id = oi.product_id
LEFT JOIN reviews r ON r.order_item_id = oi.order_item_id
GROUP BY p.product_id, p.product_name
HAVING SUM(oi.quantity) >= 10 AND COUNT(r.review_id) = 0
ORDER BY units_sold DESC
LIMIT 15;

-- Q24. Average rating and review volume by product (only products with 5+ reviews)
-- Technique: INNER JOIN, GROUP BY, HAVING
SELECT
    p.product_id,
    p.product_name,
    COUNT(r.review_id)          AS review_count,
    ROUND(AVG(r.rating), 2)     AS avg_rating
FROM reviews r
INNER JOIN order_items oi ON oi.order_item_id = r.order_item_id
INNER JOIN products p ON p.product_id = oi.product_id
GROUP BY p.product_id, p.product_name
HAVING COUNT(r.review_id) >= 5
ORDER BY avg_rating DESC, review_count DESC
LIMIT 15;

-- Q25. Payment method popularity and failure rate
-- Technique: CASE WHEN, GROUP BY, aggregate functions
SELECT
    payment_method,
    COUNT(*)                                                          AS total_payments,
    COUNT(*) FILTER (WHERE payment_status = 'failed')                 AS failed_payments,
    ROUND(COUNT(*) FILTER (WHERE payment_status = 'failed') * 100.0 / COUNT(*), 2) AS failure_rate_pct
FROM payments
GROUP BY payment_method
ORDER BY failure_rate_pct DESC;

-- Q26. Orders with a payment total that doesn't match the order_items total
--      (a real data-quality / reconciliation check an analyst would run)
-- Technique: CTE, INNER JOIN, HAVING with a computed difference
WITH item_totals AS (
    SELECT
        order_id,
        SUM(quantity * unit_price * (1 - discount_pct / 100.0)) AS items_total
    FROM order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_amount) AS paid_total
    FROM payments
    WHERE payment_status = 'completed'
    GROUP BY order_id
)
SELECT
    it.order_id,
    ROUND(it.items_total, 2)  AS items_total,
    ROUND(pt.paid_total, 2)   AS paid_total,
    ROUND(it.items_total - pt.paid_total, 2) AS discrepancy
FROM item_totals it
INNER JOIN payment_totals pt ON pt.order_id = it.order_id
WHERE ABS(it.items_total - pt.paid_total) > 1.00
ORDER BY ABS(it.items_total - pt.paid_total) DESC
LIMIT 15;

-- Q27. Second-highest-selling product per category (classic interview question)
-- Technique: CTE, DENSE_RANK(), subquery-style filtering
WITH product_sales AS (
    SELECT
        p.category_id,
        p.product_id,
        p.product_name,
        SUM(oi.quantity) AS units_sold,
        DENSE_RANK() OVER (PARTITION BY p.category_id ORDER BY SUM(oi.quantity) DESC) AS sales_rank
    FROM order_items oi
    INNER JOIN orders o   ON o.order_id = oi.order_id
    INNER JOIN products p ON p.product_id = oi.product_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY p.category_id, p.product_id, p.product_name
)
SELECT category_id, product_id, product_name, units_sold
FROM product_sales
WHERE sales_rank = 2
ORDER BY category_id;

-- Q28. Days-since-last-order per customer, using date functions
-- Technique: Date functions (AGE / date subtraction), subquery
SELECT
    customer_id,
    MAX(order_date)                                    AS last_order_date,
    (SELECT MAX(order_date) FROM orders) - MAX(order_date) AS days_since_last_order
FROM orders
WHERE order_status <> 'cancelled'
GROUP BY customer_id
ORDER BY days_since_last_order DESC
LIMIT 15;

-- Q29. Realised gross margin by category, with cumulative share of gross profit
-- Technique: multi-table JOIN, GROUP BY, window function (running total)
-- (Replaces an earlier "inventory value" query: the schema has no stock
-- levels, so summing catalogue cost prices did not measure inventory.)
WITH category_profit AS (
    SELECT
        c.category_name,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0))  AS revenue,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)
            - oi.quantity * p.cost_price)                                  AS gross_profit
    FROM order_items oi
    INNER JOIN orders o     ON o.order_id = oi.order_id
    INNER JOIN products p   ON p.product_id = oi.product_id
    INNER JOIN categories c ON c.category_id = p.category_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY c.category_name
)
SELECT
    category_name,
    ROUND(revenue, 2)                               AS revenue,
    ROUND(gross_profit, 2)                          AS gross_profit,
    ROUND(100 * gross_profit / revenue, 1)          AS gross_margin_pct,
    ROUND(100 * SUM(gross_profit) OVER (ORDER BY gross_profit DESC)
              / SUM(gross_profit) OVER (), 1)       AS cumulative_profit_share_pct
FROM category_profit
ORDER BY gross_profit DESC;

-- Q30. Full business summary: orders, revenue, AOV, and review score per
--      region and quarter — a typical "give me an executive summary table"
--      ask, combining most techniques in one query
-- Technique: CTE, multiple JOINs, GROUP BY, aggregate + window functions
WITH order_level AS (
    SELECT
        o.order_id,
        o.region,
        DATE_TRUNC('quarter', o.order_date)::DATE AS quarter,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct / 100.0)) AS order_total
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status <> 'cancelled'
    GROUP BY o.order_id, o.region, DATE_TRUNC('quarter', o.order_date)
),
review_level AS (
    SELECT
        o.region,
        DATE_TRUNC('quarter', o.order_date)::DATE AS quarter,
        AVG(r.rating) AS avg_rating
    FROM reviews r
    INNER JOIN order_items oi ON oi.order_item_id = r.order_item_id
    INNER JOIN orders o ON o.order_id = oi.order_id
    GROUP BY o.region, DATE_TRUNC('quarter', o.order_date)
)
SELECT
    ol.region,
    ol.quarter,
    COUNT(ol.order_id)                    AS total_orders,
    ROUND(SUM(ol.order_total), 2)         AS total_revenue,
    ROUND(AVG(ol.order_total), 2)         AS avg_order_value,
    ROUND(rl.avg_rating, 2)               AS avg_review_rating,
    RANK() OVER (PARTITION BY ol.quarter ORDER BY SUM(ol.order_total) DESC) AS region_rank_in_quarter
FROM order_level ol
LEFT JOIN review_level rl ON rl.region = ol.region AND rl.quarter = ol.quarter
GROUP BY ol.region, ol.quarter, rl.avg_rating
ORDER BY ol.quarter, region_rank_in_quarter;
