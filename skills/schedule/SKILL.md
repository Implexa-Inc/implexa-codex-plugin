---
name: schedule
description: Schedule any installed skill to run on a recurring schedule (daily, weekly, hourly) with output delivered to the Implexa dashboard or to a Slack channel via incoming webhook. Use when the user says "schedule this skill", "run X daily", "every morning run Y", "set up a daily standup", "auto-run my morning brief", "run hackernews-and-x-comment-drafter every day at 9am", or invokes $implexa-schedule. THE Implexa-native scheduling primitive — replaces ad-hoc "schedule this for me" requests with a real registered manifest, persistent output log, and optional Slack delivery. Wraps Codex's scheduling mechanism with the manifest + destination layer Codex alone doesn't provide.
---

# Schedule a skill to run recurringly

Register a recurring run for any skill in the user's library. The output gets persisted to the Implexa dashboard (always-on) and optionally posted to a Slack channel via incoming webhook.

This skill **wraps** the scheduling mechanism of the agent runtime. Implexa stores the manifest (what's scheduled, when, where it goes); when the task fires, it invokes the wrapper skill `$implexa-run-scheduled` which executes the real skill and persists the output.

On Codex, there are three scheduling paths (the user picks one in Step 3): **system cron** (recommended, headless), **Codex app Automations** (uses the Codex desktop app), or **GitHub Actions** (runs in cloud). Implexa stores the manifest the same way regardless; the difference is who pulls the trigger when the cron fires.

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

  Two options on Codex. Pick based on what the user said:

  **(a) `{ type: "dashboard" }`** — default. Output lands at app.implexa.ai/runs.

  **(b) `{ type: "slack-webhook", target: "<webhook-url>" }`** — when the user has a Slack incoming-webhook URL ready (e.g. they pasted one). The Implexa backend POSTs to the URL server-side; works cross-vendor with no agent-side Slack integration needed.

  > **Note:** the `slack-plugin` destination type exists in the manifest schema for parity with the Claude Code plugin, but on Codex it has no working delivery path. If a user asks for Slack on Codex, route them to slack-webhook (ask them to paste a `hooks.slack.com/services/...` URL). See `$implexa-run-scheduled` for the graceful-fail behavior if a slack-plugin schedule does fire on Codex.

  ## Default destination

  If the user gave only the skill slug + schedule without mentioning Slack, **do not ask** for Slack details. Default to dashboard. They can add Slack later by re-running `$implexa-schedule` with the same args + a destination.

## Step 2 — Call `schedule_skill`

Call `schedule_skill` with the parsed args:

```jsonc
{
  "skillSlug":   "daily-ai-skills-pulse",
  "scheduleNl": "daily at 8:55am",
  "destination": { "type": "dashboard" }
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

(The `claudeScheduledTaskPrompt` field is named for legacy reasons; on Codex you'll feed the same prompt into whichever path the user picks below.)

If `ok === false`, the tool returns an `error` string. Common cases:
- Unknown skill slug → ask the user to install/fork it first
- Unparseable schedule → echo the supported patterns from the error message
- Invalid Slack webhook URL → ask user to paste a real `hooks.slack.com` URL

## Step 3 — Ask the user which Codex scheduling path

Present three options as a numbered list. Codex has no native scheduling MCP, so the user picks the trigger mechanism they want to use:

```
how do you want to wire up the trigger?

  1. system cron (Recommended), most reliable, headless, no app required. one crontab line, fires forever.
  2. Codex app Automations, uses the Codex desktop app's Automations panel. fires while the app is open.
  3. GitHub Actions, runs in cloud on Actions' scheduler. no laptop required, fires 24/7.

reply with 1, 2, 3, or describe what you want.
```

Wait for the user's reply. Parse:
- `1` / "cron" / "system" / "headless" → **Path A**
- `2` / "codex app" / "app" / "automations" → **Path B**
- `3` / "github" / "actions" / "cloud" → **Path C**
- ambiguous free text → ask once for clarification, then accept

## Step 4 — Generate setup instructions for the chosen path

### Path A — system cron

Show the user the exact crontab line to add (substitute the real cron and uuid from the schedule_skill response):

```
0 8 * * * codex exec "$implexa-run-scheduled <scheduledSkillId>"
```

Then tell them:

1. Run `crontab -e` to open the crontab editor.
2. Paste the line above.
3. Save and exit (`:wq` in vim, `Ctrl+X` then `Y` in nano).
4. Verify with `crontab -l | grep implexa`.

Confirm: *"scheduled. next run fires `<humanizedSchedule>`. to disable, remove the line via `crontab -e`."*

### Path B — Codex app Automations

Tell the user:

1. Open the Codex desktop app (macOS or Windows).
2. Navigate to the Automations panel.
3. Click "New automation" and enter:
   - **Cron**: `<cronExpression>`
   - **Prompt**: `$implexa-run-scheduled <scheduledSkillId>`
   - **Timezone**: `<timezone>`
4. Click Save.

Confirm: *"once you click Save in the Codex app, runs fire at the scheduled time. manage at the Codex app's Automations panel. note: the app must be open (or set to run in background) for fires to land."*

### Path C — GitHub Actions

Generate this YAML workflow snippet and tell the user to commit it to `.github/workflows/implexa-scheduled-run.yml` in any repo they own:

```yaml
name: Implexa scheduled run
on:
  schedule:
    - cron: '<cronExpression>'
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Implexa skill
        run: |
          npm install -g @openai/codex
          codex exec "$implexa-run-scheduled <scheduledSkillId>"
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          IMPLEXA_API_KEY: ${{ secrets.IMPLEXA_API_KEY }}
```

Substitute `<cronExpression>` and `<scheduledSkillId>` with the real values from Step 2.

Then tell them:

1. Add `OPENAI_API_KEY` and `IMPLEXA_API_KEY` to the repo's secrets (Settings → Secrets and variables → Actions).
2. Commit + push the workflow file to `main`.
3. Verify with `gh run list -w "Implexa scheduled run"` (or check the Actions tab in the GitHub UI).

Confirm: *"once committed + pushed, GitHub Actions fires the run at the scheduled cron. no laptop required. verify with `gh run list -w 'Implexa scheduled run'` or the Actions tab."*

## Step 5 — Confirm to the user

Render a concise confirmation:

```
✓ scheduled `<skillSlug>` <humanizedSchedule>.
  trigger: <system cron / Codex app / GitHub Actions>
  output → <destination summary>
  manage at: app.implexa.ai/scheduled
```

Where `<destination summary>` is:
- `Implexa dashboard only` (default)
- `Slack (via webhook) + Implexa dashboard` (when `slack-webhook` configured — do NOT echo the webhook URL)

Keep it ≤ 5 lines. Do not echo the cron expression unless the user asked for it.

## What's next?

Schedule management is now available from inside the agent (no dashboard hop needed):

- `Pause this schedule` → `mcp__implexa__pause_scheduled_skill({ scheduledSkillId })` — flip status to paused. Idempotent.
- `Resume a paused schedule` → `mcp__implexa__resume_scheduled_skill({ scheduledSkillId })` — flip back to active.
- `Delete a schedule` → `mcp__implexa__delete_scheduled_skill({ scheduledSkillId })` — hard-delete the manifest. Historical runs at app.implexa.ai/runs are preserved.
- `List all my schedules` → `mcp__implexa__list_scheduled_skills({})` — returns every schedule with natural-prose humanizedSchedule, nextRunInfo, destinationLabel, runCount, lastRunAt.
- `Run it once now to test` — invoke `$implexa-run-scheduled <id>` directly (or `codex exec "$implexa-run-scheduled <id>"` from the shell).
- `Manage in the dashboard` — app.implexa.ai/scheduled is still live as the visual alternative.

Pausing / deleting in the Implexa dashboard only updates the manifest. The trigger you wired in Step 4 still fires until you also remove it from crontab / Codex app / GitHub Actions. The `$implexa-run-scheduled` wrapper silently exits when the manifest is paused or deleted, so no harm done, just wasted fires.

## Notes for the model

- **Default to dashboard destination** unless the user explicitly mentions Slack. Asking for a Slack webhook URL when they didn't ask for Slack is friction.
- **On Codex, only slack-webhook destination is supported for Slack delivery.** Claude Code supports both plugin + webhook; Codex needs the webhook URL. If the user asks for Slack and doesn't have a webhook URL, point them at https://api.slack.com/messaging/webhooks to create one.
- **Slack webhook URLs are not secret-secret but should not be echoed back to the user.** When confirming, say "Slack via webhook" not the full URL.
- **Reuse the user's typed schedule string** when calling `schedule_skill`. The natural-language parser handles capitalization and whitespace.
- **One invocation, one schedule.** Don't try to register two schedules in one invocation. If the user wants two, run `$implexa-schedule` twice.
- **Telemetry is automatic.** The schedule_skill tool writes the manifest + the wrapper skill writes each run to skill_runs.
- **Step 3's path choice is the user's call.** Don't push a recommendation beyond marking system cron as "(Recommended)". The user knows their setup; respect their pick.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `schedule_skill` returns ok=false with "Skill not found" | The skill isn't in the user's library | "I couldn't find `<slug>` in your library. Fork it from a Playbook or install via a share link, then re-run `$implexa-schedule`." |
| `schedule_skill` returns ok=false with "Could not parse schedule" | NL parser couldn't match a pattern | Echo the supported patterns from the error message. Ask the user to rephrase. |
| `schedule_skill` returns ok=false with "slack-webhook destination requires..." | Webhook URL invalid or missing | Ask the user to paste a real `hooks.slack.com/services/...` URL. |
| User picked slack-plugin on Codex | Not supported on Codex | Tell them: "slack-plugin destination is Claude Code-only. Want to switch to slack-webhook? Paste a `hooks.slack.com/services/...` URL." |
| Schedule registered but later runs never fire | Trigger lost on the user's side | Ask which path they wired (cron / app / Actions) and walk them through verifying it: `crontab -l | grep implexa`, check the Codex app's Automations panel, or `gh run list -w 'Implexa scheduled run'`. |
