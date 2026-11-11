# Portfolio 3: Isolation and Concurrency

**Case study:** ROO's, a multi-tenant EMR platform for home health agencies.
**Environment:** MySQL in MySQL Workbench. Two query tabs were used as two separate sessions (connection IDs 9 and 11, `screenshots/`). The server's default isolation level is REPEATABLE READ (`screenshots/isolation-default.png`).

Commit, rollback and savepoint examples are in `commit-rollback.sql`. This document covers the two multi-session experiments: isolation levels and double-booking a clinician.

---

## Part B: Isolation levels

### Scenario

A billing user reads a claim's amount inside a transaction. While that transaction is still open, another user updates the same claim and commits. The question is whether the first transaction sees the change.

### Method

Session A opened a transaction and read the amount for claim 1. Session B then increased the amount by 100 and committed. Session A read the same row again, still inside its transaction. This was done once under each isolation level, and the amount was reset afterwards.

```sql
-- Session A
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- then READ COMMITTED
START TRANSACTION;
SELECT claim_id, amount FROM claims WHERE claim_id = 1;     -- read 1
-- Session B (autocommit):
UPDATE claims SET amount = amount + 100 WHERE claim_id = 1;
-- Session A
SELECT claim_id, amount FROM claims WHERE claim_id = 1;     -- read 2
COMMIT;
```

### Results

| Isolation level | Read 1 | Read 2 (after B's committed update) | Evidence |
|---|---|---|---|
| REPEATABLE READ | [amount] | [same amount] | `b1-read1.png`, `b1-read2.png` |
| READ COMMITTED | [amount] | [amount + 100] | `b2-read1.png`, `b2-read2.png` |

### Explanation

Under READ COMMITTED, the same query run twice in one transaction returned two different values. This is a **non-repeatable read**. Each statement sees the latest committed data, so a change committed by another session between the two reads becomes visible.

Under REPEATABLE READ, the second read returned the same value as the first, even though B's update had already been committed. This is because transactions in this scenerio maintain a consistent snapshot at its first read and keeps using it until the transaction ends. After A committed, a new read showed the updated amount.

The trade-off is between **consistency and freshness**. REPEATABLE READ suits work that needs a stable view for the length of a transaction, such as a billing or audit report that adds up several queries and must be internally consistent. READ COMMITTED suits cases where seeing the newest data matters more, and it holds fewer locks. For ROO's, I would keep the default REPEATABLE READ for reports and financial work, and only use READ COMMITTED where a transaction needs to see other users' changes as they happen.

---

## Part C: Double-booking a clinician

### Scenario

Two schedulers at the same agency book the same clinician (staff 2, an RN) for the same hour (2030-01-15, 10:00 to 11:00) for two different patients (episodes 1 and 11). The application first checks whether the clinician already has an overlapping scheduled visit, and inserts the new visit only if there is none. The schema has no constraint that rejects overlapping visits, so correctness depends on how the check and the insert are run.


```sql
SELECT COUNT(*) AS conflicts
FROM visits
WHERE staff_id = 2
  AND status = 'SCHEDULED'
  AND scheduled_start < '2030-01-15 11:00:00'
  AND scheduled_end   > '2030-01-15 10:00:00';
```

### C1: The concurrency problem (no locking)

**Method.** Both sessions started a transaction and ran the conflict check before either had inserted anything. Then A inserted its visit and committed, and B inserted its visit and committed.

**Result.** Both checks returned 0 conflicts (`c1-conflict-check-a.png`, `c1-conflict-check-b.png`). Both inserts succeeded. The clinician ended up with two overlapping visits at the same time, with visit IDs [id 1] and [id 2] (`c1-double-booked.png`).

**Explanation.** This is a **race condition** in a check-then-insert sequence. The check and the insert are separate steps, and a plain `SELECT` does not take a lock. When B ran its check, A's visit was not yet committed, so B correctly saw no conflict. Both transactions made a decision based on data that was about to change, and nothing stopped the second from proceeding. Isolation levels alone do not fix this. A plain read does not block other writers under either REPEATABLE READ or READ COMMITTED.

### C2: The control mechanism (lock the clinician's row first)

**Method.** Before running the conflict check, each session locked the clinician's row in `staff`:

```sql
START TRANSACTION;
SELECT staff_id FROM staff WHERE staff_id = 2 FOR UPDATE;   -- take the lock
-- conflict check
-- INSERT only if the check returns 0
COMMIT;
```

A took the lock and ran its check (0 conflicts). B then ran the same `FOR UPDATE` statement and **waited**, blocked on A's lock for about [N] seconds (`c2-b-waiting.png`). A inserted its visit and committed, which released the lock. B's statement then completed, and its conflict check returned **1** (`c2-b-conflict.png`). B did not insert and rolled back. Only one visit existed for the clinician in that slot (`c2-one-visit.png`).

**Explanation.** `SELECT ... FOR UPDATE` puts an exclusive lock on the clinician's row, which only one transaction can hold at a time. That forces bookings for the same clinician to run one after another instead of side by side. B's check ran after A had committed, so it saw A's visit and the double booking was avoided. Booking for different clinicians is unaffected, because each takes a lock on a different row.

### Trade-offs and alternatives

- **Waiting:** the second scheduler's request pauses until the first finishes. Transactions that take locks should therefore be short. A blocked statement is cancelled with a lock wait timeout if it waits longer than `innodb_lock_wait_timeout` (50 seconds by default), and the application must handle that error.
- **Scope of the lock:** locking the clinician's row serialises all bookings for that clinician, not only overlapping ones. This is acceptable for the booking volumes in a home health agency, and simpler than locking time ranges.
- An alternative design is to store the schedule as fixed time slots with a `UNIQUE (staff_id, slot_start)` constraint, so the database rejects a second booking of the same slot. 

---

## Evidence

Screenshots are in `screenshots/`