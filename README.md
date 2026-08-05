# agent-skills

Personal collection of [Agent Skills](https://agentskills.io) for Claude Code
and other coding agents. Install any skill with the
[`skills` CLI](https://skills.sh/docs/cli):

```bash
npx skills add guillermoscript/agent-skills
```

Or install a single skill from this repo:

```bash
npx skills add guillermoscript/agent-skills --skill work-issue
```

## Skills

The GitHub-workflow skills compose: `work-issue` is the orchestrator, and
the other six are the pieces it delegates to — each also usable on its own,
and concatenable in any subset (plan only, ship only, close-out only…).
They share one per-repo config file, `.claude/gh-workflow.config.json`,
managed by `gh-repo-config`.

### [`work-issue`](skills/work-issue/SKILL.md)

End-to-end GitHub issue workflow: read an issue, plan it, move it to *In
Progress* on the project board (if one exists), implement it, verify UI
changes with a recorded GIF, open a template-compliant PR set to *In Review*
with labels and a milestone, and announce it on Slack for review (if
connected). Repo-agnostic — discovers everything at runtime via the skills
below.

```
/work-issue https://github.com/<owner>/<repo>/issues/123
/work-issue #123 +shadcn +animate
```

### [`issue-plan`](skills/issue-plan/SKILL.md)

The front half on its own: read an issue (comments and references included),
survey the code it touches read-only, author a four-part plan of attack
(root cause, approach, risks, test plan), then assign the issue, move it to
*In Progress*, and post the plan as the issue comment teammates read. "Plan
#123, don't code it."

### [`gh-repo-config`](skills/gh-repo-config/SKILL.md)

Discovers a repo's workflow facts (repo, gh user, PR template, branch/commit
conventions, build commands) and caches the non-discoverable ones (project
board, Slack channel, default reviewer) in
`.claude/gh-workflow.config.json`, asking at most once per repo.

### [`gh-board`](skills/gh-board/SKILL.md)

Operates any GitHub Projects (v2) board by name — add items, find them, set
Status/Priority/Size or any single-select field — with field and option IDs
resolved at call time, nothing hardcoded. "Move #123 to In Review."

### [`ui-evidence`](skills/ui-evidence/SKILL.md)

Visual proof for UI changes: "before" screenshots captured while the code is
untouched, a recorded verification GIF, matching "after" shots, and the
browser-upload dance that attaches them to PRs on private repos.

### [`ship-pr`](skills/ship-pr/SKILL.md)

Takes an implemented branch to a reviewable PR: template-compliant body with
a QA script, draft-first lifecycle, labels/milestone/board linkage, a strict
ready gate, and a Slack announcement that actually gets seen. After approval
and merge, posts the close-out pair — a final "what shipped" comment on the
PR and a short resolution comment on the issue referencing it.

### [`pr-review-loop`](skills/pr-review-loop/SKILL.md)

The back half after the announcement: watch the PR on an in-session cron,
answer reviewer questions on-thread, implement requested changes and push
them, iterate until approval, then merge automatically and trigger
`ship-pr`'s close-out (plus a "merged" note on Slack). Stateless — GitHub
threads are the only state, so `/pr-review-loop #123` resumes seamlessly
after a dead session. Red CI is reported, never auto-fixed.

```
/pr-review-loop https://github.com/<owner>/<repo>/pull/123
/pr-review-loop            # resolves the PR from the current branch
```

**Requires:** [`gh`](https://cli.github.com/) (authenticated), `jq`, and
(optionally) a Slack MCP server for the review-announcement step and the
claude-in-chrome extension for UI evidence.

## Output style

### [`terse`](skills/terse/SKILL.md)

Report back in maximally compressed prose — articles, copulas, hedges and
pleasantries dropped, one line per fact. Grammar loses to information.
Applies to reporting only: code, commit messages, PR bodies and
explanation-shaped answers keep their full shape.

```
/terse
```

## Notifications

### [`claude-sounds`](skills/claude-sounds/SKILL.md)

Play a different meme sound when a turn ends, picked by outcome and scaled
by how much code was written — a small fix gets a vine boom, a 1000-line
refactor gets a ten-second `I GOT THIS FAAAAAHHHH`. Failures get a BRUH,
questions get a `hmmm`. Ambient awareness for long runs: you can walk away
and still know whether it landed, died, or is waiting on you.

Installs a `Stop` hook; works in any Claude Code session, no skill required
at runtime.

```bash
curl -fsSL https://raw.githubusercontent.com/guillermoscript/agent-skills/main/skills/claude-sounds/install.sh | bash
```

**Requires:** `jq`, `curl`, and an audio player (`afplay` on macOS; `mpv`,
`ffplay`, `mpg123` or `paplay` on Linux). Audio is downloaded from
myinstants.com to your own machine at install time — this repo ships a URL
manifest, not the sounds.

## License

MIT — see [LICENSE](LICENSE).
