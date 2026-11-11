# Portfolio 2: Query Processing and Optimisation

This portfolio loads a realistic volume of data into the Portfolio 1 schema, measures the queries with `EXPLAIN ANALYZE`, adds indexes, and compares the plans before and after.

## Contents

| File / folder | Description |
|---|---|
| `seed.sql` | Generates about 800,000 rows (210,000 visits is the largest table) |
| `queries.sql` | The baseline queries |
| `indexes.sql` | The indexes added after the baseline plans were saved |
| `plans-before.md` | `EXPLAIN ANALYZE` output for each query before indexing |
| `plans-after.md` | `EXPLAIN ANALYZE` output for each query after indexing |
| `analysis.md` | Before/after comparison, explanation and conclusions for each query |
| `screenshots/` | Row counts, query results and index listing |

## How to run

Tested on MySQL using MySQL Workbench. (MySQL 8.0.18 or later is needed for `EXPLAIN ANALYZE`).

1. Create a fresh database by running `../portfolio-1-database-design/schema.sql`.
2. Run `seed.sql`. The seed relies on auto-increment IDs starting at 1, so always run it on a freshly created schema. If Workbench disconnects, raise the DBMS connection read timeout (Edit, Preferences, SQL Editor).
3. Run each query in `queries.sql`, once normally and once with `EXPLAIN ANALYZE` in front. Save the plan text as the baseline.
4. Run `indexes.sql`.
5. Run the same queries with `EXPLAIN ANALYZE` again and compare.

## Data volume

Row counts after seeding are in `screenshots/row-counts.png`. The main tables are 20,000 patients, 30,000 episodes, 210,000 visits, about 178,000 visit notes and vital signs, 60,000 patient medications and 30,000 claims.


## Summary of results

Full detail and explanations are in `analysis.md`.

| Query | Main change |
|---|---|
| Q1 | Optimiser used `idx_visits_episode_status`, not the index built for it |
| Q2 | Index scan of 20,000 entries became a direct lookup |
| Q3 | Full scan became an index range scan; modest gain, most time is in the joins |
| Q5b | Corrected query; see note below |


## Limits of this analysis

- All timings are from one machine and one run each (the last of three). Small differences, especially under 1 ms, are within noise.
