-- ROO's EMR: Portfolio 2 indexes
-- Run ONLY after saving the "before" plans from queries.sql.
-- Then re-run the same queries with EXPLAIN ANALYZE to get the "after" plans.

USE roos_emr;

-- Q1, Q4: filter on status and a date range; staff_id included so Q4 can be
-- answered from the index alone
CREATE INDEX idx_visits_status_sched_staff ON visits (status, scheduled_start, staff_id);

-- Q2: lookup by MRN alone (the existing unique index starts with agency_id)
CREATE INDEX idx_patients_mrn ON patients (mrn);

-- Q3: outstanding claims by status and submission date
CREATE INDEX idx_claims_status_submitted ON claims (status, submitted_at);

-- Q5b: count of visits by episode and status without reading the visits rows
CREATE INDEX idx_visits_episode_status ON visits (episode_id, status);

ANALYZE TABLE visits, patients, claims;

SHOW INDEX FROM visits;
