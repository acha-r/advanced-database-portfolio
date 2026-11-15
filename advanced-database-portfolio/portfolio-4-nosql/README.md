# Portfolio 4: NoSQL and Advanced Data Models

This portfolio models the clinical chart as a document in MongoDB. Each patient is one document with medications, episodes, orders, visits, vitals and notes embedded inside it. Billing, scheduling and the transactional work from Portfolios 2 and 3 stay in the relational database.

## Contents

| File / folder | Description |
|---|---|
| `nosql-model.md` | The document model, what is embedded and why, results of each operation, and the suitability discussion |
| `seed-mongo.js` | Creates the `patient_charts` collection with a validator, loads 5,000 patient documents and builds the indexes |
| `mongo-queries.js` | Queries and updates M1 to M9 |
| `screenshots/` | Compass views and the output of each operation |

## How to run

1. Load the data. From PowerShell, in the folder that holds the script:

   ```powershell
   mongosh "mongodb://localhost:27017/roos_emr_docs" --file seed-mongo.js
   ```

   The database name in the address is what makes the data go into `roos_emr_docs`. The script drops and recreates `patient_charts`, so it is safe to re-run. It prints the document count, the average and total size, and the index names.
3. Start an interactive session in the same database:

   ```powershell
   mongosh "mongodb://localhost:27017/roos_emr_docs"
   ```

4. Paste the first lines of `mongo-queries.js` (the `DAY` and `cutoff` constants), then paste one block (M1 to M9) at a time. Each `const` can only be declared once per session, so restart the session to re-run a block. Alternatively run the whole file with `mongosh "mongodb://localhost:27017/roos_emr_docs" --file mongo-queries.js`.

M5 to M7 modify the chart for `MRN-000123`. Re-running `seed-mongo.js` resets it.

## Data

`seed-mongo.js` generates the documents with a seeded random generator, so the content is the same on every run, except that dates are relative to the day it is run. Patients use the same MRN and agency numbering as the MySQL database (`MRN-000001` onwards, 10 agencies). The documents were generated with the same structure of episodes and visits, not exported from MySQL, so individual visit details differ between the two databases.

## Operations

| Ref | What it demonstrates |
|---|---|
| M1 | Reading a patient's whole chart in one lookup (the relational equivalent needs a four-table join) |
| M2 | Missed visits for an agency in the last 12 months, using `$unwind` to flatten nested arrays (compare Q1 in Portfolio 2) |
| M3 | Aggregation: visit counts by type and status |
| M4 | Querying a field that only some visits have (wound care stage) |
| M5 | Adding a medication with `$push`, an atomic single-document update |
| M6 | Updating one nested visit note in place with `arrayFilters` |
| M7 | Adding a new visit type with new fields and no schema change |
| M8 | The `$jsonSchema` validator rejecting an invalid document |
| M9 | `explain` output: index use, keys and documents examined |

## Indexes

| Index | Purpose |
|---|---|
| `uq_agency_mrn (agencyId, mrn)`, unique | Chart lookup by MRN. MRNs are unique only within an agency |
| `idx_agency_visit_status (agencyId, episodes.visits.status)` | Finds an agency's patients with visits in a given status |

