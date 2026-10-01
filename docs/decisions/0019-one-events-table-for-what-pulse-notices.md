# One `rails_pulse_events` table holds what Pulse notices

_Recorded 2026-09, before 1.0._

`rails_pulse_events` is a single generic table: `kind`, `subject`, `outcome`, `value`, `occurred_at`, `message` and JSON `metadata`, indexed by kind and time and by kind, subject and time. One kind is written into it today, the background writer's once-a-minute heartbeat (`WriterHeartbeat`). A kind whose rows are updated in place rather than appended is registered in `config.event_retention_exempt_kinds`. `CleanupService` prunes everything else by `config.event_retention_period`; the writer prunes its own heartbeats after a day.

The alternative was one table per shape, starting with a typed heartbeats table. Typed columns read better, and the heartbeat's queue depth would be a column rather than a JSON key. It was rejected because the things Pulse notices have nearly the same shape (a kind, a subject, a number, a time, a message, some detail) and because a host should migrate as few tables as possible: with one table, the next thing worth noticing ships without a migration.

The cost is that the heartbeat's secondary fields live in `metadata` and are parsed in Ruby. The reads that need them touch a handful of rows (the latest sample per live process); the read that runs across many rows, drops in the last hour, is a `SUM(value)` over the kind and time index. Heartbeats are most of the rows, so a kind filter is required on every query, and retention is per kind rather than per table.

A `kind` is a string, not an enum, on purpose: a future feature (a summary-job heartbeat, a schema-check notice) adds a kind without a migration.
