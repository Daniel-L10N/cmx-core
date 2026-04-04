# Changelog - CMX-CORE

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-04-03

### Added
- **SQLite + FTS5 Backend**: cmx-memories now uses SQLite with Full-Text Search
- **brain-adapter.sh**: Bridge connecting brain.sh decisions to pipeline.sh execution
- **AI Providers Configuration**:
  - OpenCode (5 free models: big-pickle, gpt-5-nano, etc.)
  - Gemini CLI (direct, no API key needed)
  - OpenRouter (4 free models: deepseek, llama3.2, gemma, mistral)
- **Cost-based AI Selection**: Trivial tasks automatically use cheapest IA (gemini)
- **Retry Logic**: Automatic fallback chain when primary IA fails
- **Backup/Restore Scripts**: Database backup with compression and integrity check

### Changed
- **ai-selector.sh**: Now detects trivial tasks and selects cost-effective IA
- **check-environment.sh**: Improved provider detection (CLI vs API)
- **memories.db**: New SQLite database with FTS5 index
- **brain.sh**: Integrated with brain-adapter for SDD tasks

### Breaking Changes
- Backend migrated from JSON (memories.json) to SQLite (memories.db)
- AI selection now considers cost_level (1-5) for efficiency
- Some CLI commands added (backup, restore, search)

### Files Added
- `memories.db` - SQLite database
- `orchestrator/brain-adapter.sh`
- `scripts/ai-executor.sh`
- `scripts/backup-memories.sh`
- `scripts/restore-memories.sh`
- `scripts/migrate-to-sqlite.sh`
- `scripts/setup-ai-providers.sh`
- `scripts/test-ai-providers.sh`
- `.env` (template)
- `.gitignore`
- `VERSION`

## [1.3.1] - 2026-03-22

### Added
- Brain autonomous system (brain.sh)
- AI selector (ai-selector.sh)
- CMX CLI (cmx)
- Pre-flight check (check-environment.sh)
- Memory system (JSON backend)
- Cleanup project script

### Fixed
- Various bug fixes in pipeline execution

---

## Upgrade Notes

### Upgrading from v1.x to v2.1.0

1. Run migration script:
   ```bash
   bash scripts/migrate-to-sqlite.sh
   ```

2. Update environment:
   ```bash
   source .env
   ```

3. Verify setup:
   ```bash
   ./cmx status
   ```