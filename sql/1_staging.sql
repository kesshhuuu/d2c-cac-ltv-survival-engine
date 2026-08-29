-- ============================================================================
-- Step 1: Staging Layer (sql/1_staging.sql)
-- Standardizes types, sanitizes currency strings, and removes test anomalies.
-- ============================================================================

CREATE OR REPLACE VIEW stg_customers AS
SELECT
    CAST(customer_id AS VARCHAR) AS customer_id,
    CAST(signup_timestamp AS TIMESTAMP) AS signup_timestamp,
    DATE_TRUNC('month', CAST(signup_timestamp AS TIMESTAMP))::DATE AS signup_month,
    LOWER(TRIM(CAST(acquisition_channel_id AS VARCHAR))) AS acquisition_channel_id,
    UPPER(TRIM(CAST(country_code AS VARCHAR))) AS country_code
FROM raw_customers
WHERE customer_id IS NOT NULL;

CREATE OR REPLACE VIEW stg_orders AS
SELECT
    CAST(order_id AS VARCHAR) AS order_id,
    CAST(customer_id AS VARCHAR) AS customer_id,
    CAST(order_timestamp AS TIMESTAMP) AS order_timestamp,
    DATE_TRUNC('month', CAST(order_timestamp AS TIMESTAMP))::DATE AS order_month,
    CAST(gross_order_value AS NUMERIC(12,2)) AS gross_order_value,
    CAST(discount_amount AS NUMERIC(12,2)) AS discount_amount,
    CAST(cogs_amount AS NUMERIC(12,2)) AS cogs_amount,
    CAST(refund_amount AS NUMERIC(12,2)) AS refund_amount,
    LOWER(TRIM(CAST(order_status AS VARCHAR))) AS order_status
FROM raw_orders
WHERE order_id IS NOT NULL 
  AND gross_order_value > 0;

CREATE OR REPLACE VIEW stg_channel_spend AS
SELECT
    CAST(spend_month AS DATE) AS spend_month,
    LOWER(TRIM(CAST(acquisition_channel_id AS VARCHAR))) AS acquisition_channel_id,
    CAST(marketing_spend AS NUMERIC(12,2)) AS marketing_spend
FROM raw_channel_spend
WHERE spend_month IS NOT NULL;