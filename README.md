# Tidewave Phoenix — cvkmohan fork

This is a private, local-only fork of Tidewave Phoenix's open-source Runtime
Intelligence MCP server. It deliberately excludes Tidewave Web, Connect,
browser automation, toolbar injection, hosted assets, Teams, uploads, and
subscription-backed features.

The fork retains upstream Tidewave 0.8.1's vetted local MCP tools:

- `project_eval`
- `get_logs`
- `get_source_location`
- `get_docs`
- `execute_sql_query`
- `get_ecto_schemas` when Ecto is available
- `get_ash_resources` when Ash is available

It also retains the local `Tidewave&#46;Agent` facade, scoped log retrieval, tool
profiles, and the Elixir 1.20 project floor maintained for our applications.
Use an external browser tool such as `agent-browser` for UI verification.

## Installation

```elixir
{:tidewave,
 github: "cvkmohan/tidewave_phoenix",
 tag: "0.8.1",
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
- `:inspect_opts` — options passed to `Kernel.inspect/2` for tool output.

The tool surface may be reduced in `config/dev.exs`:

```elixir
config :tidewave, tools_profile: :minimal
```

Supported profiles are `:full`, `:minimal` (`project_eval` only),
`{:only, names}`, and `{:except, names}`.

## Local agent facade

The facade is invoked through `project_eval`:

```elixir
Tidewave.Agent.project()
Tidewave.Agent.logs(tail: 50, since: DateTime.utc_now() |> DateTime.to_iso8601())
Tidewave.Agent.sql("select count(*) from users")
Tidewave.Agent.ecto_schemas()
Tidewave.Agent.docs(Ecto.Changeset)
Tidewave.Agent.source(MyApp.Context)
Tidewave.Agent.routes()
Tidewave.Agent.frontend_status()
Tidewave.Agent.frontend_check()
```

## License

Copyright (c) 2025 Dashbit

Licensed under the Apache License, Version 2.0. See the repository's `LICENSE`
file.
