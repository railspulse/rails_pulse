# Rails Pulse

A Rails engine that instruments a host app's requests, queries, jobs, and exceptions, storing the data in the host app's own database and surfacing it via a mounted dashboard.

## Language

### Exception tracking

**ExceptionGroup**:
One row per distinct exception site — identified by exception class and the first app-code method in the backtrace. Accumulates a lifetime occurrence count (`occurrence_count` / "Total Seen") and tracks lifecycle status. Never represents a single event. Stores `location` as a Rails.root-relative `file#method` (or `file:line` for anonymous frames) used for fingerprinting and display.
_Avoid_: error, issue, bug

**ExceptionOccurrence**:
A single instance of an exception being raised. Always belongs to an ExceptionGroup. Stores up to 50 parsed backtrace frames, request context, and deploy SHA at the time of the event. Cleanup may delete occurrence rows while the group's lifetime count remains.
_Avoid_: event, record, entry

**Fingerprint**:
A SHA256 hash of `exception_class + relative first_app_frame_file#method_name`. Determines which ExceptionGroup an ExceptionOccurrence belongs to. The file path is relative to `Rails.root` (or the `app/` / `lib/` / `config/` suffix) so it is stable across deploys. Stable across line-number changes; changes only when the method is renamed or moved.
_Avoid_: hash, digest, key

**First app frame**:
The first backtrace frame whose file path matches `/app/`, `/lib/`, or `/config/` and does not match a gem path (`/gems/`, `/rubygems/`, `/bundler/`, `/lib/ruby/`). Used as the canonical location for fingerprinting and grouping.
_Avoid_: stack frame, top frame

**Status** (on ExceptionGroup):
Lifecycle state: `open` (active), `resolved` (fixed), `ignored` (known, not worth acting on). A resolved group auto-reopens to `open` when a new occurrence arrives. An ignored group does not reopen automatically. New occurrences for an ignored group are not stored — the group's `occurrence_count` and `last_seen_at` still update, but no ExceptionOccurrence row is created.
_Avoid_: state, flag

**Preserve** (on ExceptionGroup):
A boolean flag that exempts a group from all automatic cleanup — count-based pruning, orphan deletion, and deletion of that group's occurrence rows. Independent of status; a group can be both `resolved` and preserved.
_Avoid_: pin, keep, retain

### Capture

**ExceptionSubscriber**:
The ActiveSupport::Notifications subscriber that fires on `process_action.action_controller` and passes the exception (if any) to the ExceptionCaptureService. Skips an exception already recorded by JobRunCollector on the same request (`perform_now`).

**JobRunCollector**:
On a failed job, calls ExceptionCaptureService so background-job exceptions are grouped alongside web-request ones. Rake tasks are not captured automatically.

**ExceptionCaptureService**:
The service that parses the backtrace, computes the fingerprint, upserts the ExceptionGroup, creates the ExceptionOccurrence, and handles the resolved→open reopen transition.
