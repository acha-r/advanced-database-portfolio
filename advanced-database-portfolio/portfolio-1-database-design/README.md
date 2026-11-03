## Relationships

### One-to-many (1:N)

| Parent (1) | Child (N) | Foreign key | Meaning |
|---|---|---|---|
| agencies | staff | staff.agency_id | An agency employs many staff |
| agencies | patients | patients.agency_id | An agency has many patients |
| patients | episodes | episodes.patient_id | A patient can have many care episodes |
| physicians | episodes | episodes.physician_id | A physician certifies many episodes |
| episodes | physician_orders | physician_orders.episode_id | An episode has many orders |
| physicians | physician_orders | physician_orders.physician_id | A physician signs many orders |
| episodes | visits | visits.episode_id | An episode has many visits |
| staff | visits | visits.staff_id | A clinician performs many visits |
| visits | vital_signs | vital_signs.visit_id | A visit can record several sets of vitals |
| episodes | claims | claims.episode_id | An episode can have many claims |
| claims | payments | payments.claim_id | A claim can be paid in several payments |

### One-to-one (1:1)

| Table A | Table B | How it is enforced |
|---|---|---|
| visits | visit_notes | visit_notes.visit_id is UNIQUE, so each visit has at most one note |

### Many-to-many (M:N), resolved with a junction table

| Entity A | Entity B | Junction table | Notes |
|---|---|---|---|
| patients | drugs | patient_medications | A patient takes many drugs and a drug is taken by many patients. The junction table also stores dose, frequency, start_date and stop_date |

patients and physicians are also M:N over time (a physician certifies many
patients, and a patient may have different physicians in different episodes).
This is resolved by the episodes table, which links one patient to one physician
for a certification period.
