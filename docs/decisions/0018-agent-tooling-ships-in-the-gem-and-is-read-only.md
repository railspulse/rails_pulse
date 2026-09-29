# The JSON API, CLI and MCP server ship in the gem and are read-only

_Recorded 2026-09, for the 0.5 release._

`rails_pulse` ships a token-authenticated JSON API (`app/controllers/rails_pulse/api/v1/`), the `rails-pulse` CLI (`lib/rails_pulse/cli/`) and an MCP server (`lib/rails_pulse/mcp/`) that talks to that API. All three are read-only. The API answers over the same engine mount as the dashboard but never consults the dashboard session: it accepts only `config.api_token`, and with no token configured it refuses every request.

The MCP server and CLI run on the developer's machine, not inside the application, and reach it only over HTTP. They live in the same gem as the API they call, so there is one thing to install and no version skew between the client and the server. Every tool and every command is backed by an endpoint in this gem that returns data: a tool is not shipped ahead of its endpoint, so an agent never meets one that can only say what is missing.

The alternative was to sell the tooling separately from the gem. It was rejected because the tooling is distribution, not product: every APM will have an MCP server, the data it reads sits in the host's own database under an open schema, and the diagnosis workflow an agent runs (deploy, slow requests, endpoint, queries, jobs) should work for every install without anything extra.

Read-only is a promise, not an implementation detail. `MCP::Tool` annotations declare `read_only_hint`, the controllers expose only index and show actions, and nothing under the API namespace may write. A feature that needs an agent to change the application belongs in a workflow the customer runs (a PR from their own agent runner), never in these endpoints. The other constraint this inherits is decision 0006: the API serves the host's own database and sends nothing anywhere else.
