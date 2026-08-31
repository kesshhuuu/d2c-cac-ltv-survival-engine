"""
src/generate_data.py
-------------------------------------------------------------------------
Principal Growth & Marketing Analytics Engineering Pipeline
Project: D2C CAC vs. LTV Cohort & Customer Survival Engine

Generates:
1. data/raw_customers.csv
2. data/raw_orders.csv
3. data/raw_channel_spend.csv

Includes automated programmatic mathematical and referential integrity assertions.
-------------------------------------------------------------------------
"""

import os
import numpy as np
import pandas as pd
from datetime import datetime, timedelta

# Set deterministic seed for commercial reproducibility
SEED = 42
np.random.seed(SEED)

def generate_synthetic_growth_data():
    os.makedirs("data", exist_ok=True)
    
    # -------------------------------------------------------------------------
    # 1. Parameter Specifications & Marketing Mix Assumptions
    # -------------------------------------------------------------------------
    start_date = datetime(2024, 1, 1)
    end_date = datetime(2025, 12, 31)
    months = pd.date_range(start=start_date, end=end_date, freq='MS')
    
    channels = {
        'meta_ads': {
            'name': 'Meta Ads', 'type': 'Paid Performance', 
            'cac_base': 38.0, 'share': 0.38, 'aov_mean': 88.0, 'aov_std': 22.0,
            'base_refund_rate': 0.14, 'discount_prob': 0.45
        },
        'google_ads': {
            'name': 'Google Ads', 'type': 'Paid Performance', 
            'cac_base': 46.0, 'share': 0.27, 'aov_mean': 105.0, 'aov_std': 26.0,
            'base_refund_rate': 0.11, 'discount_prob': 0.28
        },
        'creator_network': {
            'name': 'Creator Network', 'type': 'Partner', 
            'cac_base': 32.0, 'share': 0.15, 'aov_mean': 78.0, 'aov_std': 18.0,
            'base_refund_rate': 0.16, 'discount_prob': 0.70
        },
        'organic_search': {
            'name': 'Organic Search', 'type': 'Organic/Owned', 
            'cac_base': 0.0, 'share': 0.12, 'aov_mean': 92.0, 'aov_std': 24.0,
            'base_refund_rate': 0.09, 'discount_prob': 0.20
        },
        'direct': {
            'name': 'Direct', 'type': 'Organic/Owned', 
            'cac_base': 0.0, 'share': 0.08, 'aov_mean': 96.0, 'aov_std': 25.0,
            'base_refund_rate': 0.08, 'discount_prob': 0.15
        }
    }
    
    total_customers_target = 12500
    customer_ids = [f"CUST_{i:06d}" for i in range(1, total_customers_target + 1)]
    
    # -------------------------------------------------------------------------
    # 2. Customer Cohort Generation
    # -------------------------------------------------------------------------
    channel_keys = list(channels.keys())
    channel_probs = [channels[c]['share'] for c in channel_keys]
    
    month_weights = np.linspace(0.7, 1.3, len(months))
    month_weights /= month_weights.sum()
    
    # Generate index choices to keep native Timestamp types
    chosen_month_indices = np.random.choice(len(months), size=total_customers_target, p=month_weights)
    assigned_channels = np.random.choice(channel_keys, size=total_customers_target, p=channel_probs)
    
    customers_data = []
    for idx, cust_id in enumerate(customer_ids):
        cohort_m = months[chosen_month_indices[idx]]  # Native pd.Timestamp
        ch = assigned_channels[idx]
        
        days_in_month = cohort_m.days_in_month
        random_day = int(np.random.randint(0, days_in_month))
        random_seconds = int(np.random.randint(0, 86400))
        signup_dt = cohort_m.to_pydatetime() + timedelta(days=random_day, seconds=random_seconds)
        
        country = np.random.choice(['US', 'CA', 'GB', 'DE'], p=[0.75, 0.12, 0.08, 0.05])
        
        customers_data.append({
            'customer_id': cust_id,
            'signup_timestamp': signup_dt.strftime('%Y-%m-%d %H:%M:%S'),
            'acquisition_channel_id': ch,
            'country_code': country
        })
        
    df_customers = pd.DataFrame(customers_data)
    
    # -------------------------------------------------------------------------
    # 3. Order Stream Simulation (Weibull Repurchase Latency & Economics)
    # -------------------------------------------------------------------------
    orders_data = []
    order_counter = 1
    
    for idx, row in df_customers.iterrows():
        cust_id = row['customer_id']
        signup_dt = datetime.strptime(row['signup_timestamp'], '%Y-%m-%d %H:%M:%S')
        ch = row['acquisition_channel_id']
        ch_config = channels[ch]
        
        cur_order_time = signup_dt
        propensity = np.random.beta(a=0.8, b=2.2)
        
        is_active = True
        seq = 1
        
        while is_active and cur_order_time <= end_date:
            gross_val = max(25.0, np.random.normal(ch_config['aov_mean'], ch_config['aov_std']))
            gross_val = round(gross_val, 2)
            
            has_discount = np.random.rand() < ch_config['discount_prob']
            if has_discount:
                discount_pct = np.random.choice([0.10, 0.15, 0.20, 0.25], p=[0.40, 0.35, 0.20, 0.05])
                discount_amt = round(gross_val * discount_pct, 2)
            else:
                discount_amt = 0.00
                
            cogs_rate = np.random.uniform(0.32, 0.38)
            cogs_amt = round(gross_val * cogs_rate, 2)
            
            discount_excess = (discount_amt / gross_val) if gross_val > 0 else 0
            adjusted_refund_prob = ch_config['base_refund_rate'] + (0.08 if discount_excess >= 0.20 else 0.0)
            
            is_refunded = np.random.rand() < adjusted_refund_prob
            if is_refunded:
                refund_amt = gross_val if np.random.rand() < 0.70 else round(gross_val * np.random.uniform(0.3, 0.7), 2)
                status = 'completed' if refund_amt < gross_val else 'refunded'
            else:
                refund_amt = 0.00
                status = 'completed'
                
            orders_data.append({
                'order_id': f"ORD_{order_counter:07d}",
                'customer_id': cust_id,
                'order_timestamp': cur_order_time.strftime('%Y-%m-%d %H:%M:%S'),
                'gross_order_value': gross_val,
                'discount_amount': discount_amt,
                'cogs_amount': cogs_amt,
                'refund_amount': refund_amt,
                'order_status': status
            })
            order_counter += 1
            
            repeat_prob = propensity * (0.65 ** seq)
            if np.random.rand() < repeat_prob:
                latency_days = int(np.random.weibull(a=1.5) * 45) + 3
                cur_order_time = cur_order_time + timedelta(days=latency_days, hours=int(np.random.randint(1, 23)))
                seq += 1
            else:
                is_active = False
                
    df_orders = pd.DataFrame(orders_data)
    
    # -------------------------------------------------------------------------
    # 4. Channel Marketing Spend Generation
    # -------------------------------------------------------------------------
    df_customers['cohort_month'] = pd.to_datetime(df_customers['signup_timestamp']).dt.to_period('M').dt.to_timestamp()
    acq_counts = df_customers.groupby(['cohort_month', 'acquisition_channel_id']).size().reset_index(name='acquired_count')
    
    spend_data = []
    for m in months:
        for ch_key, ch_cfg in channels.items():
            cnt_match = acq_counts[(acq_counts['cohort_month'] == m) & (acq_counts['acquisition_channel_id'] == ch_key)]
            actual_acq = cnt_match['acquired_count'].values[0] if len(cnt_match) > 0 else 0
            
            if ch_cfg['cac_base'] > 0:
                cac_noise = np.random.uniform(0.92, 1.10)
                total_spend = round(actual_acq * ch_cfg['cac_base'] * cac_noise, 2)
            else:
                total_spend = 0.00
                
            spend_data.append({
                'spend_month': m.strftime('%Y-%m-%d'),
                'acquisition_channel_id': ch_key,
                'marketing_spend': total_spend
            })
            
    df_channel_spend = pd.DataFrame(spend_data)
    
    # -------------------------------------------------------------------------
    # 5. Programmatic Assertions & Mathematical Audits
    # -------------------------------------------------------------------------
    print("=" * 70)
    print("RUNNING AUTOMATED SELF-VERIFICATION & DATA INTEGRITY ASSERTIONS...")
    print("=" * 70)
    
    assert df_customers['customer_id'].is_unique, "Assertion Failed: Customer IDs are not unique!"
    assert df_orders['order_id'].is_unique, "Assertion Failed: Order IDs are not unique!"
    
    missing_custs = set(df_orders['customer_id']) - set(df_customers['customer_id'])
    assert len(missing_custs) == 0, f"Assertion Failed: {len(missing_custs)} orders reference non-existent customers!"
    
    assert (df_orders['gross_order_value'] > 0).all(), "Assertion Failed: Non-positive gross order value detected!"
    assert (df_orders['discount_amount'] >= 0).all(), "Assertion Failed: Negative discount detected!"
    assert (df_orders['discount_amount'] <= df_orders['gross_order_value']).all(), "Assertion Failed: Discount exceeds gross order value!"
    assert (df_orders['refund_amount'] <= df_orders['gross_order_value']).all(), "Assertion Failed: Refund exceeds gross order value!"
    assert (df_orders['cogs_amount'] >= 0).all(), "Assertion Failed: Negative COGS detected!"
    
    df_merged_check = df_orders.merge(df_customers[['customer_id', 'signup_timestamp']], on='customer_id')
    assert (pd.to_datetime(df_merged_check['order_timestamp']) >= pd.to_datetime(df_merged_check['signup_timestamp'])).all(), \
        "Assertion Failed: Order occurred prior to customer signup timestamp!"
        
    print("✓ Primary Key Uniqueness: PASSED (100% Unique)")
    print("✓ Foreign Key Referential Integrity: PASSED (0 Broken Keys)")
    print("✓ Financial Bounds (Gross >= Discounts, Gross >= Refunds, COGS >= 0): PASSED")
    print("✓ Temporal Causality (Order Timestamp >= Signup Timestamp): PASSED")
    print("=" * 70)
    
    # -------------------------------------------------------------------------
    # 6. Export to CSV
    # -------------------------------------------------------------------------
    df_customers[['customer_id', 'signup_timestamp', 'acquisition_channel_id', 'country_code']].to_csv('data/raw_customers.csv', index=False)
    df_orders.to_csv('data/raw_orders.csv', index=False)
    df_channel_spend.to_csv('data/raw_channel_spend.csv', index=False)
    
    print(f"Data generation complete.")
    print(f" -> data/raw_customers.csv     | Rows: {len(df_customers):,}")
    print(f" -> data/raw_orders.csv        | Rows: {len(df_orders):,}")
    print(f" -> data/raw_channel_spend.csv | Rows: {len(df_channel_spend):,}")
    print("=" * 70)

if __name__ == "__main__":
    generate_synthetic_growth_data()