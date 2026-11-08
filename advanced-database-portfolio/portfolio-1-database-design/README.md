# Portfolio 1: Database Design and Modelling

**Case study:** ROO's, a simulated multi-tenant EMR platform used by home health agencies. See `case-study.md` for the full statement.

## Contents

| File / folder | Description |
|---|---|
| `case-study.md` | Organisation, users, data stored and key operations |
| `roo's ERD.png` | ER diagram of the 13 tables, generated from the live schema |
| `schema.sql` | Full MySQL schema: tables, primary keys, foreign keys, constraints |
| `normalisation.md` | Normalisation from an unnormalised visit sheet to 3NF, plus design decisions |
| `screenshots/` | Evidence that the schema ran and the constraints exist |

## How to run

Tested on MySQL 8.0.xx using MySQL Workbench. MySQL 8.0.16 or later is needed for CHECK constraints.

1. Open `schema.sql` in Workbench (File, Open SQL Script).
2. Run the whole script (lightning bolt).
3. Run `USE roos_emr; SHOW TABLES;` to confirm the 13 tables exist.

## How it was tested

- Ran `schema.sql` on a clean server with no errors.
- `SHOW TABLES;` lists all 13 tables (`screenshots/show-tables.png`).
- `SHOW CREATE TABLE visits` confirms the foreign keys and `CHECK` constraints exist as defined (`screenshots/show-create-visits.png`).
- Reverse-engineered the ER diagram from the running database so the diagram matches the schema.

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
| visits | visit_notes | `visit_notes.visit_id` is UNIQUE, so each visit has at most one note |

### Many-to-many (M:N), resolved with a junction table

| Entity A | Entity B | Junction table | Notes |
|---|---|---|---|
| patients | drugs | patient_medications | A patient takes many drugs and a drug is taken by many patients. The junction table also stores dose, frequency, start_date and stop_date |

Patients and physicians are also many-to-many over time. A physician certifies many patients, and a patient may have different physicians in different episodes. The `episodes` table resolves this by linking one patient to one physician for a certification period.

## Design choices

**`physicians` is separate from `staff`.** Referring and certifying physicians are not employees of the agency. They do not log in as agency staff, do not have an agency role, and can certify patients for more than one agency. Keeping them in their own table, identified by a unique NPI, avoids mixing external clinicians with internal ones.

**`UNIQUE (agency_id, mrn)` on `patients`.** Each agency assigns its own medical record numbers, so two agencies can legitimately use the same MRN. The number only has to be unique inside one agency. A unique constraint on `mrn` alone would wrongly block that, and a plain index would allow duplicates within an agency.

**`ENUM` for status and type fields.** Fields like `visits.status` and `claims.status` have small fixed sets of values. `ENUM` stores them compactly and makes the database reject invalid values. The trade-off is that adding a new value requires an `ALTER TABLE`. A lookup table would be more flexible but adds a join to many queries.

**No secondary indexes yet.** Only the indexes MySQL creates automatically (primary keys, `UNIQUE` constraints, and foreign key columns) exist. Other indexes are left out on purpose so Portfolio 2 can capture "before" execution plans first, then add indexes and compare "after" plans.

**Multi-tenancy through `agency_id`.** Each agency is a tenant. `agency_id` sits on `staff` and `patients`, and everything else reaches it through those tables. This also gives a natural shard key for Portfolio 5.

See `normalisation.md` for the normalisation steps and the other design decisions.

## AI use

Tool: Claude (Anthropic).

Used for: Understanding database concepts and design decisions (junction tables, and normal forms), troubleshooting MySQL and PowerShell setup, and producing starter drafts of the normalisation document and README, which I then reviewed and adapted.
