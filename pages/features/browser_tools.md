# Browser Testing Tools

Tidewave includes BEAM-side verification tools for Phoenix LiveView applications. These tools are intended to complement your agent browser tooling: use Tidewave for runtime-aware server checks and use your browser automation stack for full client-side verification.

## Overview

Two browser-related MCP tools are available:

| Tool | Description |
|------|-------------|
| `smoke_test` | Server-side LiveView mount testing |
| `eval_with_logs` | Code evaluation with scoped logs |

## smoke_test

The `smoke_test` tool mounts a Phoenix LiveView route entirely within the BEAM and returns structured verification data. This is the fastest way to verify that a LiveView route can render without server-side failures.

### What it catches

- LiveView crashes during mount
- Missing assigns
- Undefined function errors
- Bad database queries
- Redirects, including authentication redirects

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

## Recommended Workflow

1. Start with `smoke_test` to verify the route mounts without server-side errors.
2. Use `eval_with_logs` to debug server-side issues with scoped logs.
3. Use your agent browser tooling for JavaScript execution, console errors, and client-side interaction checks.
