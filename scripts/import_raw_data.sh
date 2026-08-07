#!/usr/bin/env bash
# =============================================================================
# import_raw_data.sh
# Loads the raw (messy) CSVs into the staging tables.
# Usage: ./import_raw_data.sh [database_name]
# =============================================================================
set -euo pipefail

DB_NAME="${1:-retail_analytics}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW_DIR="$PROJECT_ROOT/data/raw"

echo "Building schema in database: $DB_NAME"
psql -d "$DB_NAME" -f "$PROJECT_ROOT/sql/00_staging_schema.sql"
psql -d "$DB_NAME" -f "$PROJECT_ROOT/sql/01_schema.sql"

echo "Loading raw CSVs into staging tables..."
psql -d "$DB_NAME" <<SQL
\copy staging_categories   FROM '$RAW_DIR/categories_raw.csv'   WITH (FORMAT csv, HEADER true)
\copy staging_customers    FROM '$RAW_DIR/customers_raw.csv'    WITH (FORMAT csv, HEADER true)
\copy staging_products     FROM '$RAW_DIR/products_raw.csv'     WITH (FORMAT csv, HEADER true)
\copy staging_orders       FROM '$RAW_DIR/orders_raw.csv'       WITH (FORMAT csv, HEADER true)
\copy staging_order_items  FROM '$RAW_DIR/order_items_raw.csv'  WITH (FORMAT csv, HEADER true)
\copy staging_payments     FROM '$RAW_DIR/payments_raw.csv'     WITH (FORMAT csv, HEADER true)
\copy staging_reviews      FROM '$RAW_DIR/reviews_raw.csv'      WITH (FORMAT csv, HEADER true)
SQL

echo "Running data cleaning (staging -> clean tables)..."
psql -d "$DB_NAME" -f "$PROJECT_ROOT/sql/02_data_cleaning.sql"

echo "Done. Row counts in clean tables:"
psql -d "$DB_NAME" -c "
SELECT 'customers' AS table_name, COUNT(*) FROM customers
UNION ALL SELECT 'categories', COUNT(*) FROM categories
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'payments', COUNT(*) FROM payments
UNION ALL SELECT 'reviews', COUNT(*) FROM reviews
ORDER BY table_name;
"
