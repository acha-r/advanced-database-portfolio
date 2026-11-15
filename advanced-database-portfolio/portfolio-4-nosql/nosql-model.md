# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** ROO's, a multi-tenant EMR platform for home health agencies.
**NoSQL model:** database `roos_emr_docs`, collection `patient_charts`.
**Scripts:** `seed-mongo.js` (creates and loads the collection) and `mongo-queries.js` (queries and updates M1 to M9).

---

## 1. Why a document model for part of ROO's

The relational design from Portfolio 1 stores a patient's clinical record across several tables (`patients`, `episodes`, `visits`, `visit_notes`, `vital_signs`, `patient_medications`, `physician_orders`). Showing one patient's chart in Q2 needed a four-table join. In practice, a clinician opens a chart, reads it as a whole, and adds to it. A document model stores that whole chart as one document, so the common read is a single lookup.

Clinical documentation also varies by visit type. An admission records a home safety check, a nursing visit records a pain score and sometimes a wound assessment, a therapy visit records balance scores and exercises, and an aide visit records a daily living checklist. In MySQL this would need many nullable columns on `visits`, a table per visit type, or an entity-attribute-value structure. In a document, each visit simply carries the fields that apply to it.

**What stays relational.** Billing (`claims`, `payments`), scheduling and the concurrency control from Portfolio 3 (double booking prevented by locking) need constraints, joins across entities and multi-row transactions. The relational database remains the right home for those. The result is a split design (polyglot persistence): MySQL for transactional and financial data, MongoDB for the clinical chart.

---

## 2. Document design

One document per patient. Medications, episodes, orders, visits, vitals and notes are embedded.

```json
{
  "agencyId": 3,
  "mrn": "MRN-000123",
  "firstName": "...", "lastName": "...", "dob": "ISODate", "sex": "F", "status": "ACTIVE",
  "medications": [
    { "drug": "Lisinopril", "strength": "10mg", "form": "tablet",
      "dose": "1 tablet", "frequency": "once daily", "startDate": "ISODate", "stopDate": null }
  ],
  "episodes": [
    {
      "startDate": "ISODate", "endDate": "ISODate", "status": "CLOSED",
      "physician": { "physicianId": 17, "npi": "1000000017", "name": "Dr ..." },
      "orders": [ { "text": "...", "orderedAt": "ISODate", "signedAt": "ISODate", "status": "SIGNED" } ],
      "visits": [
        {
          "visitType": "SKILLED_NURSING", "status": "COMPLETED",
          "scheduledStart": "ISODate", "scheduledEnd": "ISODate",
          "actualStart": "ISODate", "actualEnd": "ISODate",
          "clinician": { "staffId": 12, "name": "...", "role": "RN" },
          "vitals": { "systolic": 128, "diastolic": 78, "heartRate": 72, "tempC": 36.8, "spo2": 97 },
          "note": { "text": "...", "signedAt": "ISODate" },
          "assessment": { "painScore": 3, "medicationReviewDone": true,
                          "woundCare": { "site": "sacrum", "stage": 3, "sizeCm": { "length": 4, "width": 3 } } }
        }
      ]
    }
  ]
}
```

### Embed or reference

| Relational table | In the document | Reason |
|---|---|---|
| `patients` | Top-level fields | The document is the patient |
| `patient_medications` and `drugs` | `medications[]`, with the drug name, strength and form copied in | A patient has a few medications, always read with the chart. The drug details are stored as they were when prescribed, so a later change to a drug record does not rewrite history |
| `episodes` | `episodes[]` | A patient has a small number of episodes |
| `physicians` | `episodes[].physician` (id, NPI, name) | Copied into each episode because the episode is certified by that physician at that time |
| `physician_orders` | `episodes[].orders[]` | Orders belong to one episode and are read with it |
| `visits` | `episodes[].visits[]` | About 7 per episode, bounded |
| `visit_notes` | `visits[].note` | One note per visit |
| `vital_signs` | `visits[].vitals` | Read with the visit |
| `staff` | `visits[].clinician` (id, name, role) | Copied as a snapshot. The clinician's full record stays in MySQL |
| `claims`, `payments` | Not in MongoDB | Financial data that needs ACID transactions and constraints |

Embedding works here because every embedded array is **bounded** (a few episodes, about 7 visits each) and is nearly always read together with the patient. Large arrays that grow without limit, or data shared by many documents, would be referenced instead.

### Schema flexibility and validation

- Each visit's `assessment` has different fields depending on `visitType`. Only some nursing visits include `woundCare`.
- The collection has a `$jsonSchema` validator that requires `agencyId`, `mrn`, `firstName`, `lastName`, `dob`, `status` and `episodes`, and restricts `status` to `REFERRED`, `ACTIVE` or `DISCHARGED`. It enforces the essentials while leaving the clinical detail flexible.

### Indexes

| Index | Purpose |
|---|---|
| `uq_agency_mrn (agencyId, mrn)`, unique | Lookup of a chart by MRN. MRNs are unique only within an agency, as in the relational design |
| `idx_agency_visit_status (agencyId, episodes.visits.status)` | Finds an agency's patients that have visits with a given status. This is a multikey index because `visits` is an array |

---

## 3. Data used

The collection holds [N] patient documents (`screenshots/collection-count.png`) with an average size of [avg] bytes per document and [total] MB in total. Patients use the same MRN and agency numbering as the MySQL database. The documents were generated by `seed-mongo.js` with the same structure of episodes and visits, rather than exported from MySQL, so the individual visit details differ between the two databases.

---

## 4. Operations and results

| Ref | Operation | Result | Evidence |
|---|---|---|---|
| M1 | Fetch a patient's whole chart by `agencyId` and `mrn` | [episodes] episodes, [visits] visits and [medications] medications in one read; document size [bytes] bytes | `m1-chart.png` |
| M2 | Missed visits for agency 3 in the last 12 months (aggregation with `$unwind`) | [rows] rows | `m2-missed-visits.png` |
| M3 | Visit counts by type and status (aggregation with `$group`) | [rows] groups | `m3-visits-by-type.png` |
| M4 | Charts with a stage 3 or 4 wound (a field only some visits have) | [count] charts | `m4-wounds.png` |
| M5 | Add a medication to a chart (`$push`) | The new medication appears in the array | `m5-medication.png` |
| M6 | Add an addendum to one nested visit note (`arrayFilters`) | [matched]/[modified] | `m6-addendum.png` |
| M7 | Add a `TELEHEALTH` visit with new fields (`platform`, `connectionRequired`) | Stored and queryable with no schema change | `m7-telehealth.png` |
| M8 | Insert a document with `status: 'UNKNOWN'` and no `episodes` | Rejected by the validator | `m8-validation.png` |
| M9 | `explain` on the MRN lookup, an MRN-only lookup and the visit-status query | [fill in keys examined, documents examined and time for each] | `m9-explain.png` |

---

## 5. Suitability: strengths and trade-offs

**Where the document model fits.**

- **One read for a whole chart.** M1 returns what Q2 needed four tables for, with no joins.
- **Flexible clinical content.** M4 and M7 show fields that exist only on some visits, and a new visit type added without changing a schema.
- **Single-document updates are atomic.** M5 and M6 change one chart in one operation, without a multi-table transaction.
- **Natural fit for the data's shape.** The chart is a tree (patient, episodes, visits), and the document keeps it as one.

**Where it is weaker.**

- **Cross-patient reporting is clumsier.** M2 needs two `$unwind` stages to flatten the arrays before filtering, where the SQL in Q1 was a plain join with a WHERE clause. Reports across many patients suit SQL better.
- **Duplication.** Clinician names, physician names and drug details are copied into the chart. This keeps history accurate but means a correction has to be applied in more than one place.
- **Document size limit.** A MongoDB document is limited to 16 MB. A chart averages [avg] bytes here, so the limit is far away, but a chart that accumulated years of episodes would need older episodes moved into a separate collection.
- **Weaker guarantees for relationships.** The database does not enforce that `clinician.staffId` points at a real staff member, which a foreign key does in MySQL.
- **Multi-entity consistency.** Updating something that spans charts and billing together would need coordination across two databases.

**Conclusion.** The clinical chart suits a document store, because it is read and written as a unit and its content varies by visit type. Billing and scheduling are better kept in the relational database, where constraints, joins and the locking from Portfolio 3 apply. Using each for what it is good at is a better fit than moving everything to either.

---