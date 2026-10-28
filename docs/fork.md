# Fork scope

This fork keeps only the open-source, local Runtime Intelligence MCP server of
Tidewave for Phoenix. It is currently at upstream 0.9.2 (27 Oct 2026), ported
by hand from fork point `ccd3b9d` (upstream v0.8.1). Upstream is never merged
or rebased.

## Tools

`project_eval`, `get_logs`, `get_source_location`, `get_docs`, `execute_sql_query`.

## Deliberately excluded

- Tidewave Web, toolbar injection, CSP and response rewriting (`ae66b47`)
- Connect, browser sessions, `browser_eval`, `create_design_canvas`
- control WebSockets, uploads, Teams configuration
- request silencing (`4388f3b`, `6ab5727`: toolbar only)
- `get_ecto_schemas` (removed upstream in `292c316`), the Ash tool, tool profiles
- `Tidewave.Agent.frontend_status`, `frontend_check`, `ecto_schemas`, `ash_resources`

Browser verification belongs to external tooling such as `agent-browser`.

## Ours only

- `Tidewave.Agent` (`project`, `logs`, `clear_logs`, `sql`, `docs`, `source`, `routes`)
- scoped, non-destructive log retrieval
- Elixir 1.20 floor
- `execute_sql_query` is read-only: it runs in a transaction that is
  `SET TRANSACTION READ ONLY` and always rolled back. A `SELECT 1` follows the
  `SET` to take the snapshot; before that, Postgres lets a query switch the
  transaction back to read-write. Only PostgreSQL repos are supported; any other
  adapter is refused without running the query (fail closed). Reason: dev
  databases may be production copies with no backup.

## Ported from upstream

| Upstream commit | What | Here |
| --- | --- | --- |
| `8dbb44e` | MCP core split from HTTP | `lib/tidewave/mcp/handler.ex`, `lib/tidewave/mcp/http.ex` (browser-tool options dropped) |
| `6f7272d` | stdio transport and `mix tidewave.proxy` | `lib/tidewave/mcp/stdio.ex`, `lib/mix/tasks/tidewave.proxy.ex` (no `--browser-tools`) |
| `6107915` | MCP server `instructions` | `handler.ex`, rewritten for the five tools |
| `8015953` | Host header check against DNS rebinding | `lib/tidewave/router.ex`, `lib/tidewave.ex` (`:allowed_origins`; toolbar meta-tag part left out) |

The fork keeps its rule that any request carrying an `Origin` header to `/mcp`
is rejected.
