---
name: schedule
description: Schedule any installed skill to run on a recurring schedule (daily, weekly, hourly) with output delivered to the Implexa dashboard or to a Slack channel via incoming webhook. Use when the user says "schedule this skill", "run X daily", "every morning run Y", "set up a daily standup", "auto-run my morning brief", "run hackernews-and-x-comment-drafter every day at 9am", or invokes $implexa-schedule. THE Implexa-native scheduling primitive — replaces ad-hoc "schedule this for me" requests with a real registered manifest, persistent output log, and optional Slack delivery. Wraps Codex's scheduling mechanism with the manifest + destination layer Codex alone doesn't provide.
---

# Schedule a skill to run recurringly

Register a recurring run for any skill in the user's library. The output gets persisted to the Implexa dashboard (always-on) and optionally posted to a Slack channel via incoming webhook.

This skill **wraps** the scheduling mechanism of the agent runtime. Implexa stores the manifest (what's scheduled, when, where it goes); when the task fires, it invokes the wrapper skill `$implexa-run-scheduled` which executes the real skill and persists the output.

<!-- TODO (Phase 2 - Codex): The Claude Code version of this skill calls mcp__scheduled-tasks__create_scheduled_task
     (Step 3 below) to register with Claude Code's native scheduled-tasks MCP. Codex has its own
     scheduling mechanism. After calling schedule_skill (Step 2), surface the returned
     claudeScheduledTaskPrompt and cronExpression to the user and guide them to register the task
     via Codex's scheduling configuration. Update Step 3 when Codex scheduling APIs are finalized.
     See: https://developers.openai.com/codex/skills for Codex scheduling conventions. -->

---

## Step 1 — Parse the user's request into structured args

Extract three things from the user's free-form input:

- **`skillSlug`** (required): the slug of the skill to schedule. Examples: `standup-from-yesterday-commits`, `daily-ai-skills-pulse`, `hackernews-and-x-comment-drafter`. If the user used a fuzzy name ("run my morning brief"), resolve it by calling `list_org_skills` and picking the best match.

- **`scheduleNl`** (required): the natural-language schedule. Pass it through verbatim from the user. Supported patterns:
  - `"daily at 8:55am"` / `"every day at 17:30"`
  - `"every weekday at 9am"`
  - `"every monday at 9am"` (any weekday name)
  - `"every hour"` / `"hourly"`
  - `"every 30 minutes"` (1-59)
  - `"every 2 hours"` (1-23)
  - `"every 3 days"` (1-30, runs at midnight in the schedule's timezone)
  - raw cron: `"55 8 * * *"` (reverse-humanized to natural prose when displayed back)

- **`destination`** (optional, default `{type:"dashboard"}`):

  Three options. Pick based on what the user said:

  **(a) `{ type: "dashboard" }`** — default. Output lands at app.implexa.ai/runs.

  **(b) `{ type: "slack-plugin", target: "<channel>" }`** — when the user wants Slack delivery AND a Slack plugin is available in-session. Target is the channel: `"#standup"`, `"#general"`, a channel ID like `"C0123456789"`, or a DM ID like `"D012345678"`.

  **(c) `{ type: "slack-webhook", target: "<webhook-url>" }`** — fallback when the user has a Slack incoming-webhook URL ready (e.g. they pasted one). The Implexa backend POSTs to the URL server-side; works without any agent-side Slack integration.

  ## How to choose between slack-plugin and slack-webhook

  1. If the user pastes a `https://hooks.slack.com/...` URL → **slack-webhook**.
  2. If the user gives a channel name (with or without #) → **slack-plugin**.
  3. If the user just says "slack" without specifying → ask: "Channel name (#standup, uses your Slack plugin) or webhook URL (works without the plugin)?"

  ## Default destination

  If the user gave only the skill slug + schedule without mentioning Slack, **do not ask** for Slack details. Default to dashboard. They can add Slack later by re-running `$implexa-schedule` with the same args + a destination.

## Step 2 — Call `schedule_skill`

Call `schedule_skill` with the parsed args:

```jsonc
{
  "skillSlug":   "daily-ai-skills-pulse",
  "scheduleNl": "daily at 8:55am",
  "destination": { "type": "dashboard" }
  // OR { "type": "slack-plugin",  "target": "#standup" }
  // OR { "type": "slack-webhook", "target": "https://hooks.slack.com/services/T.../B.../XXX" }
}
```

The tool returns:

```jsonc
{
  "ok": true,
  "scheduledSkillId": "uuid",
  "skillSlug":         "daily-ai-skills-pulse",
  "cronExpression":    "55 8 * * *",
  "humanizedSchedule": "8:55 AM every day",
  "timezone":          "UTC",
  "destination":       { "type": "dashboard" },
  "claudeScheduledTaskPrompt": "$implexa-run-scheduled <uuid>",
  "nextAction":        "Register this task in your agent runtime's scheduler with the prompt and cron above."
}
```

If `ok === false`, the tool returns an `error` string. Common cases:
- Unknown skill slug → ask the user to install/fork it first
- Unparseable schedule → echo the supported patterns from the error message
- Invalid Slack webhook URL → ask user to paste a real `hooks.slack.com` URL

## Step 3 — Register with the agent runtime's scheduler

<!-- TODO (Phase 2 - Codex): Replace this step with the actual Codex scheduling API call once finalized.
     For now, surface the scheduling info to the user for manual registration. -->

Inform the user of the returned `claudeScheduledTaskPrompt` and `cronExpression`. Ask them to register a recurring task in their Codex scheduling configuration using:
- **Prompt**: `$implexa-run-scheduled <uuid>` (from the response)
- **Cron**: `<cronExpression>` (from the response)
- **Timezone**: `<timezone>` (from the response)

If a native scheduling MCP is available in the current Codex session, attempt to use it with those three values. Otherwise surface them clearly for manual registration.

## Step 4 — Confirm to the user

Render a concise confirmation:

```
✓ Scheduled `<skillSlug>` <humanizedSchedule>.
  Output → <destination summary>
  Manage at: app.implexa.ai/scheduled
```

Where `<destination summary>` is:
- `Implexa dashboard only` (default)
- `Slack <channel> + Implexa dashboard` (when `slack-plugin` configured — echo the channel name back)
- `Slack (via webhook) + Implexa dashboard` (when `slack-webhook` configured — do NOT echo the webhook URL)

Keep it ≤ 4 lines. Do not echo the cron expression unless the user asked for it.

## What's next?

Schedule management is now available from inside the agent (no dashboard hop needed):

- `Pause this schedule` → `mcp__implexa__pause_scheduled_skill({ scheduledSkillId })` — flip status to paused. Idempotent.
- `Resume a paused schedule` → `mcp__implexa__resume_scheduled_skill({ scheduledSkillId })` — flip back to active.
- `Delete a schedule` → `mcp__implexa__delete_scheduled_skill({ scheduledSkillId })` — hard-delete the manifest. Historical runs at app.implexa.ai/runs are preserved.
- `List all my schedules` → `mcp__implexa__list_scheduled_skills({})` — returns every schedule with natural-prose humanizedSchedule, nextRunInfo, destinationLabel, runCount, lastRunAt.
- `Run it once now to test` — invoke `$implexa-run-scheduled <id>` directly.
- `Manage in the dashboard` — app.implexa.ai/scheduled is still live as the visual alternative.

## Notes for the model

- **Default to dashboard destination** unless the user explicitly mentions Slack. Asking for a Slack webhook URL when they didn't ask for Slack is friction.
- **Slack webhook URLs are not secret-secret but should not be echoed back to the user.** When confirming, say "Slack channel" not the full URL.
- **Reuse the user's typed schedule string** when calling `schedule_skill`. The natural-language parser handles capitalization and whitespace.
- **One invocation, one schedule.** Don't try to register two schedules in one invocation. If the user wants two, run `$implexa-schedule` twice.
- **Telemetry is automatic.** The schedule_skill tool writes the manifest + the wrapper skill writes each run to skill_runs.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `schedule_skill` returns ok=false with "Skill not found" | The skill isn't in the user's library | "I couldn't find `<slug>` in your library. Fork it from a Playbook or install via a share link, then re-run `$implexa-schedule`." |
| `schedule_skill` returns ok=false with "Could not parse schedule" | NL parser couldn't match a pattern | Echo the supported patterns from the error message. Ask the user to rephrase. |
| `schedule_skill` returns ok=false with "slack-webhook destination requires..." | Webhook URL invalid or missing | Ask the user to paste a real `hooks.slack.com/services/...` URL, OR switch to slack-plugin if they meant a channel name. |
| `schedule_skill` returns ok=false with "slack-plugin destination requires..." | Channel target missing or too short | Ask the user for the channel name (e.g. `#standup`) or paste a channel ID. |
| Scheduling MCP not available | Agent runtime doesn't expose a scheduling MCP | Tell the user: "The Implexa manifest is saved (id=<id>), but I couldn't auto-register the cron task. Prompt: `$implexa-run-scheduled <id>` / Cron: `<expr>`. Register manually in your Codex scheduling settings." |
| Schedule registered but later runs never fire | Cron task lost in agent restart | Tell the user to re-register by re-running `$implexa-schedule` with the same args. |
