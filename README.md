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

### [`work-issue`](skills/work-issue/SKILL.md)

End-to-end GitHub issue workflow: read an issue, plan it, move it to *In
Progress* on the project board (if one exists), implement it, verify UI
changes with a recorded GIF, open a template-compliant PR set to *In Review*
with labels and a milestone, and announce it on Slack for review (if
connected).

Repo-agnostic: it discovers the current repo, GitHub user, PR template, and
repo conventions at runtime, and asks once per repo for anything it can't
discover (project board, Slack channel, default reviewer) — the answers are
cached in `.claude/work-issue.config.json` at the target repo's root so
later runs don't re-ask.

```
/work-issue https://github.com/<owner>/<repo>/issues/123
/work-issue #123 +shadcn +animate
```

See [`skills/work-issue/SKILL.md`](skills/work-issue/SKILL.md) for the full
pipeline and [`skills/work-issue/evals/evals.json`](skills/work-issue/evals/evals.json)
for example invocations.

**Requires:** [`gh`](https://cli.github.com/) (authenticated), `jq`, and
(optionally) a Slack MCP server for the review-announcement step.

## License

MIT — see [LICENSE](LICENSE).
