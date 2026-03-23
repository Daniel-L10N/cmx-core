# Model Context Protocol Configuration

## Engram (Memory)
Engram provides persistent memory across sessions.

```json
{
  "command": ["engram", "mcp", "--tools=agent"],
  "enabled": true
}
```

## Available MCP Tools
- `mem_save` — Save observations/decisions
- `mem_search` — Search memory
- `mem_context` — Get session context
- `mem_timeline` — Chronological history
