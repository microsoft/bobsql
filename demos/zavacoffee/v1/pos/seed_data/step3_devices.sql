/* ============================================================
   C) STAFF & DEVICES (per store, idempotent)
   ============================================================ */
-- Staff: add 4 per store if none exist
;WITH st AS (
  SELECT rs.store_id, n.n AS i
  FROM zava.RefStore rs
  CROSS APPLY zava._util_GetNumbers(4) n
)
INSERT zava.Staff(staff_code, full_name, role, active)
SELECT CONCAT('ST', RIGHT('000000',6 - LEN(CAST(ABS(CHECKSUM(store_id, i)) % 999999 + 1 AS varchar(6))))
              + CAST(ABS(CHECKSUM(store_id, i)) % 999999 + 1 AS varchar(6))) AS staff_code,
       CONCAT(N'Barista ', rs.store_code, N' #', i) AS full_name,
       CASE WHEN i=4 THEN 'MANAGER' ELSE 'BARISTA' END,
       1
FROM st
JOIN zava.RefStore rs ON rs.store_id = st.store_id
WHERE NOT EXISTS (SELECT 1 FROM zava.Staff);  -- seed once overall

-- Devices: 1 POS + 1 KIOSK per store if missing
;WITH d AS (
  SELECT rs.store_id, v.dt, ROW_NUMBER() OVER (PARTITION BY rs.store_id ORDER BY (SELECT NULL)) AS rn
  FROM zava.RefStore rs
  CROSS APPLY (VALUES ('POS'), ('KIOSK')) v(dt)
)
INSERT zava.Device(device_code, device_type, active)
SELECT CONCAT(dt, '-', RIGHT('000000',6-LEN(CAST(store_id AS varchar(6)))) + CAST(store_id AS varchar(6))),
       dt, 1
FROM d
WHERE NOT EXISTS (
  SELECT 1 FROM zava.Device WHERE device_code = CONCAT(d.dt, '-', RIGHT('000000',6-LEN(CAST(d.store_id AS varchar(6)))) + CAST(d.store_id AS varchar(6)))
);