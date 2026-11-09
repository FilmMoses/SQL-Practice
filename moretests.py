import sqlite3
import pandas as pd
import numpy as np
from sklearn.linear_model import LinearRegression
from scipy.integrate import solve_ivp
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, "fleet_monitor.db")

conn = sqlite3.connect(DB_PATH)

df = pd.read_sql_query("""
    SELECT * FROM v_clean_cstr_telemetry
    WHERE system_state NOT IN ('SCRAM', 'COOLDOWN')
    ORDER BY vessel_id, clean_timestamp
    """, conn)

df['dT_dt'] = df.groupby('vessel_id')['temp_k'].diff()
df['effective_cooling'] = df['coolant_lpm'] * (df['agitator_rpm'] / 400.0)
sys_df = df.dropna(subset=['dT_dt']).copy()

sys_df['exo_drive'] = sys_df['conc_m'] * np.exp((sys_df['temp_k'] - 340.0) / 20.0)
sys_df['cool_drive'] = sys_df['effective_cooling'] * (sys_df['temp_k'] - 310.0)

X_sys = sys_df[['exo_drive', 'cool_drive']]
y_sys = sys_df['dT_dt']

ode_fit = LinearRegression(fit_intercept=False).fit(X_sys, y_sys)
alpha_est, neg_gamma_est = ode_fit.coef_
print("=== System Identification: Learned ODE Parameters ===")
print(f"Exothermic Heat Coeff (alpha): {alpha_est:.4f}")
print(f"Effective Cooling Coeff (gamma): {abs(neg_gamma_est):.4f}")
print(f"Physics Fit R^2 Score: {ode_fit.score(X_sys, y_sys):.3f}\n")

def rx103_digital_twin(t, state, mode):
    T = state[0]
    C = 2.40 - 0.04 * t  # Gradual reactant depletion
    
    if mode == 'IGNORED_STALL':
        # Agitator continues stalling toward 0 RPM; effective cooling collapses
        rpm_t = max(0.0, 320.0 - 110.0 * t)
        q_cool = min(20.0, 13.6 + 1.8 * t)
    elif mode == 'INTERVENTION_AUX_MIXER':
        rpm_t = 400.0
        q_cool = 22.0
        
    eff_cool = q_cool * (rpm_t / 400.0)
    exo_term = C * np.exp((T - 340.0) / 20.0)
    cool_term = eff_cool * (T - 310.0)
    
    dTdt = alpha_est * exo_term + neg_gamma_est * cool_term
    return [dTdt]

t_span = [0, 4]
t_eval = [0, 1, 2, 3, 4]

sol_ignored = solve_ivp(rx103_digital_twin, t_span, [345.0], args=('IGNORED_STALL',), t_eval=t_eval)
sol_action  = solve_ivp(rx103_digital_twin, t_span, [345.0], args=('INTERVENTION_AUX_MIXER',), t_eval=t_eval)

twin_df = pd.DataFrame({
    'Timestamp': ['08:03:00 (Alert!)', '08:04:00 (+1m)', '08:05:00 (+2m)', '08:06:00 (+3m)', '08:07:00 (+4m)'],
    'Actual_RX103_Temp_K': [345.0, 351.2, 364.0, 382.5, 398.0],
    'Twin_Ignored_Stall_K': np.round(sol_ignored.y[0], 1),
    'Twin_Operator_Action_K': np.round(sol_action.y[0], 1)
})
print("=== RX-103 Digital Twin Trajectory Forecast (Triggered at 08:03:00) ===")
print(twin_df.to_string(index=False))