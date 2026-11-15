// ROO's EMR: Portfolio 4 queries and updates (MongoDB)

const DAY = 86400000;
const cutoff = new Date(Date.now() - 365 * DAY);

// ---------------------------------------------------------------------------
// M1: Full chart for one patient by MRN (relational equivalent: the 4-table join in Q2)
// One read returns the patient, medications, episodes, orders, visits, vitals and notes.
// ---------------------------------------------------------------------------
print('--- M1: patient chart by MRN');
const chart = db.patient_charts.findOne({ agencyId: 3, mrn: 'MRN-000123' });
const sizeInfo = db.patient_charts.aggregate([
  { $match: { agencyId: 3, mrn: 'MRN-000123' } },
  { $project: { _id: 0, bytes: { $bsonSize: '$$ROOT' } } }
]).toArray()[0];
printjson({
  mrn: chart.mrn,
  name: chart.firstName + ' ' + chart.lastName,
  medications: chart.medications.length,
  episodes: chart.episodes.length,
  visits: chart.episodes.reduce((n, e) => n + e.visits.length, 0),
  documentSizeBytes: sizeInfo.bytes
});
printjson(chart.episodes[0].visits[1]);   // one embedded visit with its vitals, note and assessment

// ---------------------------------------------------------------------------
// M2: Missed visits for one agency in the last 12 months (relational equivalent: Q1)
// The first $match uses the index to find candidate patients. $unwind then flattens the
// nested arrays so individual visits can be filtered.
// ---------------------------------------------------------------------------
print('--- M2: missed visits, agency 3, last 12 months');
const missedPipeline = [
  { $match: { agencyId: 3, 'episodes.visits.status': 'MISSED' } },
  { $unwind: '$episodes' },
  { $unwind: '$episodes.visits' },
  { $match: { 'episodes.visits.status': 'MISSED', 'episodes.visits.scheduledStart': { $gte: cutoff } } },
  {
    $project: {
      _id: 0, mrn: 1, lastName: 1,
      visitType: '$episodes.visits.visitType',
      scheduledStart: '$episodes.visits.scheduledStart',
      clinician: '$episodes.visits.clinician.name'
    }
  },
  { $sort: { scheduledStart: -1 } }
];
const missed = db.patient_charts.aggregate(missedPipeline).toArray();
print('rows returned: ' + missed.length);
missed.slice(0, 5).forEach(printjson);

// ---------------------------------------------------------------------------
// M3: Visits by type and status across all patients
// ---------------------------------------------------------------------------
print('--- M3: visits by type and status');
db.patient_charts.aggregate([
  { $unwind: '$episodes' },
  { $unwind: '$episodes.visits' },
  { $group: { _id: { type: '$episodes.visits.visitType', status: '$episodes.visits.status' }, visits: { $sum: 1 } } },
  { $sort: { '_id.type': 1, '_id.status': 1 } }
]).forEach(printjson);

// ---------------------------------------------------------------------------
// M4: Query on a field that only some visits have (wound care, stage 3 or 4)
// In MySQL this would need nullable columns on visits or a separate table.
// ---------------------------------------------------------------------------
print('--- M4: stage 3-4 wounds');
print('charts with a stage 3-4 wound: ' +
  db.patient_charts.countDocuments({ 'episodes.visits.assessment.woundCare.stage': { $gte: 3 } }));
db.patient_charts.aggregate([
  { $match: { 'episodes.visits.assessment.woundCare.stage': { $gte: 3 } } },
  { $unwind: '$episodes' },
  { $unwind: '$episodes.visits' },
  { $match: { 'episodes.visits.assessment.woundCare.stage': { $gte: 3 } } },
  { $project: { _id: 0, mrn: 1, wound: '$episodes.visits.assessment.woundCare' } },
  { $limit: 3 }
]).forEach(printjson);

// ---------------------------------------------------------------------------
// M5: Add a medication (a single-document update, atomic on its own)
// ---------------------------------------------------------------------------
print('--- M5: add a medication');
db.patient_charts.updateOne(
  { agencyId: 3, mrn: 'MRN-000123' },
  { $push: { medications: { drug: 'Apixaban', strength: '5mg', form: 'tablet', dose: '1 tablet', frequency: 'twice daily', startDate: new Date(), stopDate: null } } }
);
printjson(db.patient_charts.findOne({ agencyId: 3, mrn: 'MRN-000123' }, { _id: 0, mrn: 1, medications: 1 }).medications.slice(-2));

// ---------------------------------------------------------------------------
// M6: Update a nested visit note in place (arrayFilters pick the right element)
// ---------------------------------------------------------------------------
print('--- M6: add an addendum to the completed ADMISSION visit note');
const upd = db.patient_charts.updateOne(
  { agencyId: 3, mrn: 'MRN-000123' },
  { $set: { 'episodes.$[].visits.$[v].note.addendum': 'Caregiver training completed.' } },
  { arrayFilters: [{ 'v.visitType': 'ADMISSION', 'v.status': 'COMPLETED' }] }
);
printjson({ matched: upd.matchedCount, modified: upd.modifiedCount });
db.patient_charts.aggregate([
  { $match: { agencyId: 3, mrn: 'MRN-000123' } },
  { $unwind: '$episodes' },
  { $unwind: '$episodes.visits' },
  { $match: { 'episodes.visits.note.addendum': { $exists: true } } },
  { $project: { _id: 0, mrn: 1, visitType: '$episodes.visits.visitType', note: '$episodes.visits.note' } }
]).forEach(printjson);

// ---------------------------------------------------------------------------
// M7: Schema flexibility: a new visit type with its own fields, no ALTER TABLE
// ---------------------------------------------------------------------------
print('--- M7: add a TELEHEALTH visit with new fields');
const start = new Date(Date.now() + 2 * DAY);
db.patient_charts.updateOne(
  { agencyId: 3, mrn: 'MRN-000123' },
  {
    $push: {
      'episodes.0.visits': {
        visitType: 'TELEHEALTH', scheduledStart: start, scheduledEnd: new Date(start.getTime() + 1800000),
        status: 'SCHEDULED', clinician: { staffId: 42, name: 'Grace Okoro', role: 'RN' },
        platform: 'video', connectionRequired: true
      }
    }
  }
);
printjson(db.patient_charts.aggregate([
  { $match: { agencyId: 3, mrn: 'MRN-000123' } },
  { $unwind: '$episodes' },
  { $unwind: '$episodes.visits' },
  { $match: { 'episodes.visits.visitType': 'TELEHEALTH' } },
  { $project: { _id: 0, mrn: 1, visit: '$episodes.visits' } }
]).toArray());

// ---------------------------------------------------------------------------
// M8: The validator rejects an invalid document
// ---------------------------------------------------------------------------
print('--- M8: insert an invalid document');
try {
  db.patient_charts.insertOne({ agencyId: 3, mrn: 'MRN-BAD', firstName: 'Test', lastName: 'Invalid', dob: new Date(), status: 'UNKNOWN', episodes: [] });
  print('inserted (unexpected)');
} catch (e) {
  print('rejected: ' + e.codeName + ' (code ' + e.code + ')');
}

// ---------------------------------------------------------------------------
// M9: Index evidence: examined vs returned
// ---------------------------------------------------------------------------
function summary(label, ex) {
  const s = ex.executionStats;
  printjson({
    query: label,
    returned: s.nReturned,
    keysExamined: s.totalKeysExamined,
    docsExamined: s.totalDocsExamined,
    millis: s.executionTimeMillis
  });
}
print('--- M9: explain');
summary('chart by agencyId + mrn',
  db.patient_charts.find({ agencyId: 3, mrn: 'MRN-000123' }).explain('executionStats'));
summary('mrn only (no agencyId)',
  db.patient_charts.find({ mrn: 'MRN-000123' }).explain('executionStats'));
summary('agencyId + visit status MISSED',
  db.patient_charts.find({ agencyId: 3, 'episodes.visits.status': 'MISSED' }).explain('executionStats'));
