# D2C CAC vs. LTV Cohort & Customer Survival Engine

![Python](https://img.shields.io/badge/Python-Lifelines_&_Survival_Analysis-3776AB?logo=python&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-DuckDB_In--Memory_ELT-FFF000?logo=duckdb&logoColor=black)
![Power BI](https://img.shields.io/badge/Power_BI-Star_Schema_&_DAX-F2C811?logo=powerbi&logoColor=black)
![Assertions](https://img.shields.io/badge/Assertions-100%25_Verified-success)

## Executive Summary & Commercial Thesis

Standard Direct-to-Consumer (D2C) cohort reporting relies on static, cumulative revenue tables that obscure true margin payback periods, ignore non-linear customer churn hazards, and fail to discount future cash flows.

1. **Static Cohort Fallacy:** Traditional triangular matrices measure gross order accumulation without factoring customer acquisition costs (CAC), cost of goods sold (COGS), discount leakage, and refund write-downs.
2. **Channel Retention Divergence:** Assuming flat churn rates across all traffic sources masks rapid retention decay in paid performance channels versus organic discovery.

This repository implements an end-to-end **Customer Survival & Discounted Cash Flow (DCF) LTV Engine**. It ingests transactional order streams across 12,500+ customer profiles, models empirical churn dynamics using non-parametric Kaplan-Meier curves and Cox Proportional Hazards regression, and projects 24-month DCF-LTV cash flows factoring an institutional Weighted Average Cost of Capital (WACC) hurdle rate.

## Architecture Pipeline

[ Raw Event Logs & Transactions ]
├── raw_customers.csv (12,500 profiles)
├── raw_orders.csv (14,870 transactions)
└── raw_channel_spend.csv (120 monthly spend records)
│
▼
[ Staging Layer (1_staging.sql) ]
├── Type Casting & Timestamp Normalization
└── Realized Margin = Gross - Discount - Refund - COGS
│
▼
[ Intermediate Layer (2_intermediate.sql) ]
├── Window Framing (M0 to M24 Cohort Indexing)
└── Customer Lifecycle Duration & Churn Flagging (T, E)
│
▼
[ Analytical Marts Layer (3_ & 4_sql) ]
├── mart_cohort_retention_payback.csv (Retention & Margin Matrices)
└── mart_customer_survival_input.csv (Covariates & Duration Data)
│
▼
[ Statistical Survival Engine (Python / lifelines) ]
├── Kaplan-Meier Survival Curves S(t)
├── Cox Proportional Hazards Churn Drivers
└── 24-Month Parametric DCF-LTV Valuation Matrix
│
▼
[ Power BI Executive Cockpit ]
├── Page 1: Dynamic M0–M24 Retention Heatmap & Marginal Payback Horizon
└── Page 2: Statistical Churn Curves & Nominal vs. DCF Cash Flow Simulator


## Mathematical & Econometric Framework

### 1. Contribution Margin & Net Realized Revenue
$$\text{Net Revenue}_i = \text{Gross Order Value}_i - \text{Discount Amount}_i - \text{Refund Amount}_i$$
$$\text{Contribution Margin}_i = \text{Net Revenue}_i - \text{COGS}_i$$

### 2. Kaplan-Meier Non-Parametric Survival Function
$$\hat{S}(t) = \prod_{t_i \le t} \left(1 - \frac{d_i}{n_i}\right)$$

### 3. Discounted Cash Flow LTV ($\text{DCF-LTV}_T$)
Accounting for monthly cost of capital $r = (1 + \text{WACC})^{1/12} - 1$:
$$\text{DCF-LTV}_T = \sum_{t=0}^{T} \frac{\hat{S}(t) \cdot \overline{CM}_t}{(1 + r)^t}$$

## Reproducing the Pipeline Locally

```bash
# 1. Generate Synthetic Event Stream
python src/generate_data.py

# 2. Run Modular SQL Transformation Layers
python src/run_sql_models.py

# 3. Fit Statistical Survival & DCF Models
python src/survival_ltv_engine.py