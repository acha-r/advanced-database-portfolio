// ROO's EMR: Portfolio 5 replica set demos (MongoDB)
//
// Connect to the replica set (all three nodes, so the driver follows the primary):
//   mongosh "mongodb://localhost:27018,localhost:27019,localhost:27020/roos_emr_docs?replicaSet=roos-rs"
//
// Paste one block at a time. Blocks marked [PowerShell] are run in a separate PowerShell
// window with replica-set.ps1. The data is loaded first by running seed-mongo.js against the
// same connection string:
//   mongosh "mongodb://localhost:27018,localhost:27019,localhost:27020/roos_emr_docs?replicaSet=roos-rs" --file seed-mongo.js

// ---------------------------------------------------------------------------
// Helper: one line per node (name, role, health)
// ---------------------------------------------------------------------------
function members() {
  return rs.status().members.map(m => ({ name: m.name, state: m.stateStr, health: m.health }));
}

// ---------------------------------------------------------------------------
// D1: Replica set topology
// Expected: one PRIMARY and two SECONDARY nodes, all health 1.
// ---------------------------------------------------------------------------
printjson(members());

// ---------------------------------------------------------------------------
// D2: Replication of a write
// Write on the primary with majority acknowledgement, then read the same chart from a secondary.
// ---------------------------------------------------------------------------
db.patient_charts.updateOne(
  { agencyId: 3, mrn: 'MRN-000123' },
  { $set: { 'replicationTest': new Date().toISOString() } },
  { writeConcern: { w: 'majority', wtimeout: 5000 } }
);
db.getMongo().setReadPref('secondary');
printjson({ readPreference: db.getMongo().getReadPrefMode(),
            servedBySecondary: db.patient_charts.findOne({ agencyId: 3, mrn: 'MRN-000123' }, { _id: 0, mrn: 1, replicationTest: 1 }) });
db.getMongo().setReadPref('primary');

// ---------------------------------------------------------------------------
// D3: Failover
// 1. Find the primary:
printjson(members());
// 2. [PowerShell] stop the node whose state is PRIMARY (use its port), e.g.
//      .\replica-set.ps1 -Action stop -Port 27018
// 3. Wait 10 to 15 seconds, then paste again. Expected: one of the secondaries is now PRIMARY and
//    the stopped node shows health 0 / not reachable.
printjson(members());
// 4. The application keeps working: write through the same connection (the driver finds the new primary).
db.patient_charts.updateOne(
  { agencyId: 3, mrn: 'MRN-000123' },
  { $set: { 'failoverTest': new Date().toISOString() } },
  { writeConcern: { w: 'majority', wtimeout: 5000 } }
);
// 5. [PowerShell] bring the old node back:  .\replica-set.ps1 -Action start -Port 27018
//    After a short time it rejoins as a SECONDARY and catches up.
printjson(members());

// ---------------------------------------------------------------------------
// D4: Tunable consistency: write concern with one node down
// Prerequisite: one node is stopped, two are running.
// w: 'majority' (2 of 3) can still be acknowledged. w: 3 cannot, because it needs all three nodes.
// ---------------------------------------------------------------------------
const r1 = db.patient_charts.updateOne(
  { agencyId: 3, mrn: 'MRN-000123' },
  { $set: { 'wcTest': 'majority' } },
  { writeConcern: { w: 'majority', wtimeout: 3000 } }
);
printjson({ writeConcern: 'majority', acknowledged: r1.acknowledged, modified: r1.modifiedCount });

try {
  db.patient_charts.updateOne(
    { agencyId: 3, mrn: 'MRN-000123' },
    { $set: { 'wcTest': 'all three' } },
    { writeConcern: { w: 3, wtimeout: 3000 } }
  );
  print('w:3 acknowledged (unexpected with a node down)');
} catch (e) {
  print('w:3 failed: ' + (e.codeName || e.name) + ' (code ' + e.code + ')');
}

// ---------------------------------------------------------------------------
// D5: Availability vs consistency: only one node left
// Prerequisite: [PowerShell] stop two nodes so a single node is running.
// With no majority, that node cannot be primary, so it refuses writes. Reads from it still work,
// but may be slightly behind. Connect directly to the surviving node (example port 27019):
//   mongosh "mongodb://localhost:27019/roos_emr_docs?directConnection=true&readPreference=secondaryPreferred"
// ---------------------------------------------------------------------------
printjson(db.hello().isWritablePrimary);   // expected: false
printjson(db.patient_charts.countDocuments({}));   // read succeeds
try {
  db.patient_charts.updateOne({ agencyId: 3, mrn: 'MRN-000123' }, { $set: { 'outageTest': true } });
  print('write succeeded (unexpected)');
} catch (e) {
  print('write refused: ' + (e.codeName || e.name) + ' (code ' + e.code + ')');
}
