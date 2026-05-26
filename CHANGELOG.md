# Changelog

All notable changes to the Implexa Codex plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** the plugin is a thin wrapper that pins skills and points at the
> Implexa backend at `https://core.implexa.ai/api/v2/mcp` (Streamable HTTP
> transport). Backend tool changes propagate to all clients without a plugin
> release. Only changes to skills, the plugin manifest, or install scripts
> warrant a version bump.

## [0.12.0] — 2026-05-27

Consolidate the skill-invocation surface from 18 to 7 visible commands
(plus 1 internal callback). The long tail moves to natural-language
invocation; the underlying MCP tools stay exposed, so asks like "fork
this skill", "give me my morning brief", "publish my X to ClawHub",
"show me skill ROI" still route correctly without a memorized invocation.

### The final 7 (autocomplete-discoverable)

| invocation | what it does |
|---|---|
| `$implexa-suggest` | find skills (active search or passive buffer pull) |
| `$implexa-run` | unified recommender across library + cross-vendor graph |
| `$implexa-record` | capture a workflow as a skill — 3 entry intents in one flow |
| `$implexa-my-skills [scope]` | browse libraries — personal (default) / team / org / public |
| `$implexa-schedule` | schedule any skill on a recurrence |
| `$implexa-share-this` | team-gated or public share link |
| `$implexa-help` | command list + your current credit balance |

Plus `$implexa-run-scheduled` internally (the scheduler callback fired by
system cron / Codex Automations / GitHub Actions).

### Merges

- `$implexa-save-this` + `$implexa-update-skill` → folded into
  `$implexa-record`. Three entry intents in one flow:
  - **Branch A** — new skill via live demonstration
  - **Branch B** — post-hoc save via `capture_workflow_as_skill`
  - **Branch C** — update existing via re-record, finalize with `replacingSkillId`
- `$implexa-org-skills` + `$implexa-playbooks` → folded into `$implexa-my-skills`
  via a `scope` argument: `personal` (default) / `team` / `org` / `public`.
- `$implexa-credits` → folded into `$implexa-help` (balance shown at the top).

### Removed (now natural-language only)

- `$implexa-fork` — say "fork this skill" / "fork the X Playbook into my org"
- `$implexa-morning` — say "give me my morning brief"
- `$implexa-skill-roi` — say "show me skill ROI" / "which skills are driving outcomes"
- `$implexa-publish-to-clawhub` — say "publish my X to ClawHub"
- `$implexa-get-me-started` — first-run flow now lives in the install script's
  "next steps" output

### Updated

- `install-for-codex.sh` — final "what's installed" line lists the 7 commands;
  next-steps message points at `$implexa-help` instead of `$implexa-get-me-started`.

### Migration

Users on 0.11.x who memorized the old invocations can either switch to the
new shape (`$implexa-record` instead of `$implexa-record-skill`, `$implexa-my-skills team`
instead of `$implexa-org-skills`, etc.) or just ask in natural language —
the MCP tools the old invocations fronted are still exposed.

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
