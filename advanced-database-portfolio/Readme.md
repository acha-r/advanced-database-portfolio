# Advanced Database Portfolio

This repository documents a five-part advanced database portfolio built around the ROO's home health EMR case study. The work moves from relational design through tuning and concurrency, then compares that with document-based and distributed database patterns.

The portfolio demonstrates how different database technologies solve different problems in the same domain: healthcare operations, patient records, billing, visits, and distributed availability.

## Portfolio overview

| Portfolio | Focus | Key outcomes |
|---|---|---|
| [portfolio-1-database-design](./portfolio-1-database-design) | Database design and modelling | Conceptual and logical design, schema creation, normalisation, ERD and constraints |
| [portfolio-2-query-optimisation](./portfolio-2-query-optimisation) | Query processing and optimisation | Baseline query plans, indexing, before/after performance analysis |
| [portfolio-3-transactions-concurrency](./portfolio-3-transactions-concurrency) | Transactions and concurrency | Commit/rollback, savepoints, isolation-level behaviour, locking and race conditions |
| [portfolio-4-nosql](./portfolio-4-nosql) | NoSQL and document databases | MongoDB document model for patient charts, embedded structures and index design |
| [portfolio-5-distributed-cloud](./portfolio-5-distributed-cloud) | Distributed and cloud database patterns | MongoDB replica sets, failover behaviour, write concerns and sharding design |

## Project theme

The case study centres on ROO's, a simulated multi-tenant EMR platform for home health agencies. The data model combines:

- Clinical chart information for patients, episodes, visits, vitals and notes
- Scheduling and staff data
- Billing and claim/payment business logic
- Operational needs for consistency, concurrency control and high availability

Across the portfolio, the same domain is explored through different storage and processing strategies, with the aim of understanding when each database model is appropriate.

## What is included

- MySQL schema design and entity-relationship modelling
- SQL scripts for data generation and validation
- Query plan comparisons using EXPLAIN ANALYSE
- Transaction and isolation demonstrations
- MongoDB document modelling and aggregation queries
- Replica set demonstrations and failover analysis
- Screenshots and write-ups for evidence and explanation

## Repository structure

```text
advanced-database-portfolio/
├── Readme.md
├── portfolio-1-database-design/
│   ├── README.md
│   ├── case-study.md
│   ├── normalisation.md
│   ├── schema.sql
│   ├── roo's ERD.png
│   └── screenshots/
├── portfolio-2-query-optimisation/
│   ├── README.md
│   ├── analysis.md
│   ├── execution-before-indexing.md
│   ├── indexes.sql
│   ├── plans-after.md
│   ├── queries.sql
│   ├── seed.sql
│   └── screenshots/
├── portfolio-3-transactions-concurrency/
│   ├── README.md
│   ├── commit-rollback.sql
│   ├── isolation_concurrency.md
│   └── screenshots/
├── portfolio-4-nosql/
│   ├── README.md
│   ├── mongo-queries.js
│   ├── nosql-model.md
│   ├── seed-mongo.js
│   └── screenshots/
├── portfolio-5-distributed-cloud/
│   ├── README.md
│   ├── distributed-design.md
│   ├── replica-set-demo.js
│   ├── replica-set.ps1
│   └── screenshots/
└── ...
```

## Suggested reading order

1. Start with [portfolio-1-database-design](./portfolio-1-database-design)
2. Move to [portfolio-2-query-optimisation](./portfolio-2-query-optimisation)
3. Continue with [portfolio-3-transactions-concurrency](./portfolio-3-transactions-concurrency)
4. Review [portfolio-4-nosql](./portfolio-4-nosql)
5. Finish with [portfolio-5-distributed-cloud](./portfolio-5-distributed-cloud)

This sequence mirrors the conceptual progression from structure to performance to correctness to scale and availability.

## Technologies used

- MySQL
- MongoDB
- SQL scripts and schema files
- PowerShell for MongoDB replica-set setup
- JavaScript for MongoDB data loading and demos
- Documentation and screenshots as evidence of implementation

## Notes

This is an academic/portfolio project focused on learning and demonstration rather than a production deployment. Each portfolio folder contains the source materials, scripts and documentation for that specific topic.

For more detail, read the project-specific README files in each subfolder.
