-- ============================================================================
-- Step 3: Production Cohort Payback Matrix (sql/3_marts_cohort_payback.sql)
-- Evaluates retention decay, cumulative margin LTV, and CAC recovery velocity.
-- ============================================================================

CREATE OR REPLACE VIEW mart_cohort_retention_payback AS
WITH cohort_baseline_sizes AS (
    SELECT
        cohort_month,
        acquisition_channel_id,
        COUNT(DISTINCT customer_id) AS cohort_starting_customers
    FROM int_customer_cohort_assignments
    GROUP BY cohort_month, acquisition_channel_id
),
cohort_monthly_activity AS (
    SELECT
        cohort_month,
        acquisition_channel_id,
        cohort_month_index,
        COUNT(DISTINCT customer_id) AS active_retained_customers,
        COUNT(order_id) AS total_orders,
        SUM(gross_order_value) AS period_gross_revenue,
        SUM(discount_amount) AS period_discounts,
        SUM(refund_amount) AS period_refunds,
        SUM(cogs_amount) AS period_cogs,
        SUM(net_order_revenue) AS period_net_revenue,
        SUM(gross_contribution_margin) AS period_net_margin
    FROM int_order_transactions_sequenced
    GROUP BY cohort_month, acquisition_channel_id, cohort_month_index
),
cohort_matrix_joined AS (
    SELECT
        b.cohort_month,
        b.acquisition_channel_id,
        a.cohort_month_index,
        b.cohort_starting_customers,
        COALESCE(a.active_retained_customers, 0) AS active_retained_customers,
        ROUND(COALESCE(a.active_retained_customers, 0)::NUMERIC / b.cohort_starting_customers, 4) AS retention_rate,
        COALESCE(a.period_net_revenue, 0.00) AS period_net_revenue,
        COALESCE(a.period_net_margin, 0.00) AS period_net_margin,
        cac.channel_cac,
        ROUND(b.cohort_starting_customers * cac.channel_cac, 2) AS total_cohort_acquisition_cost
    FROM cohort_baseline_sizes b
    INNER JOIN cohort_monthly_activity a 
        ON b.cohort_month = a.cohort_month 
       AND b.acquisition_channel_id = a.acquisition_channel_id
    LEFT JOIN int_monthly_channel_cac cac 
        ON b.cohort_month = cac.cohort_month 
       AND b.acquisition_channel_id = cac.acquisition_channel_id
),
cumulative_aggregation AS (
    SELECT
        cohort_month,
        acquisition_channel_id,
        cohort_month_index,
        cohort_starting_customers,
        active_retained_customers,
        retention_rate,
        period_net_margin,
        channel_cac,
        total_cohort_acquisition_cost,
        -- Cumulative Contribution Margin across cohort lifecycle
        SUM(period_net_margin) OVER (
            PARTITION BY cohort_month, acquisition_channel_id 
            ORDER BY cohort_month_index ASC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_net_margin,
        -- Cumulative Margin LTV per acquired customer
        ROUND(
            SUM(period_net_margin) OVER (
                PARTITION BY cohort_month, acquisition_channel_id 
                ORDER BY cohort_month_index ASC 
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) / cohort_starting_customers, 
        2) AS cumulative_margin_ltv
    FROM cohort_matrix_joined
)
SELECT
    cohort_month,
    acquisition_channel_id,
    cohort_month_index,
    cohort_starting_customers,
    active_retained_customers,
    retention_rate,
    period_net_margin,
    cumulative_net_margin,
    channel_cac,
    cumulative_margin_ltv,
    (cumulative_net_margin - total_cohort_acquisition_cost) AS net_capital_recovery_dollars,
    ROUND(
        CASE 
            WHEN channel_cac > 0 THEN (cumulative_margin_ltv / channel_cac) 
            ELSE NULL 
        END, 
    2) AS cumulative_ltv_to_cac_ratio,
    CASE
        WHEN channel_cac = 0 THEN 'Organic / Pure Profit'
        WHEN cumulative_margin_ltv < channel_cac THEN 'Unrecovered Capital'
        WHEN cumulative_margin_ltv >= channel_cac AND cumulative_margin_ltv < (channel_cac * 2) THEN 'Breakeven / Recovered'
        ELSE 'Profitable Compounding'
    END AS payback_status
FROM cumulative_aggregation;