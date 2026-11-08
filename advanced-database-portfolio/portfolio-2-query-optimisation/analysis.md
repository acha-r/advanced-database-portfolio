## Q1: Missed visits for one agency (last 12 months)

| | Before | After |
|---|---|---|
| Index used on `visits` | `fk_visit_episode` (episode_id only) | `idx_visits_episode_status` (episode_id, status) |
| How `status` is handled | Checked after each visit row is fetched | Part of the index lookup |
| Visits examined | about 21,000 (7 per episode × 3,000 episodes) | about 1,635 (0.545 per episode × 3,000) |
| Rows returned | 806 | 806 |
| Time on the visits step | about 53 ms | about 15 ms |
| Total actual time | 66.4 ms | 28 ms |
| Optimiser cost estimate | 8,945 | 6,418 |

**Result:** about 58% faster (66.4 ms to 28 ms), with about 92% fewer visit rows read. The result set is the same 806 rows in both runs.

**Why it improved:** before, MySQL could only look up visits by `episode_id`, so it fetched every visit for each of the agency's 3,000 episodes and discarded the ones that weren't `MISSED` or outside the date range. With `status` in the index, it fetches only the missed visits for each episode, and the date check trims that to 806.

**What I did not expect:** 
I created `idx_visits_status_sched_staff` for this query, but the optimiser didn't use it. This query starts from one agency's patients and works down through episodes to visits, so looking visits up by `episode_id` is cheaper than scanning a status and date range across all visits. The index that helped was `idx_visits_episode_status`, which was added for Q5b. This shows that an index designed for a query isn't always the one the optimiser picks, and the plan is how to find out.

**What remains:** `scheduled_start` isn't in the index, so about 1,635 rows are still fetched and 806 kept. An index on `(episode_id, status, scheduled_start)` could narrow that further, but this is not tested.

## Q2: Full visit history for one patient, looked up by MRN

| | Before | After |
|---|---|---|
| Access on `patients` | Covering index scan on `uq_patient_mrn`, then a filter on `mrn` | Covering index lookup on `idx_patients_mrn` (mrn = 'MRN-000123') |
| Index entries examined | 20,000 | 1 |
| Rows returned | 14 | 14 |
| Time on the `patients` step | about 13 ms | about 0.02 ms |
| Total actual time | 13.5 ms | 0.22 ms |
| Optimiser cost estimate | 34,111 | 16 |

**Result:** about 60 times faster (13.5 ms to 0.22 ms), and the lookup went from reading 20,000 index entries to reading 1. The result set is the same 14 rows.

**Why it improved:** the existing unique index is on `(agency_id, mrn)`. An index can only be searched from its leftmost column, and this query didn't filter on `agency_id`, so MySQL had to read the whole index and filter on `mrn` afterwards. A separate index on `mrn` lets it jump straight to the one matching entry. Almost all of the original 13.5 ms was that scan. The episode, visit and vitals joins after it already used indexes and took under 0.5 ms before and after.

**Side effect:** the visits lookup now uses `idx_visits_episode_status` instead of `fk_visit_episode`. That composite index starts with `episode_id`, so it covers the same lookup, and MySQL no longer needs the single-column foreign key index. This had no real effect on the result here.

**Caveat:** at 0.22 ms the timing is close to measurement noise, so the exact ratio will vary between runs. The row counts (20,000 examined vs 1) are the reliable evidence.

**Alternative fix:** the query could also include `agency_id` in the filter and use the existing unique index. That's how an application would normally call it, since MRNs are only unique within an agency. The standalone `mrn` index is the right fix only if lookups by MRN alone need to be supported.

## Q3: Outstanding claims per agency (submitted over 30 days ago, still unpaid)

| | Before | After |
|---|---|---|
| Access on `claims` | Full table scan, then filter | Index range scan on `idx_claims_status_submitted` |
| Claims rows read | 30,000 | 6,592 |
| Claims that matched the filter | 6,592 | 6,592 |
| Rows returned | 10 | 10 |
| Time to get the matching claims | about 22 ms | about 14 ms |
| Time on the 3 joins (episodes, patients, agencies) | about 35 ms | about 29 ms |
| Grouping and sorting | about 11 ms | about 9 ms |
| Total actual time | 67.7 ms | 52.7 ms |

**Result:** about 22% faster (67.7 ms to 52.7 ms), with 78% fewer claim rows read (30,000 to 6,592). The result is the same 10 agency rows.

**Why it improved:** the index on `(status, submitted_at)` lets MySQL go straight to the claims with status `SUBMITTED` older than the cutoff, instead of reading every claim and discarding the rest. Only the scan step got meaningfully faster (about 22 ms to 14 ms).

**Why the improvement is modest:** about 29 ms of the 52.7 ms is spent on the three primary key lookups for each of the 6,592 matching claims, and 9 ms on grouping. Those steps process the same 6,592 rows before and after, so an index on the filter can't reduce them. The filter also matches about 22% of the table, which is a lot, so there was less to save than in Q4.

**Cost estimate:** the optimiser's cost for the whole query went up (5,076 to 9,888) even though the real time went down. Before, it estimated the filter would keep 2,464 rows, but 6,592 actually matched. After, its estimate was 6,592, which matches reality. The cost went up because the estimate became accurate. This is a reminder that cost is an estimate and `actual time` is what to judge a plan by.

**What remains:** each matching claim still requires fetching the full row to get `amount` and `episode_id`. A covering index such as `(status, submitted_at, episode_id, amount)` might avoid that, but I haven't tested it.

