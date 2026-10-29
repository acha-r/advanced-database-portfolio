-- ROO's EMR for home health agencies
-- Portfolio 1: Database Design and Modelling

DROP DATABASE IF EXISTS roos_emr;
CREATE DATABASE roos_emr CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE roos_emr;

-- Each home health agency is a tenant of ROO's.
CREATE TABLE agencies (
  agency_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(120) NOT NULL,
  license_no  VARCHAR(40)  NOT NULL UNIQUE,
  phone       VARCHAR(20),
  address     VARCHAR(255),
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staff (
  staff_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  agency_id   INT UNSIGNED NOT NULL,
  first_name  VARCHAR(60) NOT NULL,
  last_name   VARCHAR(60) NOT NULL,
  role        ENUM('RN','LVN','PT','OT','ST','HHA','MSW','ADMIN','BILLER') NOT NULL,
  email       VARCHAR(120) NOT NULL UNIQUE,
  license_no  VARCHAR(40),
  is_active   TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT fk_staff_agency FOREIGN KEY (agency_id) REFERENCES agencies(agency_id)
);

-- Referring/certifying physicians are not agency employees, so they sit outside staff.
CREATE TABLE physicians (
  physician_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  npi          CHAR(10) NOT NULL UNIQUE,
  first_name   VARCHAR(60) NOT NULL,
  last_name    VARCHAR(60) NOT NULL,
  phone        VARCHAR(20)
);

CREATE TABLE patients (
  patient_id  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  agency_id   INT UNSIGNED NOT NULL,
  mrn         VARCHAR(20) NOT NULL,
  first_name  VARCHAR(60) NOT NULL,
  last_name   VARCHAR(60) NOT NULL,
  dob         DATE NOT NULL,
  sex         ENUM('F','M','O') NOT NULL,
  phone       VARCHAR(20),
  address     VARCHAR(255),
  status      ENUM('REFERRED','ACTIVE','DISCHARGED') NOT NULL DEFAULT 'REFERRED',
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_patient_mrn UNIQUE (agency_id, mrn),
  CONSTRAINT fk_patient_agency FOREIGN KEY (agency_id) REFERENCES agencies(agency_id)
);

-- A care episode (certification period) for one patient under one certifying physician.
CREATE TABLE episodes (
  episode_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  patient_id   INT UNSIGNED NOT NULL,
  physician_id INT UNSIGNED NOT NULL,
  start_date   DATE NOT NULL,
  end_date     DATE NOT NULL,
  status       ENUM('OPEN','CLOSED') NOT NULL DEFAULT 'OPEN',
  CONSTRAINT chk_episode_dates CHECK (end_date > start_date),
  CONSTRAINT fk_episode_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
  CONSTRAINT fk_episode_physician FOREIGN KEY (physician_id) REFERENCES physicians(physician_id)
);

CREATE TABLE physician_orders (
  order_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  episode_id   INT UNSIGNED NOT NULL,
  physician_id INT UNSIGNED NOT NULL,
  order_text   TEXT NOT NULL,
  ordered_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  signed_at    DATETIME NULL,
  status       ENUM('PENDING','SIGNED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  CONSTRAINT fk_order_episode FOREIGN KEY (episode_id) REFERENCES episodes(episode_id),
  CONSTRAINT fk_order_physician FOREIGN KEY (physician_id) REFERENCES physicians(physician_id)
);

CREATE TABLE visits (
  visit_id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  episode_id      INT UNSIGNED NOT NULL,
  staff_id        INT UNSIGNED NOT NULL,
  visit_type      ENUM('ADMISSION','SKILLED_NURSING','THERAPY','AIDE','RECERTIFICATION','DISCHARGE') NOT NULL,
  scheduled_start DATETIME NOT NULL,
  scheduled_end   DATETIME NOT NULL,
  actual_start    DATETIME NULL,
  actual_end      DATETIME NULL,
  status          ENUM('SCHEDULED','COMPLETED','MISSED','CANCELLED') NOT NULL DEFAULT 'SCHEDULED',
  CONSTRAINT chk_visit_sched CHECK (scheduled_end > scheduled_start),
  CONSTRAINT fk_visit_episode FOREIGN KEY (episode_id) REFERENCES episodes(episode_id),
  CONSTRAINT fk_visit_staff FOREIGN KEY (staff_id) REFERENCES staff(staff_id)
);

-- One clinical note per visit.
CREATE TABLE visit_notes (
  note_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  visit_id   INT UNSIGNED NOT NULL UNIQUE,
  note_text  TEXT NOT NULL,
  signed_at  DATETIME NULL,
  CONSTRAINT fk_note_visit FOREIGN KEY (visit_id) REFERENCES visits(visit_id)
);

CREATE TABLE vital_signs (
  vital_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  visit_id    INT UNSIGNED NOT NULL,
  systolic    SMALLINT UNSIGNED,
  diastolic   SMALLINT UNSIGNED,
  heart_rate  SMALLINT UNSIGNED,
  temp_c      DECIMAL(4,1),
  spo2        TINYINT UNSIGNED,
  recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_spo2 CHECK (spo2 IS NULL OR spo2 BETWEEN 0 AND 100),
  CONSTRAINT fk_vital_visit FOREIGN KEY (visit_id) REFERENCES visits(visit_id)
);

CREATE TABLE drugs (
  drug_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name      VARCHAR(120) NOT NULL,
  strength  VARCHAR(40),
  form      VARCHAR(40),
  CONSTRAINT uq_drug UNIQUE (name, strength, form)
);

-- Resolves the many-to-many between patients and drugs.
CREATE TABLE patient_medications (
  pm_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  patient_id  INT UNSIGNED NOT NULL,
  drug_id     INT UNSIGNED NOT NULL,
  dose        VARCHAR(40) NOT NULL,
  frequency   VARCHAR(40) NOT NULL,
  start_date  DATE NOT NULL,
  stop_date   DATE NULL,
  CONSTRAINT chk_med_dates CHECK (stop_date IS NULL OR stop_date >= start_date),
  CONSTRAINT fk_pm_patient FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
  CONSTRAINT fk_pm_drug FOREIGN KEY (drug_id) REFERENCES drugs(drug_id)
);

CREATE TABLE claims (
  claim_id      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  episode_id    INT UNSIGNED NOT NULL,
  amount        DECIMAL(10,2) NOT NULL,
  submitted_at  DATETIME NULL,
  status        ENUM('DRAFT','SUBMITTED','PAID','DENIED') NOT NULL DEFAULT 'DRAFT',
  CONSTRAINT chk_claim_amount CHECK (amount >= 0),
  CONSTRAINT fk_claim_episode FOREIGN KEY (episode_id) REFERENCES episodes(episode_id)
);

CREATE TABLE payments (
  payment_id  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  claim_id    INT UNSIGNED NOT NULL,
  amount      DECIMAL(10,2) NOT NULL,
  paid_at     DATETIME NOT NULL,
  method      ENUM('INSURER','MEDICARE','PATIENT','OTHER') NOT NULL,
  CONSTRAINT chk_payment_amount CHECK (amount > 0),
  CONSTRAINT fk_payment_claim FOREIGN KEY (claim_id) REFERENCES claims(claim_id)
);