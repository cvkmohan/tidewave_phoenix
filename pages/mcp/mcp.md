# Tidewave MCP

This fork exposes only local Runtime Intelligence over MCP. Configure clients
with the endpoint embedded in the running development application:

```text
http://localhost:4000/tidewave/mcp
```

The MCP server provides runtime evaluation, logs, source and documentation
lookup, and database/schema access. Browser automation is intentionally not
included; use an external browser tool for UI verification.

The endpoint has no authentication and accepts loopback connections only by
default. Never enable it in production.
