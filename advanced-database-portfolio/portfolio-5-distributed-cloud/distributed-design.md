# Portfolio 5: Distributed and Cloud Database Exercise

**Case study:** ROO's, a multi-tenant EMR platform for home health agencies, with the clinical chart stored in MongoDB (Portfolio 4) and billing and scheduling in MySQL.
**Scripts:** `replica-set.ps1` (starts and stops a local 3-node replica set) and `replica-set-demo.js` (demo steps D1 to D5).

---

## 1. Why distribution matters for ROO's

An EMR is used by clinicians in the field and must stay available. A nurse who cannot open a chart during a visit is a patient-care problem, not just an inconvenience. The data is also sensitive, valuable and growing (every visit adds vitals, notes and assessments). That raises three questions:

- **Availability:** what happens when a database server fails?
- **Consistency:** after a write is confirmed, will every reader see it?
- **Scale:** what happens when one server can no longer hold or serve all agencies' data?

This portfolio answers them for the MongoDB chart store with a replica set that was built and tested, and a sharding design that was analysed but not deployed.

---

## 2. Deployment: a three-node replica set

**Setup.** A MongoDB replica set named `roos-rs` with three nodes on one Windows machine, on ports 27018, 27019 and 27020, each with its own data directory (`replica-set.ps1`, `screenshots/d1-members.png`). In production the nodes would sit on separate servers, ideally in separate availability zones, so one failure cannot take out more than one node. A single machine shows the behaviour but not the physical isolation.

**How it works.**

- One node is the **primary** and takes all writes. The other two are **secondaries**, which copy the primary's operation log (oplog) and apply the same changes.
- If the primary becomes unreachable, the secondaries hold an **election**. A node needs votes from a **majority** of the voting members (2 of 3) to become primary.
- Because a majority is required, a three-node set tolerates the loss of one node. An odd number of members avoids ties.

---

## 3. Replication and failover results

### D2: replication

A write to chart `MRN-000123` was made on the primary with `w: 'majority'`, then the same chart was read with the read preference set to `secondary`. The secondary returned the new field (`screenshots/d2-secondary-read.png`).

### D3: failover

The primary (port 27018) was stopped with a hard kill to simulate a crash.

| Event | Observation | Evidence |
|---|---|---|
| Before | Port [port] PRIMARY, the other two SECONDARY | `d3-before.png` |
| About [N] seconds after the kill | Port [new primary port] became PRIMARY, port [old port] unreachable | `d3-after.png` |
| Write after the election | The write through the same connection succeeded without changing the connection string | `d3-write.png` |
| Old node restarted | It rejoined as SECONDARY and caught up | `d3-rejoined.png` |

**Explanation.** The driver was given all three addresses and the replica set name, so it discovered the new primary by itself (after a short pause).  The election took about 10 seconds, which fits MongoDB's default election timeout.

---

## 4. Consistency and availability trade-offs

### D4: write concern with one node down

With one node stopped and two running:

| Write concern | Result | Evidence |
|---|---|---|
| `w: 'majority'` (2 of 3) | Acknowledged | `d4-majority.png` |
| `w: 3` (all nodes) | Failed after the 3 second timeout: [error name and code] | `d4-w3-timeout.png` |

**Explanation.** Write concern sets how many nodes must confirm a write before the client is told it succeeded. A stronger setting gives a stronger durability guarantee but is less available, since `w: 3` stops working as soon as any node is down. A weaker setting (`w: 1`) is faster and survives more failures, but a write that only the primary has confirmed can be **rolled back** if that primary fails before the write reaches a secondary. A timeout on `w: 3` does not mean the write was undone. It means not every node confirmed it. For clinical data I would use `w: 'majority'` as the default, which also matches the default in recent MongoDB versions.

### D5: only one node left

With two of three nodes stopped, the remaining node ran as a SECONDARY and refused writes ([error name and code], `d5-write-refused.png`). Reads from it still worked (`d5-read.png`).

**Explanation.** One node of three is not a majority, so it cannot safely elect itself primary. If it could, the two stopped nodes might come back with a different copy of the data (a split brain). MongoDB therefore chooses **consistency over availability for writes** when the cluster is partitioned or mostly down. This is the CAP trade-off: during a partition, a system must give up either consistency or availability, and a replica set gives up write availability. Reads from a secondary remain possible, but may return slightly stale data, so a system must decide which screens can tolerate stale reads (for example, a historical chart view) and which cannot (for example, checking current medications before a dose).

---

## 5. Sharding design (analysed, not deployed)

Replication copies the same data to several nodes. It improves availability but does not increase how much data a cluster can hold or how many writes it can take. **Sharding** splits the data across several replica sets (shards), each holding part of it. A sharded cluster also needs config servers and `mongos` routers, so it was not deployed in this exercise.

### Choosing a shard key for `patient_charts`

| Candidate | Distribution | Query targeting | Verdict |
|---|---|---|---|
| `agencyId` | Poor: only 10 values, and agencies differ in size. One large agency becomes one chunk that cannot be split further | Good for per-agency queries | Rejected: low cardinality |
| `mrn` (ranged) | Even in count, but new MRNs increase steadily, so inserts all hit the newest chunk | Queries by agency must ask every shard | Rejected: insert hotspot, no tenant locality |
| `mrn` (hashed) | Very even | Every per-agency query goes to every shard | Rejected: loses tenant locality |
| **`{ agencyId: 1, mrn: 1 }`** | Good: a large agency can still be split by MRN | Queries with `agencyId` go to the shards that hold that agency | **Chosen** |

**Why the compound key.** It keeps an agency's charts together, so most queries (one chart by agency and MRN, an agency's missed visits) go to one shard or a few, and it lets a big agency be split by MRN. It also matches the existing unique index `uq_agency_mrn (agencyId, mrn)`, which matters because a unique index on a sharded collection must begin with the shard key.

**Effect on the queries from Portfolio 4.**

- **M1** (`agencyId` and `mrn`): targeted to one shard.
- **M2** (filters on `agencyId`): targeted to the shards that hold agency 3.
- **M3** (counts across all agencies): scatter-gather across every shard and merged by `mongos`.

**Zone sharding.** Agencies could be pinned to particular shards, for example to keep an agency's data in a region required by a regulator or contract.


## 7. Summary

| Topic | Finding |
|---|---|
| Replication | Writes on the primary appeared on the secondaries |
| Availability | After the primary was killed, a new primary was elected in about [N] seconds and writes continued |
| Consistency | `w: 'majority'` stayed available with one node down; `w: 3` did not |
| Partition behaviour | With one of three nodes left, writes were refused but reads worked (consistency over write availability) |
| Sharding | Compound key `{ agencyId, mrn }` keeps tenants together and splits large agencies |
