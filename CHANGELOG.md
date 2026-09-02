# Changelog

All notable changes to the Implexa Codex plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** the plugin is a thin wrapper that pins skills and points at the
> Implexa Desktop's local authenticated MCP broker (stdio transport). Backend
> tool changes propagate to all clients without a plugin
> release. Only changes to skills, the plugin manifest, or install scripts
> warrant a version bump.

## [0.29.2] - 2026-09-01

### Fixed

- Replaced obsolete per-run HTTP-header assumptions with a validated private
  stdio preamble. Desktop-launched Codex runs now carry request, attempt, and
  fencing identity through the managed local broker without writing values to
  Codex configuration or exposing account credentials.

## [0.29.1] - 2026-08-31

### Security

- Removed the Implexa account credential from Codex MCP URLs, arguments,
  environment variables, cached manifests, backups, and installer output.
- Added a direct, secret-free local shim that reaches the authenticated Implexa
  Desktop broker over a private Unix socket and fails closed when Desktop is not
  available or signed in.
- Added conservative migration of legacy Implexa-owned Codex configuration and
  caches, including refusal on unsafe symlinks, traversal, or unverifiable
  cleanup.

## [0.29.0] - 2026-06-08

Synced from the Claude plugin: connect-your-accounts reachability.

### Added

- **Schedule-time reachability gate (`/implexa:schedule` Step 2.8).** Alongside the
  permission pre-grant, a browser-driving agent's required accounts/domains are checked
  against the backend Connections status via `get_connection_status`. If a needed account
  is not reachable in a paired Chrome profile, the schedule WARNS and offers to connect it
  now (steering the user to sign it into the dedicated profile and re-verifying) rather than
  silently scheduling against an inbox it cannot reach. A recommendation, not a hard block,
  and best-effort: a missing reachability read never stops a schedule.
- **Runtime honest degradation + record (`/implexa:run-scheduled` Step 2.7).** When a run
  hits a required signed-in account that is unreachable, it degrades honestly via the
  existing fallback and records the account through `record_scheduled_run`'s new
  `unreachableAccounts` field, which the backend fans out to the run-state row and the
  Connections registry so the dashboard shows the gap instead of a silent partial result.

## [0.28.0] - 2026-06-07

Synced from the Claude plugin: unattended-run permission pre-grant.

### Added

- **Permission pre-grant at schedule time (`/implexa:schedule` Step 2.7).** A scheduled
  agent's permission manifest is pre-approved once at schedule time via the bundled
  `apply-permission-manifest.mjs`, so an unattended run executes under a scoped allowlist
  instead of stalling on an interactive prompt. Additive, idempotent, never a blanket bypass.

## [0.27.6] - 2026-06-06

Synced: loop-powered watch/until workflow triggers (run offers a loop_call;
schedule has a watch/until branch returning a /loop invocation).

## [0.27.5] - 2026-06-06

Synced from the Claude plugin: unified share (skill OR workflow), schedule-time
config resolution for hands-free first runs, and workflow-first help/vocabulary.

## [0.27.4] - 2026-06-06

Browse the workflows you've saved: synced `/implexa:my-skills workflows` lens
(owner-scoped list_my_workflows), with one-tap run / schedule / share.

## [0.27.3] - 2026-06-06

`/implexa:run` now leads with whole-job workflows (synced from the Claude
plugin): Step 2.4 surfaces a matching workflow_candidate (apply_workflow +
schedule) above the skill list, and the caller's own captured/generated
workflows resurface to re-run.

## [0.27.2] - 2026-06-06

Capture your work as a WORKFLOW, not just a skill.

### Changed

- **`/implexa:record` now captures multi-step workflows.** Synced from the
  Claude plugin: a Phase 0 skill-vs-workflow decision plus a Branch W that
  reconstructs a multi-step job into an ordered, schedulable workflow via
  `capture_workflow` (private, ownable, shareable for karma).

## [0.27.1] - 2026-06-06

Sync the Codex plugin up to parity with the Claude plugin (0.27.1). The skill
set had drifted: Codex was pinned at 0.12.0 while the Claude plugin shipped
fifteen releases of skill refinements. Since both plugins point at the same
backend MCP, the runtime tools were always current; this release brings the
local skill definitions back in line so Codex users get the same guidance.

### Added

- **`edit-workflow` skill.** Revise a generated workflow in place (the Claude
  plugin's 0.2x addition), now available in Codex too.

### Changed

- **Refreshed `my-skills`, `record`, `run`, `run-scheduled`, `schedule`,
  `share-this`** to their current Claude-plugin content (new cross-vendor
  sources, the unified-recommender framing, clearer triggers). Generic
  agent-routing prose in `run` and `run-scheduled` was generalized away from
  Claude-specific wording.

### Known follow-up

- The `schedule` / `run-scheduled` skills still describe scheduling via Claude
  Code's `scheduled-tasks` MCP and `/mcp` flow. Those are concrete operational
  steps that need Codex-specific equivalents; left as faithful copies for now
  rather than rewritten with unverified Codex instructions.

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
