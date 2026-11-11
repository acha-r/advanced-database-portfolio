
# Portfolio 3: Transactions and Concurrency

This portfolio demonstrates transactions (commit, rollback, savepoints), isolation levels, and a concurrency problem with its control mechanism, using the ROO's schema and the data loaded in Portfolio 2.

## Environment

MySQL in MySQL Workbench. The database is `roos_emr` as created by `../portfolio-1-database-design/schema.sql` and populated by `../portfolio-2-query-optimisation/seed.sql`. The server's default isolation level, REPEATABLE READ, was used unless a test says otherwise.

## What each part demonstrates

| Part | Scenario | Concept |
|---|---|---|
| A1 | Admitting a patient: patient, episode and first visit saved in one transaction | Commit, atomicity |
| A2 | An invalid episode date fails a `CHECK` constraint part-way through an admission | Rollback, consistency |
| A3 | Undoing one update inside a transaction while keeping an earlier insert | Savepoint |
| B | Reading a claim twice while another session changes it, under REPEATABLE READ and READ COMMITTED | Isolation levels, non-repeatable read |
| C1 | Two schedulers book the same clinician at the same time and both succeed | Race condition |
| C2 | The same booking with the clinician's row locked using `SELECT ... FOR UPDATE` | Locking as a control mechanism |

## How to run

1. Make sure `roos_emr` exists and is seeded (`SELECT COUNT(*) FROM visits;` should return about 210,000).
2. Run `commit-rollback.sql` one statement at a time. The deliberate failure in A2 would stop a whole-script run.
3. For parts B and C, open two query tabs and confirm they are separate sessions by running `SELECT CONNECTION_ID();` in each (the two numbers must differ).
