## Q1: Missed visits for one agency (last 12 months)
**Plan:**
```
-> Sort: v.scheduled_start DESC  (actual time=28..28.1 rows=806 loops=1)
    -> Stream results  (cost=6418 rows=3795) (actual time=0.483..27.6 rows=806 loops=1)
        -> Nested loop inner join  (cost=6418 rows=3795) (actual time=0.477..26.2 rows=806 loops=1)
            -> Nested loop inner join  (cost=5090 rows=3795) (actual time=0.47..24.8 rows=806 loops=1)
                -> Nested loop inner join  (cost=1105 rows=2841) (actual time=0.439..9.94 rows=3000 loops=1)
                    -> Index lookup on p using uq_patient_mrn (agency_id=3)  (cost=321 rows=2000) (actual time=0.428..4.18 rows=2000 loops=1)
                    -> Covering index lookup on e using fk_episode_patient (patient_id=p.patient_id)  (cost=0.25 rows=1.42) (actual time=0.00186..0.00263 rows=1.5 loops=2000)
                -> Filter: (v.scheduled_start >= <cache>((now() - interval 12 month)))  (cost=1 rows=1.34) (actual time=0.00455..0.0048 rows=0.269 loops=3000)
                    -> Index lookup on v using idx_visits_episode_status (episode_id=e.episode_id, status='MISSED'), with index condition: (v.`status` = 'MISSED')  (cost=1 rows=4.01) (actual time=0.00416..0.00458 rows=0.545 loops=3000)
            -> Single-row index lookup on s using PRIMARY (staff_id=v.staff_id)  (cost=0.25 rows=1) (actual time=0.00151..0.00154 rows=1 loops=806)
```

**Observation:**
- Access type on `visits`: Index lookup (`ref`) on `idx_visits_episode_status` (episode_id, status = 'MISSED'). The status filter is now part of the index lookup. `scheduled_start` is still filtered after the row is fetched.
- Rows examined vs rows returned: about 1,635 visits examined (0.545 per episode × 3,000) vs 806 returned. Before: about 21,000 examined.
- Actual time: 28 ms total, down from 66.4 ms (about 58% faster). The optimiser chose `idx_visits_episode_status` and ignored `idx_visits_status_sched_staff`.

## Q2: Patient history by MRN
**Plan:**
```
-> Sort: v.scheduled_start  (actual time=0.22..0.223 rows=14 loops=1)
    -> Stream results  (cost=16 rows=9.95) (actual time=0.0928..0.197 rows=14 loops=1)
        -> Nested loop left join  (cost=16 rows=9.95) (actual time=0.0824..0.165 rows=14 loops=1)
            -> Nested loop inner join  (cost=5.05 rows=9.95) (actual time=0.0692..0.0901 rows=14 loops=1)
                -> Nested loop inner join  (cost=1.57 rows=1.42) (actual time=0.0384..0.0417 rows=2 loops=1)
                    -> Covering index lookup on p using idx_patients_mrn (mrn='MRN-000123')  (cost=1.07 rows=1) (actual time=0.0189..0.0207 rows=1 loops=1)
                    -> Index lookup on e using fk_episode_patient (patient_id=p.patient_id)  (cost=0.497 rows=1.42) (actual time=0.0188..0.0202 rows=2 loops=1)
                -> Index lookup on v using idx_visits_episode_status (episode_id=e.episode_id)  (cost=2.24 rows=7.01) (actual time=0.021..0.0233 rows=7 loops=2)
            -> Index lookup on vs using fk_vital_visit (visit_id=v.visit_id)  (cost=1.01 rows=1) (actual time=0.00425..0.00502 rows=0.857 loops=14)
```

**Observation:**
- Access type on `patients`: Covering index lookup (`ref`) on `idx_patients_mrn`.
- Rows examined vs rows returned: 1 index entry examined, 1 patient found, 14 result rows overall. Before: 20,000 entries examined.
- Actual time: 0.22 ms total, down from 13.5 ms.

## Q3: Outstanding claims
**Plan:**
```
-> Sort: total_outstanding DESC  (actual time=52.7..52.7 rows=10 loops=1)
    -> Table scan on <temporary>  (actual time=52.7..52.7 rows=10 loops=1)
        -> Aggregate using temporary table  (actual time=52.7..52.7 rows=10 loops=1)
            -> Nested loop inner join  (cost=9888 rows=6592) (actual time=1.7..43.8 rows=6592 loops=1)
                -> Nested loop inner join  (cost=7581 rows=6592) (actual time=1.69..35.7 rows=6592 loops=1)
                    -> Nested loop inner join  (cost=5274 rows=6592) (actual time=1.69..25.3 rows=6592 loops=1)
                        -> Index range scan on c using idx_claims_status_submitted over (status = 'SUBMITTED' AND NULL < submitted_at < '2026-10-09 17:01:37'), with index condition: ((c.`status` = 'SUBMITTED') and (c.submitted_at < <cache>((now() - interval 30 day))))  (cost=2967 rows=6592) (actual time=1.68..14.3 rows=6592 loops=1)
                        -> Single-row index lookup on e using PRIMARY (episode_id=c.episode_id)  (cost=0.25 rows=1) (actual time=0.00147..0.00149 rows=1 loops=6592)
                    -> Single-row index lookup on p using PRIMARY (patient_id=e.patient_id)  (cost=0.25 rows=1) (actual time=0.0014..0.00142 rows=1 loops=6592)
                -> Single-row index lookup on a using PRIMARY (agency_id=p.agency_id)  (cost=0.25 rows=1) (actual time=0.00102..0.00106 rows=1 loops=6592)
```

**Observaion:**
- Access type on `claims`: Index range scan (`range`) on `idx_claims_status_submitted`.
- Rows examined vs rows returned: 6,592 claims read, all 6,592 match the filter, 10 rows returned after grouping. Before: 30,000 read.
- Actual time: 52.7 ms total, down from 67.7 ms (about 22% faster).