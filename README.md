# Tidewave

Tidewave is the coding agent for full-stack web app development, deeply integrated with Phoenix, from the database to the UI. [See our website](https://tidewave.ai) for more information.

This project can also be used as [a standalone Model Context Protocol server](https://hexdocs.pm/tidewave/mcp.html).

## Installation

### Manually

Add the `tidewave` package to your `mix.exs`:

```elixir
def deps do
  [
    {:tidewave, github: "cvkmohan/tidewave_phoenix", only: :dev},
    {:phoenix, ...},
  ]
end
```

Then, for Phoenix applications, go to your `lib/my_app_web/endpoint.ex` and right above the `if code_reloading? do` block, add:

```diff
+  if Code.ensure_loaded?(Tidewave) do
+    plug Tidewave
+  end

   if code_reloading? do
```

Now make sure [Tidewave is installed](https://hexdocs.pm/tidewave/installation.html) and you are ready to connect Tidewave to your app.

> Tidewave Web works best with Phoenix LiveView v1.1 or later. Once you update it,
> make sure to enable the following options in your `config/dev.exs`:
>
> ```elixir
> config :phoenix_live_view,
>   debug_heex_annotations: true,
>   debug_attributes: true
> ```
>
> Those are enabled by default for Phoenix v1.8+ apps.

### Using Igniter

Alternatively, you can use `igniter` to automatically install it into an existing Phoenix application:

```sh
# install igniter_new if you haven't already
mix archive.install hex igniter_new

# install tidewave
mix igniter.install tidewave
```

Now make sure [Tidewave is installed](https://hexdocs.pm/tidewave/installation.html) and you are ready to connect Tidewave to your app.

### Umbrella projects

For umbrella projects, you can follow the manual steps above in the application that defines your Phoenix endpoint (typically `apps/your_app_web`).

### Usage in non-Phoenix applications

Tidewave can be used as a MCP in any Elixir project. For example, you can use `bandit` (and `tidewave`) in dev mode in your `mix.exs`:

```elixir
{:tidewave, "~> 0.4", only: :dev},
{:bandit, "~> 1.0", only: :dev},
```

And then adding an alias in your `mix.exs`:

```elixir
aliases: [
  tidewave:
    "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
]
```

Now run `mix tidewave` and [configure Tidewave as a MCP](https://hexdocs.pm/tidewave/mcp.html).

## Troubleshooting

### Using multiple hosts/subdomains

If you are using multiple hosts/subdomains during development, you must use `*.localhost`, as such domains are considered secure by browsers. Additionally, add the following immediately `@session_options` definition in your `lib/your_app_web/endpoint.ex`:

```elixir
@session_options [
  # ... your configuration
]

if code_reloading? do
  @session_options Keyword.merge(@session_options, same_site: "None", secure: true)
end
```

The above will allow your application to run embedded within Tidewave across multiple subdomains, as long as it is using a secure context (such as `admin.localhost`, `www.foobar.localhost`, etc).

### Content security policy

If you have enabled Content-Security-Policy, Tidewave will automatically enable "unsafe-eval" under `script-src` in order for contextual browser testing to work correctly. It also disables the `frame-ancestors` directive.

## Configuration

You may configure the `Tidewave` plug using the following syntax:

```elixir
  plug Tidewave, options
```

The following options are available:

  * `:allow_remote_access` - Tidewave MCP only allows requests from localhost by default, even if your server listens on other interfaces. If you trust your network and need to access Tidewave MCP from a different machine, this configuration can be set to `true`.

  * `:inspect_opts` - Custom options passed to `Kernel.inspect/2` when formatting some tool results. Defaults to: `[charlists: :as_lists, limit: 50, pretty: true]`

  * `:team` - set your Tidewave Team configuration, such as `team: [id: "my-company"]`

## Available tools

### Core Tools

- `execute_sql_query` - executes a SQL query within your application
  database, useful for the agent to verify the result of an action

- `get_docs` - get the documentation for a given module/function.
  It consults the exact versions used by the project, ensuring you always
  get correct information

- `get_logs` - reads logs written by the server

- `get_models` - lists all modules in the application and their location
  for quick discovery

- `get_source_location` - get the source location for a given module/function,
  so an agent can directly read the source skipping search

- `project_eval` - evaluates code within the your application itself, giving the agent
  access to your runtime, dependencies, and in-memory data

- `search_package_docs` - runs a search on https://hexdocs.pm/ filtered to the exact
  dependencies in this project

### Browser Testing Tools

- `smoke_test` - mounts a Phoenix LiveView route inside the BEAM and returns
  structured verification data. Catches crashes, redirects, missing assigns,
  undefined functions, and bad queries. Logs are scoped to only show logs
  generated during this specific mount.

- `eval_with_logs` - evaluates Elixir code and returns both the result and
  only the logs generated during execution. Logs are scoped with no stale
  noise from previous runs. Use this instead of `project_eval` + `get_logs`
  when debugging errors.

- `browser_inspect` - navigates a real headless browser (Lightpanda) to a route
  and returns structured DOM data. Use this after `smoke_test` passes to verify
  JavaScript hook execution, console errors, client-side rendering issues, and
  full DOM structure with source annotations.

`get_ecto_schemas` and `get_ash_resources` is also available if you are using Ecto and Ash respectively.

## Lightpanda Browser (Optional)

This fork includes support for [Lightpanda](https://lightpanda.io/), a lightweight
headless browser designed for AI and automation. When installed, Tidewave can
perform real browser testing of your LiveView applications, including JavaScript
execution verification.

### Installing Lightpanda

**Linux (x86_64):**
```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux && \
chmod a+x ./lightpanda && \
sudo mv ./lightpanda /usr/local/bin/
```

**macOS (Apple Silicon):**
```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-macos && \
chmod a+x ./lightpanda && \
sudo mv ./lightpanda /usr/local/bin/
```

**Docker:**
```bash
docker run -d --name lightpanda -p 9222:9222 lightpanda/browser:nightly
```

Lightpanda will be automatically detected and started by Tidewave on port 9222.
The `browser_inspect` tool will only be available when Lightpanda is running.

## License

Copyright (c) 2025 Dashbit

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
