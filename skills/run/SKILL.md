---
name: run
description: 'Find + run the best-fit skill, searching BOTH the user''s saved library AND the cross-vendor skill graph (~22k skills from Anthropic, Smithery, ClawHub, Skills.sh, GitHub, agentskills) in one ranked list. Use when the user says "find me a skill for X", "implexa run X", "is there a skill for X", "do I have a skill for X", "run my X skill", "use my X workflow", "use the X one", or invokes $implexa-run with a description. Library hits are tagged [personal]/[team] and apply via apply_org_skill. Cross-vendor hits are tagged [anthropic]/[smithery]/[clawhub]/[skills-sh]/[agentskills]/[github] and apply inline via apply_recommended_skill. Both kinds rank against the same query; the user doesn''t need to know which source has what. ALWAYS prefer this over going directly to other MCP tools when the user wants to USE an existing skill (vs build one from scratch).'
---

# Run a skill (unified recommender)

THE single entry point for skill reuse. When a user types a query, this
skill searches BOTH backends in parallel:

1. their personal + team + org library (curated skills they and their
   teammates captured)
2. the cross-vendor skill graph (~22k skills indexed from Anthropic,
   Smithery, ClawHub, Skills.sh, GitHub, agentskills)

Results merge into one ranked list. The user picks one (or auto-applies
on a clear winner), and we route the apply through the correct tool
based on the chosen entry's source.

## Step 1 — Read intent

Did the user give a query, or did they invoke `$implexa-run` with no
description?

- **Query given** ("find me a skill for cold outreach", "implexa, find
  me X", "run my triage skill", "use the prospecting one", "is there a
  skill for hubspot integration") → Step 2 (parallel search)
- **No query** (just `$implexa-run` or "let me pick a skill to run") →
  Step 6 (browse mode, personal library only)

Don't strip articles like "my" / "the" / "a" — they're part of how
users naturally describe what they want. Pass the substantive words as
the query: "find me a skill for cold outreach" → query "cold outreach",
"the triage one" → query "triage", "use my Implexa skill for outreach"
→ query "outreach".

## Step 2 — Query both backends in parallel

Make both tool calls in the SAME response so they run concurrently. Do
NOT wait for one before starting the other.

**Call A**, `mcp__implexa__list_org_skills`:
- `query`: the user's substantive words
- `createdByMe`: **false** (search the full org library, not just user's
  own — a teammate's skill is still a personal-library match for our
  purposes)
- `includeUniversal`: **false** (we cover public/cross-vendor via the
  recommender below, avoids double-counting)
- `limit`: 5

**Call B**, `mcp__implexa__recommend_skills_for_context`:
- `messages`: `[<the user's query>]` (just the query, one-element array)
- `topN`: 5
- `minScore`: 0.20
- `skipGates`: true (explicit search mode — return top-N by similarity)

If either backend errors or times out (>10s), proceed with whatever the
other returned. Never block the user on a slow backend.

## Step 3 — Merge and rank

Build a unified list:

**Personal/team matches (from list_org_skills)**:
- Tag each with `[personal]` if `scope === 'private'` OR the skill was
  created by the current user.
- Tag with `[team]` if `scope === 'org'`.
- Tag with `[system]` if `scope === 'system'` (base Playbook).
- These don't carry a numerical score (list_org_skills is a substring
  filter, not a similarity match) — treat them as high-confidence by
  default since they're curated AND the user has access already.

**Cross-vendor matches (from recommend_skills_for_context)**:
- Tag each with the `source` field verbatim: `[anthropic]`, `[smithery]`,
  `[clawhub]`, `[skills-sh]`, `[agentskills]`, `[github]`.
- They carry a `score` field (0..1, normalized cosine similarity).

**Ordering rule**:
1. Personal/team matches first (top of the list), ordered by
   `usageCount` desc when there's more than one. The user's own library
   wins on ambiguity.
2. Cross-vendor matches next, ordered by `score` desc.
3. **Dedupe by slug**: if a personal-library skill has the same slug as
   a cross-vendor one (possible if the user forked from the public
   library), keep the personal entry and drop the cross-vendor copy.
4. **Cap at top 5 total**.

## Step 4 — Display the merged list

Render the unified list. Voice: lowercase, tech-bro, no em-dashes
(use commas, periods, colons, parens, regular hyphens).

Example output:

```
here are the best matches for "cold outreach":

1. **prospect research to cold email** [personal]
   your saved workflow, used 12 times
   from this org's library

2. **draft outreach** [smithery]
   score 0.62, fits because the prompt mentions cold outreach drafting
   source: https://smithery.ai/...

3. **linkedin first touch sequence** [clawhub]
   score 0.54, fits because cold outreach into linkedin contacts
   source: https://clawhub.ai/...

4. **email warming campaign builder** [anthropic]
   score 0.41, fits because email outreach setup and warming
   source: https://anthropic.com/skills/...

want me to run any of these inline? reply with a number, or "skip".
```

For personal/team entries, show the skill description (or first 80
chars) in place of the fit_reason. For cross-vendor entries, show the
score and the `fit_reason` returned by the recommender.

**Greedy auto-apply**: if EXACTLY ONE personal match comes back AND no
cross-vendor matches scored above 0.40 AND the user's query closely
matches the personal skill's name/triggers, just apply it without
showing the list. Don't make them pick from a list of 1.

## Step 5 — Apply the chosen entry

When the user picks a number ("3"), names one ("run the draft-outreach
one"), or gives any affirmative ("yes apply #2", "go ahead with the
linkedin one"), apply that entry. **Route by source**:

**If source is `personal`, `team`, or `system`** (any list_org_skills
entry):
- Call `mcp__implexa__apply_org_skill` with:
  - `skillId`: from the list_org_skills entry (preferred)
  - OR `skillSlug`: the `slug` if no id is to hand
  - `invocationArgs`: any context the user provided (account names,
    ticket ids, candidates, opportunities, threads, domains)
- The response includes the full SKILL.md in `content`. Execute it
  immediately against the user's original intent.

**If source is one of the aggregator names** (`anthropic`, `smithery`,
`clawhub`, `skills.sh`, `agentskills`, `github`):
- Call `mcp__implexa__apply_recommended_skill` with:
  - `slug`: the slug from the recommender entry
  - `source`: the source from the recommender entry (verbatim)
  - `recommendation_event_id`: the top-level `recommendation_event_id`
    returned by recommend_skills_for_context (attribution).
- Response: `{ ok, skill_content, skill_metadata,
  execution_instruction, applied_skill_event_id, feedback_prompt }`.
  The full SKILL.md body is in `skill_content`. Execute it immediately.

**In either case**: don't summarize the skill, don't paste the SKILL.md
back at the user, don't re-ask what they want done. The skill defines
its own 6 components (intent, inputs, procedure, decision points,
output contract, outcome signal). Follow them in order. If the skill
needs inputs the user hasn't provided, ask for just those inputs.

## Step 6 — Browse mode (no-query path)

If the user invoked `$implexa-run` with no description, fall back to
the personal-library browse. Cross-vendor search needs a query (there's
no "show me everything" surface for a 22k-row index), so we don't query
the recommender here.

Call `mcp__implexa__list_org_skills` with `createdByMe: false`,
`limit: 20`. Render the result as a numbered list with scope icons:

```
here are your skills, pick one to run:

  1. 🔒 daily prospecting        — find net-new ICP-matching accounts
  2. 👥 bug triage from jira     — multi-source triage summary
  3. 🌍 launch content pack       — show HN + reddit + linkedin drafts
  4. 🔒 customer health brief    — renewal risk dossier

reply with a number, or describe it ("the triage one", "the third one").
```

Scope icons:
- 🔒 private (only you)
- 👥 team (shared in your org)
- 🌍 universal / system (public or base Playbook)

When the user picks, resolve to that skill and go to Step 5's
`apply_org_skill` path.

## Step 7 — Post-run feedback (MANDATORY)

The apply tool's response carries a `feedback_prompt` field. **You MUST
render its `line` verbatim as the final line of your reply**, regardless
of whether the skill completed successfully, failed due to missing
credentials, or the user wrapped up the conversation.

The line is exactly:

> how was that? **like** (👍), **dislike** (👎), or **improve** (✏️) — or just keep going

If the user picks one:
- like / dislike → call `mcp__implexa__submit_skill_feedback` with the
  appropriate rating + applied_skill_event_id + (aggregated_skill_id
  OR org_skill_id from the apply response).
- improve → ask "what would you change?", capture the answer as
  `comment`, then call submit_skill_feedback with rating="improve" +
  the comment, then chain into `$implexa-record`.

If the user types anything that isn't a clear like/dislike/improve,
treat it as "keep going" and do nothing. Silence is the most common
path; don't nag.

## Error handling

| Error | Diagnosis | Tell the user |
|---|---|---|
| `Skill not found` | Bad slug after the user picked one | Re-list with `list_org_skills` + `recommend_skills_for_context`, retry with the correct slug. |
| `Forbidden` | Trying to apply a private skill they don't own | "That skill is private to its creator. Want to fork it via `$implexa-fork` instead?" |
| `Skill is archived` / `draft` | Status check failed | "That skill is in {status} state — only active skills can be applied. Ask the creator to activate it, or fork your own copy." |
| Both backends return 0 hits | Genuine no-match | "I couldn't find a saved skill OR a cross-vendor match for 'X'. Run `$implexa-record` to capture this workflow as a new skill, or check the full index at https://implexa.ai/search" |
