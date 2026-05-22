# Changelog

All notable changes to the Implexa Codex plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** the plugin is a thin wrapper that pins skills and points at the
> Implexa backend at `https://core.implexa.ai/api/v2/mcp` (Streamable HTTP
> transport). Backend tool changes propagate to all clients without a plugin
> release. Only changes to skills, the plugin manifest, or install scripts
> warrant a version bump.

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
