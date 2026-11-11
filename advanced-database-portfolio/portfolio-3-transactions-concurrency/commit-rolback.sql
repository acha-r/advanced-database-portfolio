-- ROO's EMR: Portfolio 3, part A: commit, rollback and savepoints (single session)
-- Run statement by statement (Ctrl+Enter in Workbench) and screenshot each result.
USE roos_emr;

-- A1: admit a patient as ONE unit of work: patient + episode + first visit. Then COMMIT.
START TRANSACTION;

INSERT INTO patients (agency_id, mrn, first_name, last_name, dob, sex, status)
VALUES (1, 'MRN-TX0001', 'Test', 'Admission', '1950-05-05', 'F', 'ACTIVE');
SET @pid = LAST_INSERT_ID();

INSERT INTO episodes (patient_id, physician_id, start_date, end_date, status)
VALUES (@pid, 1, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 60 DAY), 'OPEN');
SET @eid = LAST_INSERT_ID();

INSERT INTO visits (episode_id, staff_id, visit_type, scheduled_start, scheduled_end)
VALUES (@eid, 2, 'ADMISSION', DATE_ADD(NOW(), INTERVAL 1 DAY), DATE_ADD(NOW(), INTERVAL 25 HOUR));

COMMIT;

-- Evidence: all three rows exist
SELECT p.patient_id, p.mrn, e.episode_id, v.visit_id, v.visit_type
FROM patients p
JOIN episodes e ON e.patient_id = p.patient_id
JOIN visits v ON v.episode_id = e.episode_id
WHERE p.mrn = 'MRN-TX0001';



-- A2: a failure part-way through, then ROLLBACK.
START TRANSACTION;

INSERT INTO patients (agency_id, mrn, first_name, last_name, dob, sex, status)
VALUES (1, 'MRN-TX0002', 'Test', 'Rollback', '1948-03-03', 'M', 'ACTIVE');
SET @pid2 = LAST_INSERT_ID();

-- This fails: end_date is before start_date, so chk_episode_dates rejects it
INSERT INTO episodes (patient_id, physician_id, start_date, end_date, status)
VALUES (@pid2, 1, CURDATE(), DATE_SUB(CURDATE(), INTERVAL 1 DAY), 'OPEN');

-- The failed statement was undone, but the earlier INSERT is still pending inside the transaction
SELECT mrn FROM patients WHERE mrn = 'MRN-TX0002';   -- returns 1 row

ROLLBACK;

-- Evidence: the patient is gone as well
SELECT mrn FROM patients WHERE mrn = 'MRN-TX0002';   -- returns 0 rows


-- A3: savepoint: undo only the last step and keep the rest
START TRANSACTION;

INSERT INTO patients (agency_id, mrn, first_name, last_name, dob, sex, status)
VALUES (1, 'MRN-TX0003', 'Test', 'Savepoint', '1952-07-07', 'F', 'REFERRED');
SAVEPOINT after_patient;

UPDATE patients SET status = 'DISCHARGED' WHERE mrn = 'MRN-TX0003';
SELECT mrn, status FROM patients WHERE mrn = 'MRN-TX0003';   -- DISCHARGED

ROLLBACK TO SAVEPOINT after_patient;
SELECT mrn, status FROM patients WHERE mrn = 'MRN-TX0003';   -- back to REFERRED

COMMIT;
SELECT mrn, status FROM patients WHERE mrn = 'MRN-TX0003';   -- the patient row was kept