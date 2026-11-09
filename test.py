import sqlite3
import os
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import precision_score, recall_score, fbeta_score, confusion_matrix

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "fleet_monitor.db")

conn = sqlite3.connect(DB_PATH)

df = pd.read_sql_query("SELECT * FROM v_clean_cstr_telemetry ORDER BY vessel_id, clean_timestamp", conn)

df['dT_dt'] = df.groupby('vessel_id')['temp_k'].diff()
df['d2T_dt2'] = df.groupby('vessel_id')['dT_dt'].diff()
df['dRPM_dt'] = df.groupby('vessel_id')['agitator_rpm'].diff()
df['dP_dt'] = df.groupby('vessel_id')['pressure_bar'].diff()

df['effective_cooling'] = df['coolant_lpm'] * (df['agitator_rpm'] / 400.0)
df['dEffCool_dt'] = df.groupby('vessel_id')['effective_cooling'].diff()

df['is_crit'] = df['alarm_code'].str.startswith(('CRIT', 'EMERGENCY')).astype(int)
df['target_runaway_2min'] = (
    df.groupby('vessel_id')['is_crit'].shift(-1).fillna(0).astype(int) | 
    df.groupby('vessel_id')['is_crit'].shift(-2).fillna(0).astype(int)
)

model_df = df[~df['system_state'].isin(['SCRAM', 'COOLDOWN'])].dropna(subset=['dT_dt', 'd2T_dt2']).copy()
features = ['dT_dt', 'd2T_dt2', 'dP_dt', 'dEffCool_dt']

train_df = model_df[model_df['vessel_id'].isin(['RX-101', 'RX-102'])]
test_df  = model_df[model_df['vessel_id'] == 'RX-103'].copy()

X_train, y_train = train_df[features], train_df['target_runaway_2min']
X_test,  y_test  = test_df[features],  test_df['target_runaway_2min']

clf = make_pipeline(StandardScaler(), LogisticRegression(class_weight='balanced', random_state=42))
clf.fit(X_train, y_train)

y_prob = clf.predict_proba(X_test)[:, 1]
SAFETY_THRESHOLD = 0.35
preds = (y_prob >= SAFETY_THRESHOLD).astype(int)

test_df['pred_prob'] = np.round(y_prob, 3)
test_df['pred_alert'] = preds

print("=== Physics-Informed ML Evaluation on Unseen Vessel RX-103 ===")
print(f"Precision: {precision_score(y_test, preds, zero_division=0):.3f}")
print(f"Recall:    {recall_score(y_test, preds, zero_division=0):.3f}")
print(f"F2-Score (Safety-Weighted): {fbeta_score(y_test, preds, beta=2, zero_division=0):.3f}\n")

print("=== Step-by-Step Telemetry & Model Predictions on RX-103 ===")
cols_to_show = ['clean_timestamp', 'temp_k', 'agitator_rpm', 'dT_dt', 'dEffCool_dt', 'target_runaway_2min', 'pred_prob', 'pred_alert']
print(test_df[cols_to_show].to_string(index=False))