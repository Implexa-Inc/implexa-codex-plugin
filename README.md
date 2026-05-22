# implexa — the skill graph for ai work.

> **demonstrate any workflow once. capture decision traces. share with your team. measure what actually worked. compatible with the [agentskills.io](https://agentskills.io) open standard — your skills run in Codex, Claude Code, Cursor, Gemini CLI, and 30+ more agents.**

[![Built on agentskills.io](https://img.shields.io/badge/Built%20on-agentskills.io-22c55e?style=flat-square)](https://agentskills.io)
[![MIT plugin](https://img.shields.io/badge/Plugin-MIT-blue?style=flat-square)](https://github.com/Implexa-Inc/implexa-codex-plugin/blob/main/LICENSE)
[![Free forever](https://img.shields.io/badge/Free%20tier-Forever-orange?style=flat-square)](https://implexa.ai)

```bash
curl -fsSL https://core.implexa.ai/install-for-codex.sh | bash
```

one paste. ~30 seconds. browser opens for sign-up/sign-in, you approve, terminal wires everything else. installs the api key and mcp config — done.

free forever. no credit card. MIT-licensed plugin, hosted service.

[**implexa.ai**](https://implexa.ai) - [public skills](https://app.implexa.ai/skills) - [dashboard](https://app.implexa.ai) - [skill format docs](https://implexa.ai/codex-skills)

---

## what it does

`$implexa-record-skill` is the killer feature. demonstrate any workflow once. implexa captures every tool call, runs a structured interview to lock the intent, and emits a **6-component skill** (intent + inputs + procedure + decision points + output contract + outcome signal) that's:

- **replayable** - `$implexa-run "the prospecting one"` fuzzy-matches your library and re-executes
- **measurable** - outcomes attribute back via last-touch within a 30-day window
- **portable** - works in Codex, Claude Code, Cursor, Gemini CLI, and any MCP client
- **shareable** - team-gated (same email domain) or public links; public shares unlock Founding Creator status

---

## quick start

### 1. install

**marketplace (recommended):**
```bash
npx codex-marketplace add Implexa-Inc/implexa-codex-plugin --plugin
```

**one-line script:**
```bash
curl -fsSL https://core.implexa.ai/install-for-codex.sh | bash
```

works on macOS, Linux, and Windows (WSL). browser opens to approve the install. once you click Approve, the terminal finishes installing the api key and mcp wiring.

### 2. verify

open Codex and type:

```
$implexa-get-me-started
```

you'll see a quick-win Playbook run in under 10 minutes. paste a company name, a job description, or a calendar meeting — implexa pulls the research and shows you what the mcp tools can do.

### 3. record your first skill

```
$implexa-record-skill
```

tell Codex what you're about to demonstrate, then do your work normally. implexa watches every tool call. when you're done, it asks 2-4 questions to fill in gaps, then saves the skill. total time: ~3 minutes.

### 4. re-run anywhere

```
$implexa-run "the X one"
```

fuzzy match against your library. Codex picks the right skill and applies it with your current context.

---

## what's in the plugin

| skill | what it does |
|---|---|
| `$implexa-record-skill` | demonstrate once, get a structured skill back |
| `$implexa-run` | fuzzy-match + run a skill from your library |
| `$implexa-update-skill` | re-record into an existing skill to add a step or fix a branch |
| `$implexa-my-skills` | browse your personal library |
| `$implexa-org-skills` | browse your org's shared library |
| `$implexa-playbooks` | browse the 30 base Playbooks (sales, recruiting, finance, etc.) |
| `$implexa-fork` | clone any skill into your org for customization |
| `$implexa-share-this` | generate a share link — team-gated or public |
| `$implexa-publish-to-clawhub` | publish a skill to the ClawHub public marketplace |
| `$implexa-schedule` | schedule a skill to run daily, weekly, or hourly |
| `$implexa-run-scheduled` | internal callback when a scheduled run fires (not for humans) |
| `$implexa-morning` | chained skill orchestration — your daily brief in one command |
| `$implexa-skill-roi` | outcome attribution: which skills are actually driving revenue |
| `$implexa-get-me-started` | first-run activation — quick win in under 10 minutes |

---

## phase 1 — what works and what's deferred

shipping this fast. these limits are documented + tracked, fixes coming in phase 2:

| capability | works on codex? | phase 2 fix |
|---|---|---|
| `$implexa-record-skill` (capture a workflow) | ✓ works | demo capture is thinner than claude code until codex lifecycle hooks (SessionStart, etc.) wire in |
| `$implexa-run` (re-execute a skill) | ✓ full parity | nothing to fix |
| `$implexa-share-this` + forking + outcome attribution | ✓ full parity | nothing to fix |
| `$implexa-publish-to-clawhub` | ✓ full parity | nothing to fix |
| `$implexa-schedule` (cron-based scheduling) | **partial** | manifest registers in our backend, but codex doesn't have a built-in cron mechanism. you'd run `$implexa-run-scheduled <id>` manually or wire your own cron / launchd / systemd loop until v2 ships a server-side scheduler |
| interactive multi-choice prompts in record/update flows | **degraded** | falls back to plain text input on codex. claude code has a native picker; codex doesn't yet. functional, just less polished |
| `slack-plugin` destination for scheduler outputs | not supported | use `slack-webhook` destination instead. cross-vendor, just needs a `hooks.slack.com` URL |

the rest is full parity. backend is identical across both runtimes.

---

## the skill graph flywheel

every team has a few power users with integrations already wired (HubSpot, Salesforce, Linear, GitHub, Apollo, etc.). implexa turns their expertise into portable skills the rest of the org can invoke.

```
1. power user connects tools to Codex
   |
2. they record a skill that uses those tools
   |
3. implexa captures the tool chain in the skill
   |
4. a teammate runs the skill via $implexa-run
   |
5. if the teammate is missing a required tool, implexa surfaces an install hint
   |
6. they install. run the skill. get the outcome.
```

everyone in the org now has the power user's stack. power users get **Founding Creator** status: unlimited captures + a free Pro seat for life.

---

## under the hood

- **mcp transport**: streamable HTTP (same backend as the Claude Code plugin — `https://core.implexa.ai/api/v2/mcp`)
- **40+ mcp tools**: skill graph ops, external data fetching (Fiber AI, Coresignal, Apollo), outcome attribution, share/fork, scheduling
- **skill format**: agentskills.io-compliant SKILL.md — 6-component structure
- **outcome attribution**: last-touch within a 30-day window from CRM/ATS/calendar events
- **domain-gated sharing**: team links only let users on your email domain install

---

## pricing

- **free forever** - 5 skill captures/month, unlimited skill runs, public sharing
- **founding creator** (free perk) - share 1 public skill, unlock unlimited captures + a free Pro seat for life
- **pro** - $19/mo or $190/year - unlimited captures, team library, audit log, SSO

---

## uninstall

remove the `[mcp_servers.implexa]` block from `~/.codex/config.toml`. your skills stay in the dashboard at app.implexa.ai. to revoke the api key, go to [connected installs](https://app.implexa.ai/settings/api-keys).

---

## links

- implexa.ai - marketing site
- app.implexa.ai/skills - public skills directory
- app.implexa.ai/install - full install guide (logged-in)
- hello@implexa.ai - questions, feedback, bug reports
- github.com/Implexa-Inc/implexa-codex-plugin - this repo

## license

[MIT](./LICENSE). plugin source + install scripts only. the backend service is not covered.
