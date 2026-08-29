-- ============================================================================
-- Step 4: Statistical Survival Analysis Dataset (sql/4_marts_survival_input.sql)
-- Prepares customer duration (t), churn event (E), and baseline M0 covariates.
-- ============================================================================

CREATE OR REPLACE VIEW mart_customer_survival_input AS
WITH customer_aggregates AS (
    SELECT
        ca.customer_id,
        ca.acquisition_channel_id,
        ca.is_paid_acquisition,
        ca.cohort_month,
        ca.first_order_timestamp,
        MAX(o.order_timestamp) AS last_order_timestamp,
        COUNT(o.order_id) AS lifetime_orders_count,
        SUM(o.gross_contribution_margin) AS lifetime_margin_total,
        -- Global study observation cutoff: 2025-12-31 23:59:59
        TIMESTAMP '2025-12-31 23:59:59' AS study_cutoff_timestamp
    FROM int_customer_cohort_assignments ca
    INNER JOIN int_order_transactions_sequenced o 
        ON ca.customer_id = o.customer_id
    GROUP BY 
        ca.customer_id, 
        ca.acquisition_channel_id, 
        ca.is_paid_acquisition, 
        ca.cohort_month, 
        ca.first_order_timestamp
),
first_order_covariates AS (
    SELECT
        customer_id,
        gross_order_value AS m0_gross_order_value,
        ROUND((discount_amount / gross_order_value), 4) AS m0_discount_share
    FROM int_order_transactions_sequenced
    WHERE customer_order_sequence = 1
)
SELECT
    ca.customer_id,
    ca.acquisition_channel_id,
    ca.is_paid_acquisition,
    ca.cohort_month,
    foc.m0_gross_order_value,
    foc.m0_discount_share,
    ca.lifetime_orders_count,
    ca.lifetime_margin_total,
    -- Duration t (in months) from first order to last order (or cutoff if 1-time buyer)
    ROUND(
        CAST(
            EXTRACT(EPOCH FROM (
                CASE 
                    WHEN ca.lifetime_orders_count > 1 THEN ca.last_order_timestamp 
                    ELSE ca.first_order_timestamp + INTERVAL '30 days'
                END - ca.first_order_timestamp
            )) / 86400.0 / 30.4375 
        AS NUMERIC), 
    2) AS observed_duration_t,
    -- Event Churn E: 1 if inactive > 90 days before study cutoff, 0 if right-censored (active)
    CASE 
        WHEN (ca.study_cutoff_timestamp - ca.last_order_timestamp) > INTERVAL '90 days' THEN 1 
        ELSE 0 
    END AS event_churned_e
FROM customer_aggregates ca
INNER JOIN first_order_covariates foc 
    ON ca.customer_id = foc.customer_id;