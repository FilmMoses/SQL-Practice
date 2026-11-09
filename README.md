# Physics-Informed Predictive Maintenance & Grey-Box Digital Twin (CSTR Telemetry)

![SQLite](https://img.shields.io/badge/Database-SQLite3-003B57?style=flat&logo=sqlite&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?style=flat&logo=python&logoColor=white)
![Scikit-Learn](https://img.shields.io/badge/ML-Scikit--Learn-F7931E?style=flat&logo=scikit-learn&logoColor=white)
![SciPy](https://img.shields.io/badge/Dynamic_Systems-SciPy_ODE-8CAAE6?style=flat&logo=scipy&logoColor=white)

## 1. Executive Summary & Operational Impact
In industrial chemical processing, exothermic **Continuous Stirred-Tank Reactors (CSTR)** operate near unstable thermal equilibria. Legacy static-threshold alarms often trigger too late to prevent catastrophic thermal runaway, resulting in emergency shutdowns (SCRAM), equipment damage, and costly unplanned downtime.

This project builds an end-to-end **SQL Data Engineering, Physics-Informed Machine Learning, and Applied Dynamic Systems (Digital Twin)** pipeline from corrupted raw sensor logs:
* **Early Failure Detection:** Detects both external cooling starvation (`RX-101`) and internal mechanical agitator stalls (`RX-103`) **4 to 7 minutes prior to emergency shutdown**—beating legacy hardware alarms with **1.000 Precision** and **0.750 Recall** ($F_2\text{-Score} = 0.789$) on unseen reactor regimes.
* **Counterfactual ODE Simulation:** Uses Ordinary Least Squares (OLS) System Identification ($R^2 = 0.840$) and `scipy.integrate.solve_ivp` to prove that triggering backup mixing and quench cooling at the exact moment of our ML alert (`08:03:00`) caps peak vessel temperature at **345.0 K** and restores the **341.8 K** steady-state baseline—**preventing a 398.0 K emergency SCRAM and saving an estimated $250,000 in unplanned outage costs.**

---

## 2. System Architecture & Pipeline Workflow

```text
[Raw Corrupted Telemetry (CSV / Staging Dump)]
       │
       ├──► 1. Rapid Triage (Excel): Visual filter audits, sentinel detection (-999), duplicate checks
       │
       ▼
[SQLite Data Engineering Layer (v_clean_cstr_telemetry)]
       │    • Deterministic string parsing (INSTR/SUBSTR) without regex dependencies
       │    • Multi-format timestamp unification (ISO-8601, DD/MM/YYYY, Unix Epoch)
       │    • Thermodynamic unit harmonization (°C to Kelvin) & window-based imputation
       ▼
[SQLite Feature Store (v_cstr_feature_store)]
       │    • First & second-order discrete derivatives (dT/dt, d²T/dt², dRPM/dt)
       │    • First-principles Moments, Covariance, and Pearson Correlation (r_TQ)
       │    • Physics-informed feature: Effective Mixing-Coupled Cooling (η_cool)
       ▼
[Analytics, ML & Digital Twin Layer (Python / R / BI)]
       ├──► Supervised ML (Scikit-Learn): Balanced Logistic Regression w/ Safety Threshold (0.35)
       ├──► Dynamic Digital Twin (SciPy): Grey-Box ODE System Identification & Trajectory Control
       ├──► Statistical Inference (R): GLM log-odds diagnostics & structural break validation
       └──► Executive Cockpit (Tableau / PowerBI): Phase-space portraits & What-If intervention cones
```

---

## 3. Phase 1: Defensive SQL Data Engineering & Statistical Auditing

Raw telemetry (`raw_cstr_telemetry`) was ingested simulating real-world production defects across three vessels (`RX-101`, `RX-102`, `RX-103`):
* **Schema & Format Drift:** Mixed timestamps (`YYYY-MM-DD HH:MM:SS`, `DD/MM/YYYY HH:MM:SS`, and 10-digit Unix Epochs) and mid-stream firmware unit drift (`°C` mixed with `K`).
* **Corrupted Payloads & Sentinels:** Key-value string blobs (`temp:340.2K|conc:2.50|rpm:400`), checksum packet failures, reverse-polarity pressure readings (`-2.30 bar`), and sentinel codes (`-999`, `N/A`, `?`).
* **Network Retries:** Duplicate event packets requiring deterministic window pruning via `ROW_NUMBER() OVER (PARTITION BY vessel_id, event_time)`.

### First-Principles Statistical Moments in SQLite
Because lightweight embedded SQL engines omit native `STDDEV()` and `CORR()` aggregates, population moments and bivariate coupling between Reactor Temperature ($T$) and Coolant Flow ($Q$) were derived directly from expectation identities in SQL:

$$\sigma_X = \sqrt{\mathbb{E}[X^2] - (\mathbb{E}[X])^2}, \quad \text{Cov}(T, Q) = \mathbb{E}[TQ] - \mathbb{E}[T]\mathbb{E}[Q], \quad r_{TQ} = \frac{\text{Cov}(T, Q)}{\sigma_T \sigma_Q}$$

| Vessel ID | Operational Regime | Mean Temp ($K$) | Std Dev ($\sigma_T$) | IQR ($K$) | Covariance ($\text{Cov}_{TQ}$) | Pearson Correlation ($r_{TQ}$) | Engineering Diagnosis |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **RX-101** | Cooling Valve Jam $\to$ Runaway | 364.26 | 23.09 | 34.70 | 78.89 | **0.8315** | Correlation degrades as valve plateaus at 15.2 LPM during thermal spike. |
| **RX-102** | Healthy Proportional PID Loop | 342.06 | 2.98 | 5.70 | 6.15 | **0.9168** | Strong positive linear coupling; coolant scales smoothly to dampen heat. |
| **RX-103** | Mechanical Agitator Stall | 362.11 | 19.34 | 37.50 | 75.56 | **0.9715** | External valve opens to 19.5 LPM, but internal boundary layer stagnates. |

---

## 4. Phase 2: Applied Dynamic Systems & Physics-Informed Feature Engineering

### 1. Lyapunov / Semenov Thermal Acceleration
In an exothermic reactor, runaway initiates when both the first derivative ($\frac{dT}{dt} > 0$, heating velocity) and second derivative ($\frac{d^2T}{dt^2} > 0$, heating acceleration) turn positive simultaneously. Computing discrete Lagrangian derivatives in SQLite flagged unstable acceleration on `RX-101` at **`08:03:00`**—**7 minutes before the `08:10:00` emergency SCRAM**.

### 2. Solving Out-of-Distribution (OOD) Failure Shift on `RX-103`
A baseline classifier trained only on raw sensor readings from `RX-101` and `RX-102` initially scored **0.000 Precision and 0.000 Recall** on `RX-103` because `RX-103` failed via an unseen mechanical regime (agitator motor stall where $\text{RPM} \to 0$ while coolant flow rose).

To unify both failure modes in feature space, we engineered **Effective Mixing-Coupled Cooling Capacity ($\eta_{\text{cool}}$)** based on convective heat-transfer turbulence ($\text{Re}_{\text{imp}} \propto \text{RPM}$):

$$\eta_{\text{cool}}(t) = Q_{\text{cool}}(t) \times \left(\frac{\text{RPM}(t)}{\text{RPM}_{\text{nominal}}}\right), \quad \text{dEffCool\_dt} = \frac{\Delta \eta_{\text{cool}}}{\Delta t}$$

* **Result:** When `RX-103`'s agitator dragged from `405 RPM` to `320 RPM` at `08:03:00`, `dEffCool_dt` plunged to **`-2.485`**, immediately triggering the ML early-warning alert ($P(\text{Runaway}) \ge 0.35$).

| Model Iteration | Feature Space | Decision Threshold | Precision | Recall | $F_2\text{-Score}$ | Early Warning Lead Time |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Baseline Model** | Raw Sensors + Post-Trip Leakage | 0.50 | 0.000 | 0.000 | 0.000 | Missed Runaway (0 min) |
| **Physics-Informed Pipeline** | Pre-Trip Regime + `dT_dt`, `d2T_dt2`, `dP_dt`, `dEffCool_dt` | **0.35** | **1.000** | **0.750** | **0.789** | **4 Minutes (`08:03:00` vs `08:07:00` SCRAM)** |

---

## 5. Phase 3: Grey-Box Digital Twin & Counterfactual ODE Simulation

Using our clean SQLite feature store, we estimated the governing thermodynamic differential equation parameters via Ordinary Least Squares ($R^2 = \mathbf{0.840}$):

$$\frac{dT}{dt} = \alpha \underbrace{\left(C(t) \cdot e^{\frac{T(t) - 340}{20}}\right)}_{\text{Arrhenius Exothermic Drive}} - \gamma \underbrace{\left(\eta_{\text{cool}}(t) \cdot (T(t) - 310)\right)}_{\text{Effective Jacket Dissipation}}$$

Integrating forward from the **`08:03:00` ML Alert** using `scipy.integrate.solve_ivp` demonstrates the exact physical impact of operator intervention:

| Timestamp | Horizon | Actual `RX-103` Sensor ($K$) | Digital Twin: Do-Nothing Stall ($K$) | Digital Twin: Auxiliary Mixer + Quench ($K$) | Operational Status |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **`08:03:00`** | **Alert ($t_0$)** | **345.0** | **345.0** | **345.0** | **ML Alert Tripped (`dEffCool_dt = -2.485`)** |
| `08:04:00` | $+1\text{ min}$ | 351.2 | 351.1 | 343.8 | Twin tracks actual climb within $0.1\text{ K}$ |
| `08:05:00` | $+2\text{ min}$ | 364.0 | 363.2 | 342.9 | Unmitigated stall crosses warning threshold |
| `08:06:00` | $+3\text{ min}$ | 382.5 | 381.9 | 342.2 | Unmitigated stall breaches critical seal limit |
| **`08:07:00`** | **$+4\text{ min}$** | **398.0 (SCRAM)** | **401.2 (SCRAM)** | **341.8 (Stable)** | **56.2 K reduction; SCRAM averted** |

---

## 6. Repository Structure & Quickstart

```text
├── data/
│   ├── clean_cstr_telemetry_export.csv   # Sanitized flat export for Excel / Tableau / PowerBI
│   └── fleet_monitor.db                  # Self-healing SQLite database (Tables & Views)
├── sql/
│   └── cstr_eda_lesson.sql               # DDL, corrupted ingestion, Data Quality Scorecard & Views
├── src/
│   ├── csv_to_sqlite.py                  # Reusable utility to convert raw CSVs into SQLite tables
│   ├── fix_pipeline.py                   # Idempotent schema verifier & sqlite_master diagnostic
│   └── cstr_ml_simulation.py             # Physics-informed ML classifier & SciPy ODE Digital Twin
└── README.md
```

### How to Run Locally in VS Code
1. Clone the repository and install dependencies:
   ```bash
   pip install pandas numpy scikit-learn scipy
   ```
2. Build and verify the self-healing SQLite database and export the clean CSV:
   ```bash
   python src/fix_pipeline.py
   ```
3. Run the Physics-Informed ML Evaluation and ODE Digital Twin simulation:
   ```bash
   python src/cstr_ml_simulation.py
   ```
