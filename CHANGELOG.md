# Changelog

All notable changes to the Implexa Codex plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** the plugin is a thin wrapper that pins skills and points at the
> Implexa backend at `https://core.implexa.ai/api/v2/mcp` (Streamable HTTP
> transport). Backend tool changes propagate to all clients without a plugin
> release. Only changes to skills, the plugin manifest, or install scripts
> warrant a version bump.

## [0.11.0] — 2026-05-21

Phase 2 ship. Resolves 3 of 4 Phase 1 TODOs (4th — host hooks — deferred
to Phase 3 because it requires backend changes).

### Added
- `$implexa-schedule` now supports three Codex scheduling paths:
  - **system cron** (recommended, headless): generates a crontab entry
    the user pastes via `crontab -e`. Most reliable, doesn't require any
    app running.
  - **Codex app Automations**: surfaces the prompt + cron for the user to
    paste into the Codex desktop app's Automations panel.
  - **GitHub Actions**: generates a workflow YAML the user commits to any
    repo. Runs in cloud, no laptop required.

### Changed
- `AskUserQuestion`-style multi-choice prompts replaced with a numbered-list
  text fallback across record-skill, update-skill, schedule. Functional
  equivalence; clunkier UX than Claude Code's native picker but ships now.
- `slack-plugin` destination now fails gracefully on Codex with a clear
  error message + alternative (use `slack-webhook` instead).
- `run-scheduled` skill body acknowledges the codex-exec context (no
  interactive user, all output goes to stdout + persistence layer).

### Deferred to Phase 3
- Host-forwarded transcript via Codex SessionStart hooks (needs backend
  changes to accept Codex-formatted event payloads). Demo capture works
  today without it; just thinner trace.

## [0.10.1] — 2026-05-21

Initial Codex Plugin System release. Same Implexa backend (https://core.implexa.ai/api/v2/mcp) as the Claude Code plugin, bundled per the Codex `.codex-plugin/plugin.json` manifest convention.

### Added
- `.codex-plugin/plugin.json` manifest for Codex Marketplace
- `.mcp.json` bundling the Implexa MCP server (Streamable HTTP transport)
- 14 SKILL.md files adapted from the Claude Code plugin (slash command prefix changed from the Claude-style colon syntax to `$implexa-X` Codex convention)
- `install-for-codex.sh` script for one-line install: `curl -fsSL https://core.implexa.ai/install-for-codex.sh | bash`

### Notes
- Phase 1 ship: skill content, MCP server, basic install. Hooks system (Codex's SessionStart, etc.) deferred to Phase 2.
- Demo capture richness will be lower than on Claude Code until Phase 2 wires up Codex-specific lifecycle events.
