# Execution plans: BEFORE indexes

## Q1: Missed visits for one agency (last 12 months)

```sql
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
```

**Plan:**
```
-> Sort: v.scheduled_start DESC  (actual time=66.4..66.4 rows=806 loops=1)
    -> Stream results  (cost=8945 rows=1723) (actual time=0.553..65.8 rows=806 loops=1)
        -> Nested loop inner join  (cost=8945 rows=1723) (actual time=0.544..64.3 rows=806 loops=1)
            -> Nested loop inner join  (cost=8342 rows=1723) (actual time=0.535..62.7 rows=806 loops=1)
                -> Nested loop inner join  (cost=1105 rows=2841) (actual time=0.365..10 rows=3000 loops=1)
                    -> Index lookup on p using uq_patient_mrn (agency_id=3)  (cost=321 rows=2000) (actual time=0.356..4.22 rows=2000 loops=1)
                    -> Covering index lookup on e using fk_episode_patient (patient_id=p.patient_id)  (cost=0.25 rows=1.42) (actual time=0.00187..0.00269 rows=1.5 loops=2000)
                -> Filter: ((v.`status` = 'MISSED') and (v.scheduled_start >= <cache>((now() - interval 12 month))))  (cost=1.82 rows=0.606) (actual time=0.0169..0.0174 rows=0.269 loops=3000)
                    -> Index lookup on v using fk_visit_episode (episode_id=e.episode_id)  (cost=1.82 rows=7.28) (actual time=0.0142..0.0162 rows=7 loops=3000)
            -> Single-row index lookup on s using PRIMARY (staff_id=v.staff_id)  (cost=0.25 rows=1) (actual time=0.00173..0.00177 rows=1 loops=806)
```

**Observations:**
- Access type on `visits`: Index lookup (`ref`) on `fk_visit_episode` (episode_id = e.episode_id). It is not a full table scan, but the index only covers `episode_id`. `status` and `scheduled_start` are not indexed, so they are checked as a filter after each visit row is fetched.
- Rows examined vs rows returned: about 21,000 visits examined (7 per episode × 3,000 episodes) vs 806 returned, so roughly 96% of the rows read are discarded.
- Actual time: 66.4 ms total. About 52 ms of that is the visits lookup and filter step (62.7 ms at the join minus about 10 ms for the patient and episode lookups).

## Q2: Patient history by MRN
***Query*** 
```
SELECT p.mrn, e.episode_id, e.start_date, v.visit_type, v.status,
       v.scheduled_start, vs.systolic, vs.diastolic, vs.heart_rate
FROM patients p
JOIN episodes e ON e.patient_id = p.patient_id
JOIN visits v ON v.episode_id = e.episode_id
LEFT JOIN vital_signs vs ON vs.visit_id = v.visit_id
WHERE p.mrn = 'MRN-000123'
ORDER BY v.scheduled_start;
```

**Plan:**
```
-> Sort: v.scheduled_start  (actual time=13.5..13.5 rows=14 loops=1)
    -> Stream results  (cost=34111 rows=20135) (actual time=3.34..13.4 rows=14 loops=1)
        -> Nested loop left join  (cost=34111 rows=20135) (actual time=3.31..13.4 rows=14 loops=1)
            -> Nested loop inner join  (cost=12023 rows=20135) (actual time=3.29..13.1 rows=14 loops=1)
                -> Nested loop inner join  (cost=4976 rows=2766) (actual time=3.28..13.1 rows=2 loops=1)
                    -> Filter: (p.mrn = 'MRN-000123')  (cost=1988 rows=1948) (actual time=3.25..13 rows=1 loops=1)
                        -> Covering index scan on p using uq_patient_mrn  (cost=1988 rows=19476) (actual time=0.407..9.12 rows=20000 loops=1)
                    -> Index lookup on e using fk_episode_patient (patient_id=p.patient_id)  (cost=1.39 rows=1.42) (actual time=0.0287..0.0303 rows=2 loops=1)
                -> Index lookup on v using fk_visit_episode (episode_id=e.episode_id)  (cost=1.82 rows=7.28) (actual time=0.012..0.0146 rows=7 loops=2)
            -> Index lookup on vs using fk_vital_visit (visit_id=v.visit_id)  (cost=0.997 rows=1) (actual time=0.0161..0.017 rows=0.857 loops=14)
```

**Observation:**
- Access type on `patients`: Covering index scan (full scan of `uq_patient_mrn`). The index starts with `agency_id`, so a lookup by `mrn` alone cannot use it to jump to the row. The joins after it all use `ref` index lookups on foreign key indexes.
- Rows examined vs rows returned: 20,000 index entries examined to find 1 patient (and 14 result rows overall). Almost the whole index is read for one match.
- Actual time: 13.5 ms total, of which about 13 ms is the scan on `patients`.

## Q3: Outstanding claims
**Query:**
```
SELECT a.name AS agency, COUNT(*) AS unpaid_claims, SUM(c.amount) AS total_outstanding
FROM claims c
JOIN episodes e ON e.episode_id = c.episode_id
JOIN patients p ON p.patient_id = e.patient_id
JOIN agencies a ON a.agency_id = p.agency_id
WHERE c.status = 'SUBMITTED'
  AND c.submitted_at < NOW() - INTERVAL 30 DAY
GROUP BY a.agency_id, a.name
ORDER BY total_outstanding DESC;
```
**Plan:**
```
-> Sort: total_outstanding DESC  (actual time=67.7..67.7 rows=10 loops=1)
    -> Table scan on <temporary>  (actual time=67.7..67.7 rows=10 loops=1)
        -> Aggregate using temporary table  (actual time=67.7..67.7 rows=10 loops=1)
            -> Nested loop inner join  (cost=5076 rows=2464) (actual time=0.844..56.4 rows=6592 loops=1)
                -> Nested loop inner join  (cost=4213 rows=2464) (actual time=0.84..46.2 rows=6592 loops=1)
                    -> Nested loop inner join  (cost=3351 rows=2464) (actual time=0.836..34.8 rows=6592 loops=1)
                        -> Filter: ((c.`status` = 'SUBMITTED') and (c.submitted_at < <cache>((now() - interval 30 day))))  (cost=2488 rows=2464) (actual time=0.822..21.7 rows=6592 loops=1)
                            -> Table scan on c  (cost=2488 rows=29571) (actual time=0.808..15 rows=30000 loops=1)
                        -> Single-row index lookup on e using PRIMARY (episode_id=c.episode_id)  (cost=0.25 rows=1) (actual time=0.00177..0.0018 rows=1 loops=6592)
                    -> Single-row index lookup on p using PRIMARY (patient_id=e.patient_id)  (cost=0.25 rows=1) (actual time=0.00153..0.00156 rows=1 loops=6592)
                -> Single-row index lookup on a using PRIMARY (agency_id=p.agency_id)  (cost=0.25 rows=1) (actual time=0.0013..0.00134 rows=1 loops=6592)

```
**Observation:**
- Access type on `claims`: Full table scan (`ALL`). No index on `status` or `submitted_at`. The joins to episodes, patients and agencies all use primary key lookups.
- Rows examined vs rows returned: 30,000 claims read, 6,592 pass the filter (about 22%), and the final result is 10 rows (one per agency after grouping).
- Actual time: 67.7 ms total. About 22 ms scanning and filtering, about 35 ms on the three joins for 6,592 rows, about 11 ms on grouping and sorting.

## Q4a: Count query with LEFT JOINs (slow)
**Slow (And Incorrect) Query:**
```SELECT COUNT(*) AS total
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
  ```
**Count returned:** 106572

## Q4b: Count query, corrected
```
SELECT COUNT(*) AS total
FROM visits v
JOIN episodes e ON e.episode_id = v.episode_id
JOIN patients p ON p.patient_id = e.patient_id
WHERE p.agency_id = 3
  AND v.status = 'COMPLETED';
```

**Count returned:** 17762