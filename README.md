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
the other five are the pieces it delegates to — each also usable on its own,
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

**Requires:** [`gh`](https://cli.github.com/) (authenticated), `jq`, and
(optionally) a Slack MCP server for the review-announcement step and the
claude-in-chrome extension for UI evidence.

## License

MIT — see [LICENSE](LICENSE).
