-- ============================================================================
-- Step 2: Intermediate Layer (sql/2_intermediate.sql)
-- Sequences orders, assigns acquisition cohorts, and calculates channel CAC.
-- ============================================================================

-- A. Customer First Touch & Cohort Assignment
CREATE OR REPLACE VIEW int_customer_cohort_assignments AS
WITH customer_first_order AS (
    SELECT
        customer_id,
        MIN(order_timestamp) AS first_order_timestamp,
        DATE_TRUNC('month', MIN(order_timestamp))::DATE AS cohort_month
    FROM stg_orders
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.acquisition_channel_id,
    CASE 
        WHEN c.acquisition_channel_id IN ('meta_ads', 'google_ads') THEN TRUE 
        ELSE FALSE 
    END AS is_paid_acquisition,
    c.country_code,
    c.signup_timestamp,
    co.first_order_timestamp,
    co.cohort_month
FROM stg_customers c
INNER JOIN customer_first_order co 
    ON c.customer_id = co.customer_id;

-- B. Order Level Financial Mechanics & Sequence Indexing
CREATE OR REPLACE VIEW int_order_transactions_sequenced AS
SELECT
    o.order_id,
    o.customer_id,
    ca.cohort_month,
    o.order_month,
    ca.acquisition_channel_id,
    ca.is_paid_acquisition,
    o.order_timestamp,
    -- Cohort Month Index: Number of elapsed calendar months since acquisition
    CAST(
        (EXTRACT(YEAR FROM o.order_month) - EXTRACT(YEAR FROM ca.cohort_month)) * 12 +
        (EXTRACT(MONTH FROM o.order_month) - EXTRACT(MONTH FROM ca.cohort_month))
    AS INT) AS cohort_month_index,
    -- Intra-customer order sequence
    ROW_NUMBER() OVER (
        PARTITION BY o.customer_id 
        ORDER BY o.order_timestamp ASC
    ) AS customer_order_sequence,
    -- Days between orders
    COALESCE(
        EXTRACT(DAY FROM o.order_timestamp - LAG(o.order_timestamp) OVER (
            PARTITION BY o.customer_id 
            ORDER BY o.order_timestamp ASC
        )), 0
    ) AS days_since_prior_order,
    -- Unit Economic Net Revenue & Contribution Margin
    o.gross_order_value,
    o.discount_amount,
    o.refund_amount,
    o.cogs_amount,
    (o.gross_order_value - o.discount_amount - o.refund_amount) AS net_order_revenue,
    (o.gross_order_value - o.discount_amount - o.refund_amount - o.cogs_amount) AS gross_contribution_margin
FROM stg_orders o
INNER JOIN int_customer_cohort_assignments ca 
    ON o.customer_id = ca.customer_id;

-- C. Monthly Channel CAC Calculation
CREATE OR REPLACE VIEW int_monthly_channel_cac AS
WITH cohort_acquisitions AS (
    SELECT
        cohort_month,
        acquisition_channel_id,
        COUNT(DISTINCT customer_id) AS acquired_customers_count
    FROM int_customer_cohort_assignments
    GROUP BY cohort_month, acquisition_channel_id
)
SELECT
    ca.cohort_month,
    ca.acquisition_channel_id,
    ca.acquired_customers_count,
    COALESCE(s.marketing_spend, 0.00) AS total_marketing_spend,
    CASE 
        WHEN ca.acquired_customers_count > 0 
        THEN ROUND(COALESCE(s.marketing_spend, 0.00) / ca.acquired_customers_count, 2)
        ELSE 0.00 
    END AS channel_cac
FROM cohort_acquisitions ca
LEFT JOIN stg_channel_spend s 
    ON ca.cohort_month = s.spend_month 
   AND ca.acquisition_channel_id = s.acquisition_channel_id;