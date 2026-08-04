# Fork v0.8.1 integration

This change makes upstream Tidewave Phoenix v0.8.1 the authoritative codebase
for `cvkmohan/tidewave_phoenix`. The old fork history remains in Git, but the
runtime, router, browser control plane, documentation layout, and dependency
shape start from the upstream release rather than from conflict resolution.

## Adopted unchanged from upstream

- Tidewave toolbar and control page
- Browser session registry, control socket, and `browser_eval`
- Tidewave Connect support
- `/tidewave/app`, uploads, configuration metadata, and current router behavior
- The upstream MCP protocol and conditional `include_browser_tools` dispatch
- Upstream Hex-tool removal and documentation organization

## Fork extensions retained

- Elixir 1.20 project floor
- `Tidewave.Agent` facade for project, logs, SQL, schemas, docs, source, routes,
  and conservative frontend diagnostics
- Optional `:full`, `:minimal`, `{:only, names}`, and `{:except, names}` tool
  profiles; `:minimal` retains `project_eval` and upstream `browser_eval`
- ISO 8601 `since` filtering for logs, implemented without clearing the shared
  log buffer
- Fork source metadata and prerelease versioning

## Fork code retired

- Lightpanda and the old `browser_inspect` implementation
- Server-side `smoke_test` and `eval_with_logs` browser tools
- QuickBEAM `eval_js` and static JS-hook validation
- The restored Hex documentation search tool
- AST search/replacement, OTP inspection, typespec, xref, Phoenix introspection,
  and API-spec MCP tools
- The old fork router, installer rewrite, browser documentation, and dependency
  lockfile

The retired tools either overlap upstream functionality, duplicate operations
available through `project_eval`, add broad write/runtime dependencies, or make
application-specific assumptions that do not belong in a generic library.

## Browser policy

Use upstream `browser_eval` first when Tidewave is connected. Keep external
browser automation outside this library and use it for independent verification,
durable evidence, responsive checks, named authentication sessions, situations
where Tidewave is unavailable, and changes to Tidewave/browser tooling itself.

## Verification contract

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test`
- `mix hex.audit`
- `mix hex.build`
- `git diff --check`
