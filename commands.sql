-- Active: 1793783933168@@127.0.0.1@3306
SELECT
    REPLACE(TRIM(UPPER(vessel_id)), '_', '-') AS standardized_vessel,
    COUNT(*) AS total_raw_rows,

    COUNT(*) - COUNT(DISTINCT event_time) AS duplicate_packets,
    
    SUM(CASE WHEN event_time LIKE '____-__-__ __:__:__' THEN 1 ELSE 0 END) AS iso_dates,
    SUM(CASE WHEN event_time LIKE '__/__/____ __:__:__' THEN 1 ELSE 0 END) AS slash_dates,
    SUM(CASE WHEN LENGTH(event_time) = 10 AND CAST(event_time AS INTEGER) > 0 THEN 1 ELSE 0 END) AS epoch_dates,
    SUM(CASE WHEN event_time NOT LIKE '____-__-__%'
                AND event_time NOT LIKE '__/__/____%'
                AND CAST(event_time AS INTEGER) = 0 THEN 1 ELSE 0 END) AS corrupted_dates,
    
    SUM(CASE WHEN telemetry_blob IS NULL OR telemetry_blob NOT LIKE 'temp:%' THEN 1 ELSE 0 END) AS broken_blobs,
    SUM(CASE WHEN telemetry_blob LIKE '%C|%' THEN 1 ELSE 0 END) AS celcius_unit_drift_rows,
    SUM(CASE WHEN coolant_lpm IN ('N/A', '?', '-999') THEN 1 ELSE 0 END) AS missing_coolant_rows,
    SUM(CASE WHEN pressure_bar <= 0 THEN 1 ELSE 0 END) AS invalid_pressure_rows

FROM raw_cstr_telemetry
GROUP BY REPLACE(TRIM(UPPER(vessel_id)), '_', '-');

DROP VIEW IF EXISTS v_clean_cstr_telemetry;

GO

CREATE VIEW v_clean_cstr_telemetry AS
WITH parsed_stage AS (
    SELECT 
        record_id,
        REPLACE(TRIM(UPPER(vessel_id)), '_', '-') AS vessel_id,
        TRIM(UPPER(system_state)) AS system_state,
        
        CASE 
            WHEN event_time LIKE '____-__-__ __:__:__' 
                THEN DATETIME(event_time)
            WHEN event_time LIKE '__/__/____ __:__:__' 
                THEN DATETIME(
                    SUBSTR(event_time, 7, 4) || '-' || 
                    SUBSTR(event_time, 4, 2) || '-' || 
                    SUBSTR(event_time, 1, 2) || ' ' || 
                    SUBSTR(event_time, 12, 8)
                )
            WHEN LENGTH(event_time) = 10 AND CAST(event_time AS INTEGER) > 0 
                THEN DATETIME(CAST(event_time AS INTEGER), 'unixepoch')
            ELSE NULL 
        END AS clean_timestamp,
        
        CASE 
            WHEN telemetry_blob LIKE 'temp:%' THEN
                SUBSTR(
                    telemetry_blob || '|',
                    INSTR(telemetry_blob, 'temp:') + 5,
                    INSTR(SUBSTR(telemetry_blob || '|', INSTR(telemetry_blob, 'temp:') + 5), '|') - 1
                )
            ELSE NULL 
        END AS raw_temp_token,

        CASE 
            WHEN telemetry_blob LIKE '%conc:%' THEN
                CAST(
                    SUBSTR(
                        telemetry_blob || '|',
                        INSTR(telemetry_blob, 'conc:') + 5,
                        INSTR(SUBSTR(telemetry_blob || '|', INSTR(telemetry_blob, 'conc:') + 5), '|') - 1
                    ) AS REAL
                )
            ELSE NULL 
        END AS conc_mol_l,

        CASE 
            WHEN telemetry_blob LIKE '%rpm:%' THEN
                CAST(
                    SUBSTR(
                        telemetry_blob || '|',
                        INSTR(telemetry_blob, 'rpm:') + 4,
                        INSTR(SUBSTR(telemetry_blob || '|', INSTR(telemetry_blob, 'rpm:') + 4), '|') - 1
                    ) AS REAL
                )
            ELSE NULL 
        END AS agitator_rpm,

        CASE 
            WHEN TRIM(REPLACE(UPPER(coolant_lpm), 'LPM', '')) NOT IN ('N/A', '?', '-999', '')
                THEN CAST(TRIM(REPLACE(UPPER(coolant_lpm), 'LPM', '')) AS REAL)
            ELSE NULL 
        END AS raw_coolant_lpm,

        CASE 
            WHEN pressure_bar < 0 THEN ABS(pressure_bar)
            WHEN pressure_bar = 0 AND TRIM(UPPER(system_state)) NOT IN ('OFFLINE', 'SCRAM') THEN NULL
            ELSE pressure_bar 
        END AS raw_pressure_bar,

        alarm_code,

        ROW_NUMBER() OVER (
            PARTITION BY REPLACE(TRIM(UPPER(vessel_id)), '_', '-'), event_time
            ORDER BY record_id ASC
        ) AS dedup_rank
    FROM raw_cstr_telemetry
),

unit_harmonized AS (
    SELECT 
        record_id,
        vessel_id,
        clean_timestamp,
        system_state,
        
        CASE 
            WHEN raw_temp_token IS NULL THEN NULL
            WHEN CAST(raw_temp_token AS REAL) <= 0 THEN NULL -- Catches -999.0K
            WHEN raw_temp_token LIKE '%C' THEN ROUND(CAST(raw_temp_token AS REAL) + 273.15, 2)
            ELSE ROUND(CAST(raw_temp_token AS REAL), 2)
        END AS temp_kelvin,
        
        conc_mol_l,
        agitator_rpm,
        raw_coolant_lpm,
        raw_pressure_bar,
        alarm_code
    FROM parsed_stage
    WHERE dedup_rank = 1 
      AND clean_timestamp IS NOT NULL
)
SELECT 
    vessel_id,
    clean_timestamp,
    system_state,
    
    ROUND(COALESCE(
        temp_kelvin,
        (LAG(temp_kelvin, 1) OVER w + LEAD(temp_kelvin, 1) OVER w) / 2.0,
        AVG(temp_kelvin) OVER (PARTITION BY vessel_id ORDER BY clean_timestamp ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING)
    ), 2) AS temp_k,

    ROUND(COALESCE(
        conc_mol_l,
        (LAG(conc_mol_l, 1) OVER w + LEAD(conc_mol_l, 1) OVER w) / 2.0,
        LAG(conc_mol_l, 1) OVER w
    ), 3) AS conc_m,

    COALESCE(
        agitator_rpm,
        (LAG(agitator_rpm, 1) OVER w + LEAD(agitator_rpm, 1) OVER w) / 2.0,
        LAG(agitator_rpm, 1) OVER w
    ) AS agitator_rpm,

    ROUND(COALESCE(
        raw_coolant_lpm,
        (LAG(raw_coolant_lpm, 1) OVER w + LEAD(raw_coolant_lpm, 1) OVER w) / 2.0,
        LAG(raw_coolant_lpm, 1) OVER w
    ), 2) AS coolant_lpm,

    ROUND(COALESCE(
        raw_pressure_bar,
        (LAG(raw_pressure_bar, 1) OVER w + LEAD(raw_pressure_bar, 1) OVER w) / 2.0,
        LAG(raw_pressure_bar, 1) OVER w
    ), 2) AS pressure_bar,

    alarm_code
FROM unit_harmonized
WINDOW w AS (PARTITION BY vessel_id ORDER BY clean_timestamp);



WITH quartile_prep AS (
    SELECT
        vessel_id,
        temp_k,
        coolant_lpm,
        pressure_bar,
        NTILE(4) OVER (PARTITION BY vessel_id ORDER BY temp_k ASC) AS temp_quartile
    FROM v_clean_cstr_telemetry
),
moments AS (
    SELECT
        vessel_id,
        COUNT(*) AS n_obs,
        ROUND(AVG(temp_k), 2) AS mean_temp_k,
        ROUND(MIN(temp_k), 2) AS min_temp_k,

        ROUND(MAX(CASE WHEN temp_quartile = 1 THEN temp_k END), 2) AS q25_temp_k,
        ROUND(MAX(CASE WHEN temp_quartile = 2 THEN temp_k END), 2) AS median_temp_k,
        ROUND(MAX(CASE WHEN temp_quartile = 3 THEN temp_k END), 2) AS q75_temp_k,
        ROUND(MAX(temp_k), 2) AS max_temp_k,

        SQRT(MAX(0.0, AVG(temp_k * temp_k) - AVG(temp_k) * AVG(temp_k))) AS sd_temp,

        SQRT(MAX(0.0, AVG(coolant_lpm * coolant_lpm) - AVG(coolant_lpm) * AVG(coolant_lpm))) AS sd_coolant,

        (AVG(temp_k * coolant_lpm) - AVG(temp_k) * AVG(coolant_lpm)) AS cov_temp_coolant
    FROM quartile_prep
    GROUP BY vessel_id
)
SELECT
    vessel_id,
    n_obs,
    mean_temp_k,
    ROUND(sd_temp, 2) AS sd_temp_k,
    median_temp_k,
    ROUND(q75_temp_k - q25_temp_k, 2) AS iqr_temp_k,
    ROUND(cov_temp_coolant, 2) AS cov_temp_coolant,

    ROUND(cov_temp_coolant / NULLIF(sd_temp * sd_coolant, 0), 4) AS corr_temp_coolant
FROM moments; 

WITH first_order_dynamics AS (
    SELECT
        vessel_id,
        clean_timestamp,
        system_state,
        temp_k,
        conc_m,
        agitator_rpm,
        coolant_lpm,
        pressure_bar,
        alarm_code,

        ROUND((
            JULIANDAY(clean_timestamp) - JULIANDAY(LAG(clean_timestamp, 1) OVER w)
        ) * 14740.0, 2) AS dt_min,

        ROUND(temp_k - LAG(temp_k, 1) OVER w, 3) AS dT_dt,
        ROUND(conc_m - LAG(conc_m, 1) OVER w, 3) AS dC_dt,
        ROUND(coolant_lpm - LAG(coolant_lpm, 1) OVER w, 3) AS dQ_dt,

        AVG(temp_k) OVER w_roll AS roll_mean_temp,
        SQRT(MAX(0.0001, AVG(temp_k * temp_k) OVER w_roll - (AVG(temp_k) OVER w_roll) * (AVG(temp_k) OVER w_roll))) AS roll_sd_temp
    
    FROM v_clean_cstr_telemetry
    WINDOW
        w AS (PARTITION BY vessel_id ORDER BY clean_timestamp),
        w_roll AS (PARTITION BY vessel_id ORDER BY clean_timestamp ROWS BETWEEN 3 PRECEDING AND CURRENT ROW)
),

second_order_dynamics AS (
    SELECT
        *,

        ROUND(dT_dt - LAG(dT_dt, 1) OVER w, 3) AS d2T_dt2,
        ROUND(dQ_dt / NULLIF(dT_dt, 0), 3) AS cooling_response_gain,
        ROUND((temp_k - roll_mean_temp) / roll_sd_temp, 2) AS temp_z_score,
        MAX(CASE 
                WHEN alarm_code LIKE 'CRIT$' 
                OR alarm_code LIKE '%EMERGENCY%' 
                THEN 1 ELSE 0 
                END)
            OVER (
                PARTITION BY vessel_id 
                ORDER BY clean_timestamp 
                ROWS BETWEEN 1 FOLLOWING AND 2 FOLLOWING) AS target_runaway_2min

    FROM first_order_dynamics
    WINDOW w AS (
        PARTITION BY vessel_id 
        ORDER BY clean_timestamp)
)

SELECT
    vessel_id,
    clean_timestamp,
    system_state,
    temp_k,
    dT_dt,
    d2T_dt2,
    cooling_response_gain,
    temp_z_score,
    agitator_rpm,
    pressure_bar,

    CASE
        WHEN dT_dt > 2.0 AND d2T_dt2 > 0.5 THEN 'UNSTABLE_EXOTHERMIC_ACCEL'
        WHEN dT_dt > 0 AND cooling_response_gain >= 0.4 THEN 'DAMPED_FEEDBACK_ACTIVE'
        ELSE 'STABE_EQUILIBRIUM'
    END AS dynamic_regime,
    COALESCE(target_runaway_2min, 0) AS target_runaway_2min
FROM second_order_dynamics
WHERE dt_min IS NOT NULL


DROP VIEW IF EXISTS v_cstr_feature_store;

GO

CREATE VIEW v_cstr_feature_store AS
WITH base_dynamics AS (
    SELECT
        vessel_id,
        clean_timestamp,
        system_state,
        temp_k,
        conc_m,
        agitator_rpm,
        coolant_lpm,
        pressure_bar,
        alarm_code,

        ROUND(coolant_lpm * (agitator_rpm / 400.0), 4) AS effective_cooling,
        ROUND(temp_k - LAG(temp_k, 1) OVER w , 3) AS dT_dt,
        ROUND(pressure_bar - LAG(pressure_bar, 1) OVER w, 3) AS dP_dt,
        ROUND(agitator_rpm - LAG(agitator_rpm, 1) OVER w, 3) AS dRPM_dt
    FROM v_clean_cstr_telemetry
    WINDOW w AS (PARTITION BY vessel_id ORDER BY clean_timestamp)
)
SELECT
    vessel_id,
    clean_timestamp,
    system_state,
    temp_k,
    conc_m,
    agitator_rpm,
    coolant_lpm,
    effective_cooling,
    dT_dt,
    ROUND(dT_dt - LAG(dT_dt, 1) OVER w, 3) AS d2T_dt2,
    dP_dt,
    dRPM_dt,
    ROUND(effective_cooling - LAG(effective_cooling, 1) OVER w, 4) AS dEffCool_dt,
    alarm_code,

    MAX(CASE WHEN alarm_code LIKE 'CRIT%' OR alarm_code LIKE 'EMERGENCY%' THEN 1 ELSE 0 END)
        OVER (PARTITION BY vessel_id ORDER BY clean_timestamp ROWS BETWEEN 1 FOLLOWING AND 2 FOLLOWING) AS target_runaway_2min
FROM base_dynamics
WINDOW W AS (PARTITION BY vessel_id ORDER BY clean_timestamp);


