# agent-skills

Personal collection of [Agent Skills](https://agentskills.io) for Claude Code
and other coding agents.

Eleven skills, mostly one pipeline: a GitHub issue goes in, a merged PR comes
out, and you get told about it out loud. Each piece also stands alone.

```bash
npx skills add guillermoscript/agent-skills                     # everything
npx skills add guillermoscript/agent-skills --skill work-issue   # just one
```

## At a glance

| Skill | Does |
| --- | --- |
| [`work-issue`](skills/work-issue/SKILL.md) | Issue URL → reviewable, announced PR. The orchestrator. |
| [`issue-plan`](skills/issue-plan/SKILL.md) | Read an issue, survey the code, post a plan of attack. |
| [`ui-evidence`](skills/ui-evidence/SKILL.md) | Before/after screenshots and a verification GIF on the PR. |
| [`ship-pr`](skills/ship-pr/SKILL.md) | Branch → template-compliant PR, announced on Slack. |
| [`pr-review-loop`](skills/pr-review-loop/SKILL.md) | Watch **your** PR until merged, then close out and clean up. |
| [`pr-review-watch`](skills/pr-review-watch/SKILL.md) | Review **someone else's** PR until merged. |
| [`gh-repo-config`](skills/gh-repo-config/SKILL.md) | Discover and cache a repo's workflow facts. |
| [`gh-board`](skills/gh-board/SKILL.md) | Drive any GitHub Projects (v2) board by name. |
| [`terse`](skills/terse/SKILL.md) | Report back in compressed prose. Grammar loses to information. |
| [`claude-sounds`](skills/claude-sounds/SKILL.md) | A sound for how the turn ended, and for commits, pushes, merges. |
| [`sound-setup`](skills/sound-setup/SKILL.md) | Wizard for the above — pick sounds by ear, remap any event. |

## The GitHub pipeline

```
your issue        issue-plan → implement → ui-evidence → ship-pr → pr-review-loop → merged
                  plan+board    (you)      GIF+shots     PR+Slack  feedback, merge,
                                                                   close-out, cleanup

their PR          pr-review-watch → review, verdict, re-review each push → merged

used by both      gh-repo-config (repo facts, config)  ·  gh-board (project board)
```

`work-issue` runs the top row end to end. The rest are the pieces it
delegates to — each usable on its own, and concatenable in any subset (plan
only, ship only, close-out only…).

The two loops are the same idea from opposite chairs and never run on the
same PR: `pr-review-loop` watches **your** PR and handles the feedback,
`pr-review-watch` reviews **someone else's** and submits the verdicts. Both
poll on a session-scoped cron, both are stateless — GitHub is the only state,
so a dead session costs nothing; re-invoke and it catches up — and both clean
up the local checkout once the PR lands.

Everything shares one per-repo config file,
`.claude/gh-workflow.config.json`, so a repo is set up once and every skill
in the chain picks it up.

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

Extra skills come in as `+args` and get folded into the implementation step.

### [`issue-plan`](skills/issue-plan/SKILL.md)

The front half on its own: read an issue (comments and references included),
survey the code it touches read-only, author a four-part plan of attack
(root cause, approach, risks, test plan), then assign the issue, move it to
*In Progress*, and post the plan as the issue comment teammates read. "Plan
#123, don't code it."

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

The back half after the announcement, for a PR **you authored**: watch it on
an in-session cron, answer reviewer questions on-thread, implement requested
changes and push them, iterate until approval, then merge automatically and
trigger `ship-pr`'s close-out (plus a "merged" note on Slack). Keeps the
board honest throughout — *Changes Requested* while we owe work, *In Review*
while the reviewer does. Red CI is reported, never auto-fixed.

Once merged it cleans up after itself: removes the worktree, deletes the
merged branch, and leaves you on an up-to-date default branch. Every deletion
is guarded — uncommitted changes, stashes and unpushed commits stop that step
and get reported instead of destroyed, so cleanup can never eat work that
exists only on your machine.

```
/pr-review-loop https://github.com/<owner>/<repo>/pull/123
/pr-review-loop            # resolves the PR from the current branch
```

### [`pr-review-watch`](skills/pr-review-watch/SKILL.md)

The same loop from the **reviewer's** chair, for a PR you did *not* author.
Runs `/code-review` and `/security-review` over the diff, then submits a real
GitHub review — `APPROVE` or `REQUEST_CHANGES`, both automatic — with inline
comments on the lines that earned them. Every later cycle re-reviews only the
commits pushed since your last review, answers the author on your own threads
and resolves them once they're genuinely addressed. Approves on code quality
alone: a red build is a heads-up in the review body, not a veto. Never merges
— that's the author's button.

```
/pr-review-watch https://github.com/<owner>/<repo>/pull/123
```

Install just the review pair:

```bash
npx skills add guillermoscript/agent-skills \
  --skill pr-review-loop --skill pr-review-watch
```

### Shared infrastructure

These two carry no workflow of their own — the skills above call them, and
you can call them directly.

#### [`gh-repo-config`](skills/gh-repo-config/SKILL.md)

Discovers a repo's workflow facts (repo, gh user, PR template, branch/commit
conventions, build commands) and caches the non-discoverable ones (project
board, Slack channel, default reviewer) in
`.claude/gh-workflow.config.json`, asking at most once per repo.

#### [`gh-board`](skills/gh-board/SKILL.md)

Operates any GitHub Projects (v2) board by name — add items, find them, set
Status/Priority/Size or any single-select field — with field and option IDs
resolved at call time, nothing hardcoded. "Move #123 to In Review."

### Requirements

**The GitHub-workflow skills require:** [`gh`](https://cli.github.com/)
(authenticated) and `jq`.

Optional, each skipped with a note when absent rather than failing:

- a Slack MCP server — announcement and merge notes
- the claude-in-chrome extension — UI evidence
- a GitHub Projects (v2) board — the board moves

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

A sound when a turn ends, picked by outcome and scaled by how much code was
written — a small fix gets a vine boom, a 1000-line refactor gets a ten-second
`I GOT THIS FAAAAAHHHH`. Plus sounds while you work: commits, pushes, PRs
opened and merged, test runs, and when Claude is waiting on your approval.
Ambient awareness for long runs — walk away and still know whether it landed,
died, or needs you.

Three packs (`tiktok`, `zelda`, `mario`), and every event is remappable, so
the Zelda chest can be your PR-merged sound.

Installs `Stop`, `PostToolUse` and `Notification` hooks; works in any Claude
Code session, no skill required at runtime. The one-liner also installs the
`sound-setup` wizard below.

```bash
curl -fsSL https://raw.githubusercontent.com/guillermoscript/agent-skills/main/skills/claude-sounds/install.sh | bash -s -- --pack zelda
```

**Requires:** `jq`, `curl`, and an audio player (`afplay` on macOS; `mpv`,
`ffplay`, `mpg123` or `paplay` on Linux). Audio is downloaded from
myinstants.com to your own machine at install time — this repo ships URL
manifests, not the sounds.

### [`sound-setup`](skills/sound-setup/SKILL.md)

The wizard for the above, **installed automatically by the `claude-sounds`
one-liner** — no separate step. Asks what you want to hear and when, plays each
candidate out loud before committing to it, and can search myinstants for
something it doesn't ship. Also where you set up custom triggers — "when the
message says *deployed to production*, play the chest sound".

Writes `~/.claude/hooks/sound-rules.json`, which is re-read on every event, so
changes apply immediately with no reinstall or restart.

```
/sound-setup
```

## Repo layout

```
skills/<name>/SKILL.md          the skill itself
skills/<name>/scripts/*.sh      bundled helpers, invoked by the skill's own path
skills/<name>/evals/evals.json  trigger evals — does the description fire when it should
skills/claude-sounds/*.sh       the hook scripts, installed to ~/.claude/hooks
skills/claude-sounds/packs/     sound pack URL manifests
skills.sh.json                  how skills.sh groups these for browsing
```

Nine of the eleven skills ship trigger evals (both sound skills are
hook-driven, so there's no description to eval). Helper scripts are bundled
with the skill rather than the target repo, so they're invoked via
`<skill-dir>/…` and work in any checkout.

## License

MIT — see [LICENSE](LICENSE).
