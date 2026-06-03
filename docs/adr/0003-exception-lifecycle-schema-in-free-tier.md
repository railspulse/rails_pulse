# Exception lifecycle columns live in the free tier; UI actions are Pro-gated

`rails_pulse_exception_groups` includes `status`, `resolved_at`, and `preserve` columns in the free tier migration. The UI actions that change these values (resolve, reopen, ignore, preserve toggle) are Pro-gated.

The schema must exist in the free tier because the capture service — which runs in every request — reads `status` to implement the resolved→open auto-reopen transition. If these columns only existed in a Pro migration, free-tier installs would have no column to check and Pro behavior would depend on a schema that may not be present. Separating schema from UI gates keeps the capture path uniform across tiers while still differentiating the product.
