-- Baseline queries
-- Must be run BEFORE indexes.sql to capture the "before" plans.

USE roos_emr;

-- ---------------------------------------------------------------------------
-- Q1: Missed visits for one agency in the last 12 months (a scheduler's follow-up list)
-- Filters on visits.status and visits.scheduled_start, which have no index yet.
-- ---------------------------------------------------------------------------
SELECT a.name AS agency, p.mrn, p.last_name AS patient, v.visit_type,
       v.scheduled_start, s.last_name AS clinician
FROM visits v
JOIN episodes e ON e.episode_id = v.episode_id
JOIN patients p ON p.patient_id = e.patient_id
JOIN agencies a ON a.agency_id = p.agency_id
JOIN staff s ON s.staff_id = v.staff_id
WHERE a.agency_id = 3
  AND v.status = 'MISSED'
  AND v.scheduled_start >= NOW() - INTERVAL 12 MONTH
ORDER BY v.scheduled_start DESC;

-- ---------------------------------------------------------------------------
-- Q2: Full visit history for one patient, filtered by MRN
-- The only unique index on mrn is (agency_id, mrn). A lookup by mrn alone
-- cannot use it, because agency_id is the leading column.
-- ---------------------------------------------------------------------------
SELECT p.mrn, e.episode_id, e.start_date, v.visit_type, v.status,
       v.scheduled_start, vs.systolic, vs.diastolic, vs.heart_rate
FROM patients p
JOIN episodes e ON e.patient_id = p.patient_id
JOIN visits v ON v.episode_id = e.episode_id
LEFT JOIN vital_signs vs ON vs.visit_id = v.visit_id
WHERE p.mrn = 'MRN-000123'
ORDER BY v.scheduled_start;

-- ---------------------------------------------------------------------------
-- Q3: Outstanding claims per agency (submitted more than 30 days ago, still unpaid)
-- Filters on claims.status and claims.submitted_at, no index.
-- ---------------------------------------------------------------------------
SELECT a.name AS agency, COUNT(*) AS unpaid_claims, SUM(c.amount) AS total_outstanding
FROM claims c
JOIN episodes e ON e.episode_id = c.episode_id
JOIN patients p ON p.patient_id = e.patient_id
JOIN agencies a ON a.agency_id = p.agency_id
WHERE c.status = 'SUBMITTED'
  AND c.submitted_at < NOW() - INTERVAL 30 DAY
GROUP BY a.agency_id, a.name
ORDER BY total_outstanding DESC;

--------------------------------------------------------------------
-- Q4: The LEFT JOIN count query (the pagination "total records" query)
-- The screen shows a page of completed visits for an agency, and a second query
-- counts the total. The count was copied from the list query, so it carries
-- LEFT JOINs to tables that are only needed for display columns. Joining to
-- child tables (orders: 2 per episode, medications: 3 per patient) multiplies
-- the rows, so the count is both slow AND wrong.
-- ---------------------------------------------------------------------------

-- Q4a: slow version
SELECT COUNT(*) AS total
FROM visits v
LEFT JOIN episodes e ON e.episode_id = v.episode_id
LEFT JOIN patients p ON p.patient_id = e.patient_id
LEFT JOIN staff s ON s.staff_id = v.staff_id
LEFT JOIN visit_notes n ON n.visit_id = v.visit_id
LEFT JOIN vital_signs vs ON vs.visit_id = v.visit_id
LEFT JOIN physician_orders o ON o.episode_id = e.episode_id
LEFT JOIN patient_medications pm ON pm.patient_id = p.patient_id
WHERE p.agency_id = 3
  AND v.status = 'COMPLETED';

-- Q4b: corrected version. Only the tables used in the filter are joined.
SELECT COUNT(*) AS total
FROM visits v
JOIN episodes e ON e.episode_id = v.episode_id
JOIN patients p ON p.patient_id = e.patient_id
WHERE p.agency_id = 3
  AND v.status = 'COMPLETED';
