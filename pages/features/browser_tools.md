# Browser Testing Tools

This fork of Tidewave includes enhanced browser testing capabilities for Phoenix LiveView applications. These tools allow you to verify both server-side rendering and client-side JavaScript behavior.

## Overview

Three browser testing tools are available:

| Tool | Description | Requires Lightpanda |
|------|-------------|---------------------|
| `smoke_test` | Server-side LiveView mount testing | No |
| `eval_with_logs` | Code evaluation with scoped logs | No |
| `browser_inspect` | Full browser testing with JavaScript | Yes |

## smoke_test

The `smoke_test` tool mounts a Phoenix LiveView route entirely within the BEAM (Erlang virtual machine) and returns structured verification data. This is the fastest way to verify your LiveView code.

### What it catches

- LiveView crashes during mount
- Missing assigns
- Undefined function errors
- Bad database queries
- Redirects (including authentication redirects)

### Usage

```json
{
  "path": "/dashboard",
  "user_id": "optional-user-uuid",
  "session_params": {"org_id": "optional-org-uuid"}
}
```

### Output

```
status: ok
live_module: MyAppWeb.DashboardLive
source_files:
  - lib/my_app_web/live/dashboard_live.ex:1 (MyAppWeb.DashboardLive.render/1)
  - lib/my_app_web/components/layouts/root.html.heex:12 (MyAppWeb.Layouts.root/1)
html_size: 15432 bytes
element_count: 245
logs: (clean — no warnings or errors)
```

**Important:** A redirect to `/login` or any auth path means the page requires authentication. Pass a `user_id` to test as an authenticated user.

## eval_with_logs

The `eval_with_logs` tool evaluates Elixir code and returns both the result and only the logs generated during execution. Unlike `project_eval` + `get_logs`, this tool scopes logs to just the current execution.

### Usage

```json
{
  "code": "MyApp.SomeModule.some_function()",
  "timeout": 30000
}
```

### Output

```
result:
"function returned value"

logs_during_operation:
[info] Query executed in 12ms
[error] Something went wrong
```

## browser_inspect

The `browser_inspect` tool uses [Lightpanda](https://lightpanda.io/), a lightweight headless browser, to test your application with real JavaScript execution. This tool only appears when Lightpanda is available on port 9222.

### What it verifies

- JavaScript hook execution (`phx-hook`)
- Console errors
- Client-side rendering issues
- LiveView WebSocket connectivity
- Full DOM structure with source annotations

### Prerequisites

Install Lightpanda first:

**Linux:**
```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-x86_64-linux && \
chmod a+x ./lightpanda && \
sudo mv ./lightpanda /usr/local/bin/
```

**macOS:**
```bash
curl -L -o lightpanda https://github.com/lightpanda-io/browser/releases/download/nightly/lightpanda-aarch64-macos && \
chmod a+x ./lightpanda && \
sudo mv ./lightpanda /usr/local/bin/
```

**Docker:**
```bash
docker run -d --name lightpanda -p 9222:9222 lightpanda/browser:nightly
```

### Usage

```json
{
  "path": "/dashboard",
  "user_id": "optional-user-uuid",
  "wait_ms": 1000
}
```

The `wait_ms` parameter controls how long to wait after navigation for JavaScript to settle (default: 1000ms).

### Output

```
status: ok
url: http://localhost:4000/dashboard
lv_connected: true
element_count: 267
source_files:
  - lib/my_app_web/live/dashboard_live.ex:1 (MyAppWeb.DashboardLive.render/1)
console_errors: none
interactive_elements:
  - <button> "Create New" phx-click=create_item
  - <a> "Settings" href=/settings
  - <form> "Search" phx-submit=search
```

## Recommended Workflow

1. **Start with `smoke_test`** - Verify the page mounts without server-side errors
2. **Check with `eval_with_logs`** - Debug any issues with scoped logs
3. **Finish with `browser_inspect`** - Verify JavaScript hooks and client-side behavior

This layered approach gives you fast feedback for server-side issues while still allowing comprehensive browser testing when needed.

## Lightpanda Auto-Start

Tidewave includes a GenServer (`Tidewave.Lightpanda`) that automatically starts Lightpanda when:

- The `lightpanda` binary is found in your PATH
- Port 9222 is not already in use

If Lightpanda crashes, it will be restarted up to 3 times before giving up. This ensures the browser is available for testing without manual intervention.

To disable auto-start, simply don't install Lightpanda or ensure port 9222 is occupied by another service.
