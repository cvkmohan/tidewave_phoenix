# Fork scope at 0.8.1

This fork uses upstream Tidewave Phoenix 0.8.1 as the vetted baseline while
retaining only the open-source, local Runtime Intelligence MCP surface.

Retained:

- upstream runtime, docs, source, logs, Ecto, and Ash tools
- `Tidewave.Agent`
- scoped log retrieval
- configurable tool profiles
- Elixir 1.20 dependency floor

Deliberately excluded:

- Tidewave Web and hosted JavaScript
- toolbar injection and application response rewriting
- Connect, browser sessions, and `browser_eval`
- browser-control WebSockets and media uploads
- Teams/subscription configuration

Browser verification belongs to external tooling such as `agent-browser`.
