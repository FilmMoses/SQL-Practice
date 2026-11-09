DROP TABLE IF EXISTS raw_cstr_telemetry;

CREATE TABLE raw_cstr_telemetry (
    record_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    vessel_id       TEXT,
    event_time      TEXT,
    system_state    TEXT,
    telemetry_blob  TEXT,
    coolant_lpm     TEXT,
    pressure_bar    REAL,
    alarm_code      TEXT
);

INSERT INTO raw_cstr_telemetry 
    (vessel_id, event_time, system_state, telemetry_blob, coolant_lpm, pressure_bar, alarm_code)
VALUES
    -- ================= VESSEL RX-101: Normal Operation to Exothermic Runaway =================
    ('RX-101',   '2026-04-10 08:00:00', 'STEADY',    'temp:340.2K|conc:2.50|rpm:400', '12.0',     2.10, 'OK'),
    ('rx-101 ',  '2026-04-10 08:01:00', 'steady',    'temp:341.0K|conc:2.48|rpm:405', '12.2 LPM', 2.12, 'OK'),
    -- Exact network retry duplicate of 08:01:00
    ('RX-101',   '2026-04-10 08:01:00', 'STEADY',    'temp:341.0K|conc:2.48|rpm:405', '12.2',     2.12, 'OK'),
    -- Firmware glitch outputs Celsius instead of Kelvin (69.35 C = 342.50 K)
    ('RX-101',   '2026-04-10 08:02:00', 'STEADY',    'temp:69.35C|conc:2.45|rpm:400', '12.5',     2.15, 'OK'),
    -- Unix Epoch timestamp (1775808180 = 2026-04-10 08:03:00 UTC)
    ('RX_101',   '1775808180',          'STEADY ',   'temp:344.8K|conc:2.40|rpm:410', '13.0',     2.22, 'OK'),
    -- Sentinel value in coolant_lpm ('-999') and inverted pressure sensor polarity (-2.30)
    ('RX-101',   '2026-04-10 08:04:00', 'RAMPING',   'temp:348.5K|conc:2.32|rpm:420', '-999',    -2.30, 'WARN_TEMP_RISE'),
    ('RX-101',   '2026-04-10 08:05:00', 'RAMPING',   'temp:354.0K|conc:2.20|rpm:430', '14.5',     2.45, 'WARN_TEMP_RISE'),
    -- Corrupted payload checksum failure
    ('RX-101',   '2026-04-10 08:06:00', 'RAMPING',   'ERR_CHECKSUM_CORRUPT_PACKET',   '15.0',     2.60, 'SENSOR_FAULT'),
    -- Slash date format (DD/MM/YYYY HH:MM:SS)
    ('RX-101',   '10/04/2026 08:07:00', 'RAMPING',   'temp:368.2K|conc:1.95|rpm:450', '15.2 LPM', 2.85, 'WARN_HIGH_TEMP'),
    -- Cooling valve sticks at ~15.2 LPM while temperature accelerates (Feedback loop failure!)
    (' rx-101',  '2026-04-10 08:08:00', 'OVERDRIVE', 'temp:379.5K|conc:1.65|rpm:460', '15.2',     3.20, 'CRIT_THERMAL'),
    ('RX-101',   '2026-04-10 08:09:00', 'OVERDRIVE', 'temp:395.0K|conc:1.20|rpm:460', '15.1',     3.75, 'CRIT_RUNAWAY'),
    ('RX-101',   '2026-04-10 08:10:00', 'SCRAM',     'temp:412.0K|conc:0.60|rpm:0',   '25.0',     4.40, 'EMERGENCY_TRIP'),
    ('RX-101',   '2026-04-10 08:11:00', 'COOLDOWN',  'temp:385.0K|conc:0.55|rpm:0',   '25.0',     3.10, 'POST_TRIP'),
    ('RX-102',   '2026-04-10 08:00:00', 'STEADY',    'temp:338.0K|conc:2.60|rpm:380', '11.5',     2.00, 'OK'),
    ('RX-102',   '2026-04-10 08:01:00', 'STEADY',    'temp:339.2K|conc:2.58|rpm:380', '12.0',     2.04, 'OK'),
    -- Sentinel temperature (-999.0K) inside blob
    ('rx-102',   '2026-04-10 08:02:00', 'STEADY',    'temp:-999.0K|conc:2.55|rpm:385','12.8',     2.08, 'OK'),
    ('RX-102',   '2026-04-10 08:03:00', 'RAMPING',   'temp:343.5K|conc:2.48|rpm:390', '14.2',     2.18, 'OK'),
    -- Text N/A in coolant
    ('RX-102 ',  '2026-04-10 08:04:00', 'RAMPING',   'temp:346.0K|conc:2.42|rpm:395', 'N/A',      2.25, 'OK'),
    -- Cooling flow aggressively scales up to dampen heat (73.85 C = 347.00 K)
    ('RX-102',   '2026-04-10 08:05:00', 'RAMPING',   'temp:73.85C|conc:2.38|rpm:395', '17.5 LPM', 2.28, 'OK'),
    ('RX-102',   '2026-04-10 08:06:00', 'STEADY',    'temp:345.5K|conc:2.40|rpm:390', '18.0',     2.22, 'OK'),
    ('RX-102',   '10/04/2026 08:07:00', 'STEADY',    'temp:343.0K|conc:2.44|rpm:385', '16.5',     2.15, 'OK'),
    ('RX_102',   '2026-04-10 08:08:00', 'STEADY',    'temp:340.8K|conc:2.50|rpm:380', '14.0',     2.08, 'OK'),
    ('RX-102',   '2026-04-10 08:09:00', 'STEADY',    'temp:339.5K|conc:2.54|rpm:380', '12.5',     2.03, 'OK'),
    ('RX-102',   '2026-04-10 08:10:00', 'STEADY',    'temp:339.0K|conc:2.56|rpm:380', '12.0',     2.01, 'OK'),
    ('RX-103',   '2026-04-10 08:00:00', 'STEADY',    'temp:342.0K|conc:2.45|rpm:410', '13.0',     2.15, 'OK'),
    ('RX-103',   '2026-04-10 08:01:00', 'STEADY',    'temp:342.8K|conc:2.44|rpm:410', '13.1',     2.16, 'OK'),
    -- Duplicate packet
    ('rx-103',   '2026-04-10 08:01:00', 'steady',    'temp:342.8K|conc:2.44|rpm:410', '13.1',     2.16, 'OK'),
    -- Zero pressure dropout glitch while active
    ('RX-103',   '2026-04-10 08:02:00', 'STEADY',    'temp:343.5K|conc:2.42|rpm:405', '13.2',     0.00, 'OK'),
    ('RX-103',   '2026-04-10 08:03:00', 'STEADY',    'temp:345.0K|conc:2.40|rpm:320', '?',        2.30, 'WARN_AGIT_DRAG'),
    ('RX-103',   '1775808240',          'RAMPING',   'temp:351.2K|conc:2.35|rpm:180', '14.0',     2.65, 'WARN_AGIT_DRAG'),
    ('RX-103',   '2026-04-10 08:05:00', 'OVERDRIVE', 'temp:364.0K|conc:2.30|rpm:45',  '16.0',     3.15, 'CRIT_STALL'),
    ('RX-103',   '2026-04-10 08:06:00', 'OVERDRIVE', 'temp:382.5K|conc:2.25|rpm:0',   '19.5 LPM', 3.85, 'CRIT_THERMAL'),
    ('RX-103',   '2026-04-10 08:07:00', 'SCRAM',     'temp:398.0K|conc:2.10|rpm:0',   '24.0',     4.25, 'EMERGENCY_TRIP'),
    ('RX-103',   '2026-04-10 08:08:00', 'COOLDOWN',  'temp:370.0K|conc:2.05|rpm:0',   '24.0',     2.95, 'POST_TRIP'),
    -- Ghost row with unparseable timestamp
    ('RX-103',   'INVALID_CLOCK_SYNC',  'OFFLINE',   NULL,                            '0.0',      1.00, 'CLOCK_ERR');

