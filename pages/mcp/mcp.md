# Tidewave MCP

This fork exposes only local Runtime Intelligence over MCP, through five tools:

- `project_eval`: inspect live state (processes, ETS, assigns, a function's
  result). Never for writes; change code with file edits.
- `execute_sql_query`: read-only SQL (PostgreSQL). The query runs in a read-only
  transaction that is always rolled back; writes fail.
- `get_docs` and `get_source_location`: use these instead of reading `deps/`
  or grepping.
- `get_logs`: requests and errors from the running app.

Configure clients with the endpoint of the running development application:

```text
http://localhost:4000/tidewave/mcp
```

## Several worktrees: `mix tidewave.proxy`

`mix tidewave.proxy` speaks MCP over stdio and forwards each call to the app
running on `127.0.0.1:<port>`. Every tool gets a required `port` argument.

```json
{"mcpServers": {"tidewave": {"command": "mix", "args": ["tidewave.proxy"]}}}
```

## Security

The endpoint has no authentication. It accepts loopback connections only by
default, rejects requests with an `Origin` header, and checks the `Host` header
against DNS rebinding (IP addresses, `localhost`, `*.localhost`, the endpoint
URL host and `:allowed_origins`). Never enable it in production.
