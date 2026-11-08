-- ROO's EMR Seed Data: must run on a freshly created schema.
-- Values are derived from CRC32 of the row number rather than RAND(), so the
-- data is the same every time the script is run. 


USE roos_emr;
SET SESSION cte_max_recursion_depth = 100000;

-- Helper table of numbers 1..30000 (dropped at the end)
DROP TABLE IF EXISTS seq_numbers;
CREATE TABLE seq_numbers (n INT UNSIGNED PRIMARY KEY);
INSERT INTO seq_numbers (n)
WITH RECURSIVE s (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 30000
)
SELECT n FROM s;

-- 10 agencies
INSERT INTO agencies (name, license_no, phone, address)
SELECT CONCAT('Agency ', LPAD(n, 2, '0')),
       CONCAT('LIC-', LPAD(n, 5, '0')),
       CONCAT('0803', LPAD(n, 7, '0')),
       CONCAT(n, ' Care Street')
FROM seq_numbers WHERE n <= 10 ORDER BY n;

-- 200 staff, 20 per agency. Roles cycle by n MOD 10: ADMIN, RN, RN, LVN, PT, OT, ST, HHA, HHA, BILLER
INSERT INTO staff (agency_id, first_name, last_name, role, email, license_no, is_active)
SELECT ((n - 1) DIV 20) + 1,
       ELT(1 + MOD(n, 10), 'Ada', 'Chris', 'Grace', 'Daniel', 'Fatima', 'Samuel', 'Maria', 'Ibrahim', 'Esther', 'David'),
       ELT(1 + MOD(n * 7, 10), 'Okafor', 'Bello', 'Adeyemi', 'Eze', 'Musa', 'Nwosu', 'Balogun', 'Okoro', 'Uche', 'Danjuma'),
       ELT(1 + MOD(n, 10), 'ADMIN', 'RN', 'RN', 'LVN', 'PT', 'OT', 'ST', 'HHA', 'HHA', 'BILLER'),
       CONCAT('staff', n, '@roos.test'),
       CONCAT('LN-', LPAD(n, 6, '0')),
       1
FROM seq_numbers WHERE n <= 200 ORDER BY n;

-- 300 physicians
INSERT INTO physicians (npi, first_name, last_name, phone)
SELECT CONCAT('1', LPAD(n, 9, '0')),
       ELT(1 + MOD(n, 10), 'Peter', 'Amina', 'John', 'Ngozi', 'Paul', 'Halima', 'James', 'Blessing', 'Mark', 'Ruth'),
       ELT(1 + MOD(n * 3, 10), 'Adebayo', 'Okonkwo', 'Yusuf', 'Ogunleye', 'Ibe', 'Lawal', 'Chukwu', 'Abubakar', 'Obi', 'Salami'),
       CONCAT('0902', LPAD(n, 7, '0'))
FROM seq_numbers WHERE n <= 300 ORDER BY n;

-- 20,000 patients spread evenly over the 10 agencies
INSERT INTO patients (agency_id, mrn, first_name, last_name, dob, sex, phone, address, status)
SELECT MOD(n - 1, 10) + 1,
       CONCAT('MRN-', LPAD(n, 6, '0')),
       ELT(1 + MOD(CRC32(CONCAT('pf', n)), 10), 'Joy', 'Kunle', 'Hauwa', 'Peter', 'Sade', 'Musa', 'Chiamaka', 'Yemi', 'Aisha', 'Tony'),
       ELT(1 + MOD(CRC32(CONCAT('pl', n)), 10), 'Johnson', 'Ali', 'Nnamdi', 'Bassey', 'Akin', 'Garba', 'Umeh', 'Wilson', 'Ojo', 'Ekong'),
       DATE_SUB(CURDATE(), INTERVAL (60 * 365 + MOD(CRC32(CONCAT('dob', n)), 35 * 365)) DAY),
       ELT(1 + MOD(CRC32(CONCAT('sx', n)), 2), 'F', 'M'),
       CONCAT('0701', LPAD(n, 7, '0')),
       CONCAT(n, ' Patient Lane'),
       CASE WHEN MOD(CRC32(CONCAT('ps', n)), 100) < 10 THEN 'REFERRED'
            WHEN MOD(CRC32(CONCAT('ps', n)), 100) < 60 THEN 'ACTIVE'
            ELSE 'DISCHARGED' END
FROM seq_numbers WHERE n <= 20000 ORDER BY n;

-- 30,000 episodes (60-day certification periods, starting within the last two years)
INSERT INTO episodes (patient_id, physician_id, start_date, end_date, status)
SELECT patient_id, physician_id, start_date, DATE_ADD(start_date, INTERVAL 60 DAY),
       CASE WHEN DATE_ADD(start_date, INTERVAL 60 DAY) < CURDATE() THEN 'CLOSED' ELSE 'OPEN' END
FROM (
  SELECT n,
         MOD(n - 1, 20000) + 1 AS patient_id,
         MOD(CRC32(CONCAT('ph', n)), 300) + 1 AS physician_id,
         DATE_SUB(CURDATE(), INTERVAL MOD(CRC32(CONCAT('es', n)), 730) DAY) AS start_date
  FROM seq_numbers WHERE n <= 30000
) e
ORDER BY n;

-- 60,000 physician orders (2 per episode)
INSERT INTO physician_orders (episode_id, physician_id, order_text, ordered_at, signed_at, status)
SELECT episode_id, physician_id, order_text, ordered_at,
       CASE WHEN status = 'SIGNED' THEN DATE_ADD(ordered_at, INTERVAL 1 DAY) END,
       status
FROM (
  SELECT e.episode_id, e.physician_id,
         ELT(s.n, 'Skilled nursing three times weekly for two weeks', 'Physical therapy evaluation and treatment') AS order_text,
         DATE_ADD(CAST(e.start_date AS DATETIME), INTERVAL 9 HOUR) AS ordered_at,
         CASE WHEN MOD(CRC32(CONCAT('os', e.episode_id, '-', s.n)), 100) < 80 THEN 'SIGNED'
              WHEN MOD(CRC32(CONCAT('os', e.episode_id, '-', s.n)), 100) < 95 THEN 'PENDING'
              ELSE 'CANCELLED' END AS status
  FROM episodes e
  JOIN seq_numbers s ON s.n <= 2
) o;

-- 210,000 visits (7 per episode). Each visit is assigned a clinical staff member
-- from the same agency as the patient (staff with role ADMIN or BILLER are skipped).
INSERT INTO visits (episode_id, staff_id, visit_type, scheduled_start, scheduled_end,
                    actual_start, actual_end, status)
WITH a AS (
  SELECT e.episode_id, e.start_date, p.agency_id, s.n AS seq,
         MOD(CRC32(CONCAT('st', e.episode_id, '-', s.n)), 16) AS c,
         MOD(CRC32(CONCAT('vr', e.episode_id, '-', s.n)), 100) AS r,
         MOD(CRC32(CONCAT('vh', e.episode_id, '-', s.n)), 9) AS hr_off,
         MOD(CRC32(CONCAT('vl', e.episode_id, '-', s.n)), 30) AS late
  FROM episodes e
  JOIN patients p ON p.patient_id = e.patient_id
  JOIN seq_numbers s ON s.n <= 7
),
b AS (
  SELECT episode_id,
         (agency_id - 1) * 20 + (c DIV 8) * 10 + MOD(c, 8) + 1 AS staff_id,
         ELT(seq, 'ADMISSION', 'SKILLED_NURSING', 'THERAPY', 'SKILLED_NURSING',
                  'AIDE', 'SKILLED_NURSING', 'DISCHARGE') AS visit_type,
         DATE_ADD(CAST(start_date AS DATETIME),
                  INTERVAL ((seq - 1) * 8 * 24 + 8 + hr_off) HOUR) AS scheduled_start,
         r, late
  FROM a
),
c AS (
  SELECT b.*,
         CASE WHEN scheduled_start > NOW() THEN 'SCHEDULED'
              WHEN r < 88 THEN 'COMPLETED'
              WHEN r < 96 THEN 'MISSED'
              ELSE 'CANCELLED' END AS status
  FROM b
)
SELECT episode_id, staff_id, visit_type, scheduled_start,
       DATE_ADD(scheduled_start, INTERVAL 1 HOUR),
       CASE WHEN status = 'COMPLETED' THEN DATE_ADD(scheduled_start, INTERVAL late MINUTE) END,
       CASE WHEN status = 'COMPLETED' THEN DATE_ADD(scheduled_start, INTERVAL (late + 45) MINUTE) END,
       status
FROM c;

-- One note per completed visit
INSERT INTO visit_notes (visit_id, note_text, signed_at)
SELECT visit_id,
       CONCAT(REPLACE(visit_type, '_', ' '), ' visit completed. Patient assessed, vitals recorded, care plan reviewed.'),
       DATE_ADD(actual_end, INTERVAL 2 HOUR)
FROM visits
WHERE status = 'COMPLETED';

-- One set of vitals per completed visit
INSERT INTO vital_signs (visit_id, systolic, diastolic, heart_rate, temp_c, spo2, recorded_at)
SELECT visit_id,
       100 + MOD(CRC32(CONCAT('sy', visit_id)), 60),
       60 + MOD(CRC32(CONCAT('di', visit_id)), 30),
       55 + MOD(CRC32(CONCAT('hr', visit_id)), 50),
       36.0 + MOD(CRC32(CONCAT('tp', visit_id)), 20) / 10,
       90 + MOD(CRC32(CONCAT('sp', visit_id)), 11),
       actual_start
FROM visits
WHERE status = 'COMPLETED';

-- 100 drugs: 20 names x 5 strengths
INSERT INTO drugs (name, strength, form)
SELECT ELT(1 + MOD(n - 1, 20), 'Lisinopril', 'Metformin', 'Amlodipine', 'Atorvastatin', 'Furosemide',
           'Warfarin', 'Paracetamol', 'Ibuprofen', 'Omeprazole', 'Insulin glargine',
           'Salbutamol', 'Prednisolone', 'Amoxicillin', 'Ciprofloxacin', 'Gabapentin',
           'Tramadol', 'Levothyroxine', 'Carvedilol', 'Spironolactone', 'Clopidogrel'),
       ELT(1 + ((n - 1) DIV 20), '5mg', '10mg', '25mg', '50mg', '100mg'),
       ELT(1 + MOD(n, 3), 'tablet', 'capsule', 'injection')
FROM seq_numbers WHERE n <= 100 ORDER BY n;

-- 60,000 patient medications (3 per patient)
INSERT INTO patient_medications (patient_id, drug_id, dose, frequency, start_date, stop_date)
SELECT patient_id, drug_id, dose, frequency, start_date,
       CASE WHEN stopflag < 30 THEN DATE_ADD(start_date, INTERVAL (30 + stopflag) DAY) END
FROM (
  SELECT p.patient_id AS patient_id,
         MOD(CRC32(CONCAT('dr', p.patient_id, '-', s.n)), 100) + 1 AS drug_id,
         ELT(1 + MOD(CRC32(CONCAT('do', p.patient_id, '-', s.n)), 4), '1 tablet', '2 tablets', '5 ml', '10 units') AS dose,
         ELT(1 + MOD(CRC32(CONCAT('fr', p.patient_id, '-', s.n)), 4), 'once daily', 'twice daily', 'three times daily', 'weekly') AS frequency,
         DATE_SUB(CURDATE(), INTERVAL MOD(CRC32(CONCAT('ms', p.patient_id, '-', s.n)), 400) DAY) AS start_date,
         MOD(CRC32(CONCAT('mf', p.patient_id, '-', s.n)), 100) AS stopflag
  FROM patients p
  JOIN seq_numbers s ON s.n <= 3
) m;

-- 30,000 claims (1 per episode)
INSERT INTO claims (episode_id, amount, submitted_at, status)
SELECT episode_id, amount,
       CASE WHEN status <> 'DRAFT' THEN DATE_ADD(CAST(end_date AS DATETIME), INTERVAL 3 DAY) END,
       status
FROM (
  SELECT e.episode_id, e.end_date,
         800 + MOD(CRC32(CONCAT('ca', e.episode_id)), 4200) + MOD(CRC32(CONCAT('cc', e.episode_id)), 100) / 100 AS amount,
         CASE WHEN MOD(CRC32(CONCAT('cs', e.episode_id)), 100) < 10 THEN 'DRAFT'
              WHEN MOD(CRC32(CONCAT('cs', e.episode_id)), 100) < 35 THEN 'SUBMITTED'
              WHEN MOD(CRC32(CONCAT('cs', e.episode_id)), 100) < 90 THEN 'PAID'
              ELSE 'DENIED' END AS status
  FROM episodes e
) c;

-- One payment per paid claim
INSERT INTO payments (claim_id, amount, paid_at, method)
SELECT claim_id, amount, DATE_ADD(submitted_at, INTERVAL 14 DAY),
       ELT(1 + MOD(CRC32(CONCAT('pm', claim_id)), 3), 'INSURER', 'MEDICARE', 'OTHER')
FROM claims
WHERE status = 'PAID';

DROP TABLE seq_numbers;

-- Refresh optimiser statistics so execution plans reflect the new data
ANALYZE TABLE agencies, staff, physicians, patients, episodes, physician_orders,
              visits, visit_notes, vital_signs, drugs, patient_medications, claims, payments;

-- Row counts for evidence
SELECT 'agencies' AS table_name, COUNT(*) AS row_count FROM agencies
UNION ALL SELECT 'staff', COUNT(*) FROM staff
UNION ALL SELECT 'physicians', COUNT(*) FROM physicians
UNION ALL SELECT 'patients', COUNT(*) FROM patients
UNION ALL SELECT 'episodes', COUNT(*) FROM episodes
UNION ALL SELECT 'physician_orders', COUNT(*) FROM physician_orders
UNION ALL SELECT 'visits', COUNT(*) FROM visits
UNION ALL SELECT 'visit_notes', COUNT(*) FROM visit_notes
UNION ALL SELECT 'vital_signs', COUNT(*) FROM vital_signs
UNION ALL SELECT 'drugs', COUNT(*) FROM drugs
UNION ALL SELECT 'patient_medications', COUNT(*) FROM patient_medications
UNION ALL SELECT 'claims', COUNT(*) FROM claims
UNION ALL SELECT 'payments', COUNT(*) FROM payments;
