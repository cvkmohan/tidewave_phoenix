# Tidewave Phoenix — cvkmohan fork

This is a private, local-only fork of Tidewave Phoenix's open-source Runtime
Intelligence MCP server. It deliberately excludes Tidewave Web, Connect,
browser automation, toolbar injection, hosted assets, Teams, uploads, and
subscription-backed features.

Tools: `project_eval`, `get_logs`, `get_source_location`, `get_docs` and
`execute_sql_query` (read-only: a read-only transaction that is always rolled
back; PostgreSQL only). See `docs/fork.md` for scope and what was ported from
upstream 0.9.2.

It also keeps the local `Tidewave&#46;Agent` facade, scoped log retrieval and
the Elixir 1.20 project floor. Use an external browser tool such as
`agent-browser` for UI verification.

## Installation

```elixir
{:tidewave,
 github: "cvkmohan/tidewave_phoenix",
 tag: "0.9.2",
 only: :dev}
```

Add the plug above the code reloader in the Phoenix endpoint:

```elixir
if Code.ensure_loaded?(Tidewave) do
  plug Tidewave
end

if code_reloading? do
  # ...
end
```

Configure the MCP client to use the local endpoint:

```text
http://localhost:4000/tidewave/mcp
```

The server accepts local connections only by default. It is a development tool
and must not be enabled in production.

## Configuration

The plug accepts:

- `:allow_remote_access` — allow non-loopback clients. Defaults to `false`.
- `:allowed_origins` — hosts accepted in the `Host` header, as
  `[scheme:]//host[:port]` strings (only the host is compared; `*.` prefix
  allowed). IP addresses, `localhost` and `*.localhost` are always allowed; when
  unset, the Phoenix endpoint's URL host is allowed. Protects against DNS
  rebinding. Requests carrying an `Origin` header are always rejected.
- `:inspect_opts` — options passed to `Kernel.inspect/2` for tool output.

## Worktrees: `mix tidewave.proxy`

A stdio MCP server that forwards tool calls to `127.0.0.1:<port>/tidewave/mcp`.
Every tool gains a required `port` argument, so one client entry serves every
worktree's running app. In `.mcp.json`:

```json
{"mcpServers": {"tidewave": {"command": "mix", "args": ["tidewave.proxy"]}}}
```

The stdio entry must run from the application's root (the directory that holds
`.mcp.json`), not from the fork or any other directory. The proxy loads that
app's `ecto_repos` to decide whether to advertise `execute_sql_query`; from
another directory the SQL tool is missing from the tool list.

## Local agent facade

The facade is invoked through `project_eval`:

```elixir
Tidewave.Agent.project()
Tidewave.Agent.logs(tail: 50, since: DateTime.utc_now() |> DateTime.to_iso8601())
Tidewave.Agent.sql("select count(*) from users")
Tidewave.Agent.docs(Ecto.Changeset)
Tidewave.Agent.source(MyApp.Context)
Tidewave.Agent.routes()
```

## License

Copyright (c) 2025 Dashbit

Licensed under the Apache License, Version 2.0. See the repository's `LICENSE`
file.
