# A subject's baseline is stored in columns on its own row

_Recorded 2026-11, before 1.0._

Every route, query and job row carries its own baseline: `baseline_p50_duration`, `baseline_p90_duration`, `baseline_p95_duration`, `baseline_sample_count`, `baseline_periods` and `baseline_computed_at`. `BaselineBuilder` rewrites them for every subject after each day summary is written, from `config.baseline_window` of complete day summaries, traffic-weighted the same way the historical comparison weights its baseline. A subject with no day summaries in the window gets NULL percentiles and zero counts.

Two alternatives were rejected.

A separate `rails_pulse_baselines` table with a polymorphic subject keeps derived statistics off the identity tables and takes one migration instead of three sets of columns. But a baseline is strictly one per subject, so the table is those subjects' rows split in two: every read needs a polymorphic join, and because cleanup removes routes, queries and jobs with `delete_all`, the table needs an orphan sweep of its own. On the subject row the baseline is deleted with the subject, and the index tables, which already join the subject table, can compare against it with no extra join.

Computing the baseline on read from summaries needs no schema change and is never stale. It is how `Operations::Compare` works, where one subject is read at a time. It does not hold up for a table that sorts or filters every subject by "slow against its own normal": that aggregates subjects times `baseline_window` day rows on each page load, which an application with tens of thousands of distinct queries cannot afford. A cache in front of it brings staleness back without a column that says how stale.

The costs are six columns on three tables, a builder that must keep running, and a stored number that is up to a day old. `baseline_computed_at` is the same for every subject after a run, so a stopped builder is visible. Readers decide from `baseline_sample_count` and `baseline_periods` whether a baseline rests on enough history to use; the builder applies no minimum. A second window or another baselined metric means more columns.

The stored baseline covers every complete day in the window, including yesterday. `Operations::Compare` keeps computing its own, because its baseline must end where the comparison window begins.
