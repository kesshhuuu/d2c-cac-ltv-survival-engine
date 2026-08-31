# D2C CAC vs. LTV Cohort & Customer Survival Engine

[![SQL: PostgreSQL | DuckDB | BigQuery](https://img.shields.io/badge/SQL-PostgreSQL%20%7C%20DuckDB%20%7C%20BigQuery-336791.svg)](https://github.com/)
[![Python: Pandas | NumPy | SciPy | Lifelines](https://img.shields.io/badge/Python-Pandas%20%7C%20NumPy%20%7C%20SciPy%20%7C%20Lifelines-3776AB.svg)](https://github.com/)
[![Power BI: DAX | Star Schema](https://img.shields.io/badge/Power%20BI-DAX%20%7C%20Star%20Schema-F2C811.svg)](https://github.com/)
[![Assertions: 100% Verified](https://img.shields.io/badge/Assertions-100%25%20Verified-brightgreen.svg)](https://github.com/)

---

## Executive Summary & Commercial Thesis

Traditional Direct-to-Consumer (D2C) growth reporting relies heavily on static, cumulative revenue tables that obscure true margin payback periods, ignore non-linear customer churn hazards, and fail to discount future cash flows. Evaluating cohort profitability solely through standard 30-day payback matrices introduces two massive analytical blindspots:

1. **Static Cohort Fallacy:** Traditional triangular matrices measure gross order accumulation without factoring customer acquisition costs (CAC), cost of goods sold (COGS), discount leakage, and refund write-downs.
2. **Channel Retention Divergence:** Assuming flat churn rates across all traffic sources masks rapid retention decay in paid performance channels versus organic discovery.

This repository implements an end-to-end analytics engineering and customer lifetime value pipeline. It ingests 14,870+ multi-year transactional purchase events across 12,500 customer profiles, models empirical churn dynamics using non-parametric Kaplan-Meier curves and Cox Proportional Hazards regression, and projects 24-month DCF-LTV cash flows factoring an institutional Weighted Average Cost of Capital (WACC) hurdle rate ($r = 1.0\% \text{/month} \approx 12.7\% \text{ annualized}$).

---

## Architecture Pipeline

```text
[ Raw Event Logs & Transactions ]
        ├── raw_customers.csv (12,500 profiles)
        ├── raw_orders.csv (14,870 transactions)
        └── raw_channel_spend.csv (120 monthly spend records)
        │
        ▼
[ Staging Layer (1_staging.sql) ]
        ├── Type Casting, Timestamp Normalization & Regex Sanitization
        ├── UTM Parsing & Channel Type Tagging (Organic, Direct, Paid Search, Paid Social, Creator)
        └── Realized Net Margin = Gross - Discount - Refund - COGS
        │
        ▼
[ Intermediate Layer (2_intermediate.sql) ]
        ├── Cohort Month Framing (0 <= t_order - t_cohort <= 24 Months)
        ├── Customer Lifecycle Duration & Churn Flagging (Duration t, Event E)
        └── Monthly Channel CAC Spend Allocation (Channel Spend_t / M0 Acquired Customers_t)
        │
        ▼
[ Analytical Marts Layer (3_marts_cohort_payback.sql & 4_marts_survival_input.sql) ]
        ├── Mart 1: M0–M24 Cohort Retention & Cumulative Net Margin Payback Matrix
        └── Mart 2: Customer Survival Modeling Dataset (Duration t, Event E, M0 Basket Covariates)
        │
        ├────────────────────────────────────────┬────────────────────────────────────────┐
        ▼                                        ▼                                        ▼
[ Statistical Survival Engine (Python) ]  [ Power BI Diagnostic Cockpit ]        [ Power BI DCF Horizon Simulator ]
├── Kaplan-Meier Survival Curves S(t)    ├── Dynamic M0–M24 Cohort Heatmap       ├── 24M Weibull Retention Forecasts
├── Cox PH Churn Hazard Risk Multipliers ├── Cumulative Margin Payback Curves    ├── Nominal vs. Discounted Cash Gap
└── 24M Parametric DCF Valuation Matrix  └── Marginal LTV:CAC Payback Gauge      └── Capital Hurdle Stress Testing
```

---

## Dimensional Star Schema (ERD)

```text
                       ┌─────────────────────────┐
                       │  Dim_Acquisition_Channel│
                       ├─────────────────────────┤
                       │ PK  acquisition_channel │
                       │     channel_name        │
                       │     channel_type        │
                       └───────────┬─────────────┘
                                   │ 1
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         │ *                       │ *                       │ *
┌────────┴────────────────┐ ┌──────┴────────────────┐ ┌──────┴─────────────────┐
│ Fact_Order_Transactions │ │  Mart_Survival_Curves │ │Mart_DCF_LTV_Projections │
├─────────────────────────┤ ├───────────────────────┤ ├─────────────────────────┤
│ PK  order_id            │ │ PK  acquisition_ch_id │ │ PK  acquisition_ch_id   │
│ FK  customer_id         │ │ PK  tenure_month_t    │ │ PK  forecast_month_t    │
│ FK  acquisition_ch_id   │ │     survival_prob_s_t │ │     weibull_survival_s_t│
│ FK  order_timestamp     │ │     ci_lower_bound    │ │     cumulative_dcf_ltv  │
│     gross_order_value   │ │     ci_upper_bound    │ │     discount_factor     │
│     discount_amount     │ └───────────────────────┘ └─────────────────────────┘
│     gross_contrib_margin│
└────────▲────────────────┘
         │ *
         │ 1
┌────────┴────────────────┐              ┌─────────────────────────┐
│        Dim_Date         │              │  Dim_Scenario_Params    │
├─────────────────────────┤              │  (Disconnected Slicer)  │
│ PK  Date                │              ├─────────────────────────┤
│     Month Name          │              │ PK  param_id            │
│     Month Number        │              │     wacc_hurdle_rate    │
│     Quarter             │              │     margin_multiplier   │
│     Year                │              └─────────────────────────┘
└─────────────────────────┘
```

---

## Mathematical & Econometric Framework

### 1. Contribution Margin & Net Realized Revenue
For each customer order event $i$:

$$\text{Net Revenue}_i = \text{Gross Order Value}_i - \text{Discount Amount}_i - \text{Refund Amount}_i$$

$$\text{Contribution Margin}_i = \text{Net Revenue}_i - \text{COGS}_i$$

### 2. Kaplan-Meier Non-Parametric Survival Probability
For an acquisition channel with observed customer order timelines $t_1 < t_2 < \dots < t_m$:

$$\hat{S}(t) = \prod_{t_i \le t} \left(1 - \frac{d_i}{n_i}\right)$$

Where $d_i$ represents churn events at tenure interval $t_i$, and $n_i$ represents the active customer population at risk.

### 3. Cox Proportional Hazards Churn Risk Multipliers
The instantaneous hazard rate of customer churn $h(t \mid X)$ parameterized by promotional sensitivity and basket value:

$$h(t \mid X) = h_0(t) \exp\left(\beta_1 \cdot \text{GOV}_{M0} + \beta_2 \cdot \text{Discount Share}_{M0} + \sum_{k} \gamma_k \cdot \text{Channel}_k\right)$$

### 4. 24-Month Discounted Cash Flow LTV (DCF-LTV)
Accounting for monthly cost of capital $r = (1 + \text{WACC}_{\text{annual}})^{1/12} - 1$:

$$\text{DCF-LTV}_T = \sum_{t=0}^{T} \frac{\overline{\text{CM}}_t \cdot \hat{S}(t)}{(1 + r)^t}$$

---

## Model Invariants & Verification Assertions

Every statistical and transformation layer strictly satisfies these mathematical invariants:

$$\text{Survival Probability Bounding Invariant:} \quad 0.0000 \le \hat{S}(t) \le 1.0000 \quad \forall \; t \in [0, 24]$$

$$\text{Monotonic Survival Decay Invariant:} \quad \hat{S}(t) \le \hat{S}(t - 1) \quad \forall \; t \ge 1$$

$$\text{Financial DCF Capital Bounding Invariant:} \quad \text{Cumulative DCF LTV}_t \le \text{Cumulative Undiscounted Margin LTV}_t \quad \forall \; t \ge 0$$

$$\text{Referential Integrity Invariant:} \quad \text{Orphaned Orders Count } = 0 \quad \left(\text{FK}_{\text{customer}} \cap \text{PK}_{\text{customer}} \equiv \text{FK}_{\text{customer}}\right)$$

---

## Capital Payback & Channel Portfolio Optimization

### Channel Unit Economic Breakdown

| Acquisition Channel | Blended CAC | Payback Horizon ($T^*$) | 24M Nominal LTV | 24M DCF-LTV ($r=12\%$) | DCF LTV:CAC | Portfolio Classification | Strategic Capital Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Organic Search** | $0.00 | Month 0 ($M_0$) | $184.20 | $176.45 | $\infty$ | Core Asset Base | SEO content compounding & brand moat expansion |
| **Direct** | $0.00 | Month 0 ($M_0$) | $162.50 | $155.80 | $\infty$ | Repeat Baseline | App install & push notification re-engagement |
| **Google Ads** | $46.00 | Month 2 ($M_2$) | $112.40 | $108.15 | **2.35x** | Compounding Profit | Scale budget by $+25\%$; high purchase intent |
| **Meta Ads** | $38.00 | Month 6 ($M_6$) | $78.60 | $75.20 | **1.98x** | Breakeven / Recovered | Cap discount depth to $\le 15\%$ on acquisition ads |
| **Creator Network** | $32.00 | Month 9 ($M_9$) | $62.10 | $59.40 | **1.86x** | Unrecovered / High Churn | Shift compensation to second-order milestone payouts |

### Diminishing Marginal Returns Simulator
Budget scaling simulates non-linear saturation using a power-law return curve ($\beta = 0.85$):

$$\text{Simulated Net Margin} = \text{Base Attributed Margin} \times \left(\frac{\text{Simulated Spend}}{\text{Base Spend}}\right)^{0.85}$$

$$\text{Marginal ROAS (mROAS)} = \frac{\Delta \text{Projected Margin}}{\Delta \text{Channel Spend}}$$

---

## Repository File Tree

```text
d2c-cohort-survival-engine/
├── data/
│   ├── raw_customers.csv                   # Raw customer registration logs (12,500 records)
│   ├── raw_orders.csv                      # Transactional order stream (14,870 records)
│   ├── raw_channel_spend.csv               # Monthly marketing expenditure by channel
│   └── marts/
│       ├── fact_order_transactions.csv     # Materialized transactional fact mart
│       ├── mart_cohort_retention_payback.csv# M0–M24 Retention & Margin Payback matrix
│       ├── mart_customer_survival_input.csv# Right-censored survival duration dataset (Lifelines)
│       ├── mart_survival_curves.csv        # Kaplan-Meier survival probabilities & CIs
│       ├── mart_dcf_ltv_projections.csv    # 24M Nominal vs. Discounted DCF LTV matrix
│       └── mart_cox_hazard_summary.csv     # Cox PH regression coefficients & hazard ratios
├── sql/
│   ├── 1_staging.sql                       # Clean staging views, regex parsing & type casts
│   ├── 2_intermediate.sql                  # Cohort assignment, order sequencing & CAC allocation
│   ├── 3_marts_cohort_payback.sql          # M0–M24 Cumulative net margin payback engine
│   └── 4_marts_survival_input.sql          # Right-censored duration & churn event modeling dataset
├── src/
│   ├── generate_data.py                    # Synthetic clickstream & transaction event generator
│   ├── run_sql_models.py                   # DuckDB ELT pipeline executor & automated assertion suite
│   └── survival_ltv_engine.py              # Statistical survival analysis & DCF cash flow engine
├── requirements.txt                        # Python dependencies
└── README.md                               # Project technical whitepaper
```

---

## Reproducing the Pipeline Locally

### 1. Environment Setup
```bash
# Clone the repository
git clone https://github.com/kesshhuuu/d2c-cac-ltv-survival-engine.git
cd d2c-cohort-survival-engine

# Create and activate virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: .\venv\Scripts\activate

# Install required packages
pip install -r requirements.txt
```

### 2. Run Modular Analytics Engineering Pipeline
```bash
# 1. Generate synthetic customer purchase streams
python src/generate_data.py

# 2. Run modular SQL transformations via DuckDB
python src/run_sql_models.py

# 3. Fit survival models, Cox regressions, and compute DCF-LTV
python src/survival_ltv_engine.py
```