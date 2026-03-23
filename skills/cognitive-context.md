---
name: cognitive-context
description: >
  Load the shared cognitive stack context. Trigger: "load context", "contexto", "workspace", "iniciar sesión".
version: "1.0"
---

# Cognitive Stack — Context Loader

## Quick Reference

**Workspace**: `/home/cmx/cmx-core/`

```
cd /home/cmx/cmx-core
```

## Stack Tecnológico

| Layer | Technology |
|-------|------------|
| Frontend | Next.js 14+, React 18+, TypeScript strict |
| Backend | Django 5+, Django REST Framework |
| Memory | Engram (SQLite + FTS5) |

## Skills

- **frontend-react.md**: React/Next.js/TypeScript conventions
- **backend-django.md**: Django/DRF best practices

## Memory Protocol

**Always save significant decisions:**
```
mem_save(
  title: "<title>",
  topic_key: "sdd/<project>/<artifact>",
  type: "observation",
  project: "cmx-core",
  content: "<content>"
)
```

**Search before major decisions:**
```
mem_search(query: "<query>", project: "cmx-core")
```

## Commands

| Command | Purpose |
|---------|---------|
| `/sdd-init` | Initialize SDD context |
| `/sdd-new <name>` | New feature |
| `/sdd-continue` | Next phase |
| `/sdd-apply` | Implement tasks |
| `/sdd-verify` | Validate specs |
| `/sdd-archive` | Close feature |

## Orchestration Rules

1. **Delegate-first**: Never execute directly — always delegate to sub-agents
2. **HITL gates**: proposal → spec → apply
3. **Plan mode**: Present plans before execution
4. **Memory**: Save decisions, search before acting
