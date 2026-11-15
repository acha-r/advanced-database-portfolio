// ROO's EMR: Portfolio 4 seed data for MongoDB (document model)
//
// Run with:
//   mongosh "mongodb://localhost:27017/roos_emr_docs" --file seed-mongo.js
//
// Creates the collection patient_charts: ONE document per patient, with the patient's
// medications, episodes, physician orders, visits, vitals and notes embedded inside it.
// Patients use the same MRNs and agency numbers as the MySQL database (MRN-000001 ...).
// Values come from a seeded generator, so the data is the same every run. Dates are
// relative to today.

const PATIENTS = 5000;
const BATCH = 500;
const DAY = 86400000;
const now = new Date();
const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

// ---- helpers -------------------------------------------------------------
function rng(seed) { // mulberry32: small seeded random number generator
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const pad = (n, w) => String(n).padStart(w, '0');
const pick = (r, list) => list[Math.floor(r() * list.length)];
const between = (r, lo, hi) => lo + Math.floor(r() * (hi - lo + 1));
const chance = (r, p) => r() < p;
const addDays = (d, n) => new Date(d.getTime() + n * DAY);
const addMinutes = (d, n) => new Date(d.getTime() + n * 60000);

// ---- reference data ------------------------------------------------------
const FIRST = ['Joy', 'Kunle', 'Hauwa', 'Peter', 'Sade', 'Musa', 'Chiamaka', 'Yemi', 'Aisha', 'Tony'];
const LAST = ['Johnson', 'Ali', 'Nnamdi', 'Bassey', 'Akin', 'Garba', 'Umeh', 'Wilson', 'Ojo', 'Ekong'];
const STAFF_FIRST = ['Ada', 'Chris', 'Grace', 'Daniel', 'Fatima', 'Samuel', 'Maria', 'Ibrahim', 'Esther', 'David'];
const STAFF_LAST = ['Okafor', 'Bello', 'Adeyemi', 'Eze', 'Musa', 'Nwosu', 'Balogun', 'Okoro', 'Uche', 'Danjuma'];
const DOC_FIRST = ['Peter', 'Amina', 'John', 'Ngozi', 'Paul', 'Halima', 'James', 'Blessing', 'Mark', 'Ruth'];
const DOC_LAST = ['Adebayo', 'Okonkwo', 'Yusuf', 'Ogunleye', 'Ibe', 'Lawal', 'Chukwu', 'Abubakar', 'Obi', 'Salami'];
const ROLES = ['ADMIN', 'RN', 'RN', 'LVN', 'PT', 'OT', 'ST', 'HHA', 'HHA', 'BILLER'];
const DRUGS = [
  ['Lisinopril', 'tablet'], ['Metformin', 'tablet'], ['Amlodipine', 'tablet'], ['Atorvastatin', 'tablet'],
  ['Furosemide', 'tablet'], ['Warfarin', 'tablet'], ['Paracetamol', 'tablet'], ['Ibuprofen', 'tablet'],
  ['Omeprazole', 'capsule'], ['Insulin glargine', 'injection'], ['Salbutamol', 'inhaler'],
  ['Prednisolone', 'tablet'], ['Amoxicillin', 'capsule'], ['Gabapentin', 'capsule'],
  ['Levothyroxine', 'tablet'], ['Carvedilol', 'tablet'], ['Spironolactone', 'tablet'], ['Clopidogrel', 'tablet']
];
const STRENGTHS = ['5mg', '10mg', '25mg', '50mg', '100mg'];
const DOSES = ['1 tablet', '2 tablets', '5 ml', '10 units'];
const FREQUENCIES = ['once daily', 'twice daily', 'three times daily', 'weekly'];
const VISIT_PATTERN = ['ADMISSION', 'SKILLED_NURSING', 'THERAPY', 'SKILLED_NURSING', 'AIDE', 'SKILLED_NURSING', 'DISCHARGE'];
const ORDER_TEXTS = ['Skilled nursing three times weekly for two weeks', 'Physical therapy evaluation and treatment'];
const EXERCISES = ['sit-to-stand', 'seated marching', 'ankle pumps', 'wall push-ups', 'heel raises', 'step-ups'];
const WOUND_SITES = ['sacrum', 'left heel', 'right heel', 'left lower leg', 'right hip'];

// Clinical staff for an agency: same numbering rule as the MySQL seed (20 staff per agency,
// ADMIN and BILLER excluded).
function clinician(r, agencyId) {
  const c = between(r, 0, 15);
  const staffId = (agencyId - 1) * 20 + Math.floor(c / 8) * 10 + (c % 8) + 1;
  return {
    staffId,
    name: STAFF_FIRST[staffId % 10] + ' ' + STAFF_LAST[(staffId * 7) % 10],
    role: ROLES[staffId % 10]
  };
}

function physician(r) {
  const id = between(r, 1, 300);
  return { physicianId: id, npi: '1' + pad(id, 9), name: 'Dr ' + DOC_FIRST[id % 10] + ' ' + DOC_LAST[(id * 3) % 10] };
}

// The assessment differs by visit type. This is the part that varies between documents.
function assessment(r, type) {
  switch (type) {
    case 'ADMISSION':
      return {
        homeSafety: { fallRisk: pick(r, ['low', 'moderate', 'high']), stairs: chance(r, 0.4), oxygenInUse: chance(r, 0.15) },
        caregiverPresent: chance(r, 0.7)
      };
    case 'SKILLED_NURSING': {
      const a = { painScore: between(r, 0, 10), medicationReviewDone: chance(r, 0.9) };
      if (chance(r, 0.25)) {
        a.woundCare = {
          site: pick(r, WOUND_SITES),
          stage: between(r, 1, 4),
          sizeCm: { length: between(r, 1, 8), width: between(r, 1, 6) },
          dressing: pick(r, ['hydrocolloid', 'foam', 'gauze'])
        };
      }
      return a;
    }
    case 'THERAPY':
      return {
        therapyType: pick(r, ['PT', 'OT', 'ST']),
        balanceScore: between(r, 20, 56),
        exercisesCompleted: EXERCISES.filter(() => chance(r, 0.4))
      };
    case 'AIDE':
      return {
        adl: { bathing: chance(r, 0.9), dressing: chance(r, 0.9), feeding: chance(r, 0.6), mobility: chance(r, 0.8) },
        tasksCompleted: between(r, 2, 8)
      };
    default: // DISCHARGE
      return {
        goalsMet: chance(r, 0.8),
        dischargeDestination: pick(r, ['home', 'family care', 'facility']),
        followUpNeeded: chance(r, 0.3)
      };
  }
}

function buildVisit(r, epStart, seq, agencyId) {
  const type = VISIT_PATTERN[seq - 1];
  const scheduledStart = addMinutes(epStart, ((seq - 1) * 8 * 24 + 8 + between(r, 0, 8)) * 60);
  const roll = r();
  const status = scheduledStart > now ? 'SCHEDULED' : roll < 0.88 ? 'COMPLETED' : roll < 0.96 ? 'MISSED' : 'CANCELLED';
  const visit = {
    visitType: type,
    scheduledStart,
    scheduledEnd: addMinutes(scheduledStart, 60),
    status,
    clinician: clinician(r, agencyId)
  };
  if (status === 'COMPLETED') {
    visit.actualStart = addMinutes(scheduledStart, between(r, 0, 29));
    visit.actualEnd = addMinutes(visit.actualStart, 45);
    visit.vitals = {
      systolic: between(r, 100, 159), diastolic: between(r, 60, 89), heartRate: between(r, 55, 104),
      tempC: 36 + between(r, 0, 19) / 10, spo2: between(r, 90, 100)
    };
    visit.note = {
      text: type.replace('_', ' ').toLowerCase() + ' visit completed. Patient assessed, vitals recorded, care plan reviewed.',
      signedAt: addMinutes(visit.actualEnd, 120)
    };
    visit.assessment = assessment(r, type);
  }
  return visit;
}

function buildEpisode(r, start, agencyId) {
  const endDate = addDays(start, 60);
  const doc = physician(r);
  return {
    startDate: start,
    endDate,
    status: endDate < today ? 'CLOSED' : 'OPEN',
    physician: doc,
    orders: ORDER_TEXTS.map((text, i) => {
      const status = chance(r, 0.8) ? 'SIGNED' : chance(r, 0.75) ? 'PENDING' : 'CANCELLED';
      const orderedAt = addMinutes(start, 9 * 60);
      return { text, orderedAt, signedAt: status === 'SIGNED' ? addDays(orderedAt, 1) : null, status };
    }),
    visits: VISIT_PATTERN.map((_, i) => buildVisit(r, start, i + 1, agencyId))
  };
}

function buildPatient(i) {
  const r = rng(i * 7919 + 13);
  const agencyId = ((i - 1) % 10) + 1;
  const roll = r();
  const first = addDays(today, -between(r, 0, 365));
  const episodes = [buildEpisode(r, first, agencyId)];
  if (chance(r, 0.5)) {
    episodes.unshift(buildEpisode(r, addDays(first, -(61 + between(r, 0, 300))), agencyId));
  }
  const medications = [];
  for (let m = 0; m < 3; m++) {
    const [name, form] = pick(r, DRUGS);
    const startDate = addDays(today, -between(r, 0, 399));
    medications.push({
      drug: name, strength: pick(r, STRENGTHS), form,
      dose: pick(r, DOSES), frequency: pick(r, FREQUENCIES),
      startDate, stopDate: chance(r, 0.3) ? addDays(startDate, between(r, 30, 59)) : null
    });
  }
  return {
    agencyId,
    mrn: 'MRN-' + pad(i, 6),
    firstName: pick(r, FIRST),
    lastName: pick(r, LAST),
    dob: addDays(today, -(60 * 365 + between(r, 0, 35 * 365))),
    sex: pick(r, ['F', 'M']),
    status: roll < 0.1 ? 'REFERRED' : roll < 0.6 ? 'ACTIVE' : 'DISCHARGED',
    medications,
    episodes,
    createdAt: now
  };
}

// ---- create the collection with a validator ------------------------------
db.patient_charts.drop();
db.createCollection('patient_charts', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['agencyId', 'mrn', 'firstName', 'lastName', 'dob', 'status', 'episodes'],
      properties: {
        agencyId: { bsonType: 'number', minimum: 1 },
        mrn: { bsonType: 'string' },
        dob: { bsonType: 'date' },
        status: { enum: ['REFERRED', 'ACTIVE', 'DISCHARGED'] },
        episodes: { bsonType: 'array' }
      }
    }
  }
});

// ---- load ----------------------------------------------------------------
let batch = [];
for (let i = 1; i <= PATIENTS; i++) {
  batch.push(buildPatient(i));
  if (batch.length === BATCH || i === PATIENTS) {
    db.patient_charts.insertMany(batch);
    batch = [];
  }
}

// ---- indexes -------------------------------------------------------------
db.patient_charts.createIndex({ agencyId: 1, mrn: 1 }, { unique: true, name: 'uq_agency_mrn' });
db.patient_charts.createIndex({ agencyId: 1, 'episodes.visits.status': 1 }, { name: 'idx_agency_visit_status' });

// ---- summary -------------------------------------------------------------
const stats = db.runCommand({ collStats: 'patient_charts' });
print('patient_charts documents: ' + db.patient_charts.countDocuments({}));
print('average document size (bytes): ' + Math.round(stats.avgObjSize));
print('total data size (MB): ' + (stats.size / 1048576).toFixed(1));
print('indexes: ' + db.patient_charts.getIndexes().map(ix => ix.name).join(', '));
