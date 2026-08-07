# Exception capture is scoped to web requests only

The ExceptionSubscriber hooks into `process_action.action_controller` and captures only exceptions that bubble up through a Rails controller action. Background jobs, Rake tasks, and other out-of-band execution contexts are not captured automatically.

`ExceptionCaptureService.capture` is a public API that callers can invoke directly, but there is no automatic capture outside the request cycle. This is a deliberate v1 scope boundary — job adapters already exist in Rails Pulse and job-exception capture is a natural follow-on, but it is not part of this feature.

Capture is synchronous on the request thread (group upsert + occurrence insert). Request performance tracking can run async; exception capture does not yet. That keeps v1 simple and correct under concurrency. The trade-off is added DB latency on failing requests during an error storm — operators can set `track_exceptions = false` to opt out.
