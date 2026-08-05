# Security

Tidewave MCP can evaluate code and query the development database with the
permissions of the running application. Treat it like a development console.

- Load the dependency only in development.
- Keep the default loopback-only access unless the environment is isolated.
- Do not expose `/tidewave/mcp` publicly.
- Review tool calls that execute code or access data.
- Prefer a container or similarly bounded development environment when working
  with untrusted code.

This fork does not load hosted Tidewave scripts, inject a toolbar, establish
browser-control WebSockets, or send prompts and tool results to a Tidewave
subscription service.
