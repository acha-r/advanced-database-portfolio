# Normalisation: ROO's EMR

This document shows how the final design in `schema.sql` was reached by normalising a single paper-style visit sheet up to Third Normal Form (3NF).

## 1. Unnormalised starting point

A home health agency records each visit on one sheet. Stored as one table, it would look like this:

```
VisitSheet(
  visit_id, visit_type, scheduled_start,
  patient_mrn, patient_name, patient_dob,
  agency_name, agency_license_no,
  staff_name, staff_role,
  physician_name, physician_npi,
  med1_name, med1_dose, med2_name, med2_dose, med3_name, med3_dose,
  systolic, diastolic, heart_rate
)
```

Problems with this design:

- **Repeating groups:** a patient on four medications does not fit in three med columns.
- **Update anomaly:** if a nurse's role changes, every past visit row holding her name and role has to be edited.
- **Insert anomaly:** a new patient or drug cannot be stored until a visit exists for it.
- **Delete anomaly:** deleting the only visit for a patient also deletes the patient's details.

## 2. First Normal Form (1NF)

Rule: every column holds a single value and there are no repeating groups.

Change: `med1_*`, `med2_*`, `med3_*` are replaced by one row per medication. The key becomes `(visit_id, drug_name)`.

```
VisitMed(visit_id, drug_name, dose, frequency,
         visit_type, scheduled_start, patient_mrn, patient_name, ...)
```

## 3. Second Normal Form (2NF)

Rule: in 1NF, and no non-key column depends on only part of a composite key.

With key `(visit_id, drug_name)`:

- Visit details (`visit_type`, `scheduled_start`, patient, staff, vitals) depend on `visit_id` only. They move to a visit table.
- Drug details (`strength`, `form`) depend on `drug_name` only. They move to `drugs`.
- `dose` and `frequency` depend on the whole pairing, so they stay in the medication table.

Result: `visits`, `drugs`, and a medication table linking them.

## 4. Third Normal Form (3NF)

Rule: in 2NF, and no non-key column depends on another non-key column.

In the visit table:

| Non-key column | Really depends on | Moved to |
|---|---|---|
| patient_name, patient_dob | patient_mrn | `patients` |
| agency_name, agency_license_no | the agency | `agencies` |
| staff_name, staff_role | the staff member | `staff` |
| physician_name, physician_npi | the physician | `physicians` |

Two further decisions follow from 3NF:

- `visits` does not store `patient_id`. A visit belongs to an episode and an episode belongs to one patient, so the patient is already determined by `episode_id`. Storing it again would create a transitive dependency.
- Medications belong to the patient's medication profile, not to a single visit, so the medication table is `patient_medications` (keyed by patient and drug, with dose and dates). It resolves the many-to-many between `patients` and `drugs`.
- Vitals are split into `vital_signs` because a visit can record more than one set of readings.

## 5. Final design

| Table | Primary key | Depends only on key? |
|---|---|---|
| agencies | agency_id | Yes: name, license, phone, address describe the agency |
| staff | staff_id | Yes: name, role, email describe the staff member; agency_id is a foreign key |
| physicians | physician_id | Yes |
| patients | patient_id | Yes: demographics describe the patient; unique on (agency_id, mrn) |
| episodes | episode_id | Yes: dates and status describe the episode |
| physician_orders | order_id | Yes |
| visits | visit_id | Yes: type, times and status describe the visit |
| visit_notes | note_id | Yes: one note per visit (visit_id is UNIQUE) |
| vital_signs | vital_id | Yes |
| drugs | drug_id | Yes |
| patient_medications | pm_id | Yes: dose, frequency and dates describe the patient-drug pairing |
| claims | claim_id | Yes |
| payments | payment_id | Yes |

Every table has a single-column primary key, so no partial dependencies are possible. Every non-key column describes only its own table's key. The design is in 3NF.

## 6. Deliberate decisions

1. **`visits` stores both scheduled and actual times.** They are different facts: the plan and what happened. Neither can be calculated from the other, and the gap between them is useful (late and missed visits).
2. **`claims` references `episodes`, not `visits`.** In this model, billing is done per care episode, not per visit.
3. **No derived values are stored.** Patient age, total paid per claim and outstanding balance are calculated with queries, so they cannot go out of sync.
4. **Status fields use `ENUM`.** This is simple and compact. A separate lookup table would be more flexible but adds a join to almost every query. The trade-off is that adding a new status needs an `ALTER TABLE`.
5. **`address` is a single text column.** Strictly, a full address is not atomic. Splitting it into street, city, and state was not needed for any operation in this system, so it was kept simple.
6. **`drugs` is a local table.** This keeps foreign key integrity for `patient_medications`. A production system would likely reference an external drug dictionary such as RxNorm.