---
name: work-issue
description: End-to-end GitHub issue workflow, repo-agnostic — read an issue, plan it, move it to In Progress on the project board (if one exists), implement it with efficient-fable orchestration, verify UI changes with a recorded GIF, open a template-compliant PR set to In Review with labels and milestone, and announce it on Slack for review (if connected). Supports extra skills as +args (e.g. "/work-issue <url> +shadcn +animate"). Use whenever the user pastes a GitHub issue URL or issue number and wants it worked on — "work on this issue", "pick up #123", "start this one", "ship this issue", "take https://github.com/.../issues/N" — even if they don't name the skill.
---

# Work Issue — issue URL to reviewed PR

Automates the full issue-to-PR pipeline for whatever GitHub repo the current
working directory belongs to. The user pastes an issue URL (or number); you
deliver a merged-ready PR with the project board, labels, milestone, and QA
record all handled. Every step exists because a human reviewer or QA person
consumes its output later — the issue comment is the public record of the
approach, the PR body is the QA script, the GIF is the visual proof. Write
those artifacts for *them*, not for the user in this chat.

This skill is repo-agnostic: it discovers the repo, GitHub user, project
board, and repo conventions at runtime rather than assuming a specific
project. Facts that can't be discovered automatically (which project board to
use, which Slack channel, who to ping) live in a small per-repo config file
that Step 0 creates on first use and reuses on every run after.

## Bundled helpers

| What | Path | Purpose |
|---|---|---|
| Board helper | `scripts/board.sh` | Generic GitHub Projects (v2) add/find/status/priority/size — resolves field & option IDs by name at call time, works against any board |
| Config helper | `scripts/config.sh` | Reads/writes `<repo-root>/.claude/work-issue.config.json` |

Both are bundled with this skill (not the target repo), so always invoke them
by the skill's own path, e.g. `<skill-dir>/scripts/board.sh`. Find `<skill-dir>`
from wherever this SKILL.md was loaded from.

## Step 0 — Resolve repo facts and per-repo config

Do this before anything else; every later step depends on it.

1. **Repo.** `gh repo view --json nameWithOwner,url -q .nameWithOwner` from the
   cwd — `gh` resolves this from the git remote, so it works in any repo
   without configuration. If this fails (not a git repo, no `gh` auth), stop
   and tell the user.
2. **GitHub user to assign.** `gh api user -q .login` — the currently
   authenticated `gh` user. Don't hardcode a username.
3. **Load or create the config file**: run
   `<skill-dir>/scripts/config.sh read` (creates nothing yet, just reads).
   This is a small JSON file at `<repo-root>/.claude/work-issue.config.json`
   holding facts that can't be discovered from the GitHub API alone:

   ```json
   {
     "projectBoard": { "owner": "<github-org-or-user>", "number": 1 },
     "slackChannel": "#pr-review",
     "slackChannelId": "C0123456789",
     "defaultReviewer": { "name": "Alex", "slackId": "U0123456789" },
     "prTemplate": ".github/pull_request_template.md",
     "branchConvention": "<type>/<N>-<slug>"
   }
   ```

   Every field is optional and repo-specific — this is just an example shape,
   not a default configuration. Only fill in what Step 0 actually resolves
   for the repo at hand.

   - If the file is missing or a key is missing, that feature is simply
     unconfigured — don't block the whole pipeline on it. Ask the user about
     each missing piece **once, up front**, right after reading the issue
     (batch the questions with AskUserQuestion rather than asking one at a
     time deep into the run):
     - *Project board*: try `gh project list --owner <org-from-repo> --format json`
       first — if exactly one open project references this repo, propose it
       instead of asking blind. If none/ambiguous, ask whether to use a board
       at all, and if so which number/owner.
     - *PR template*: check `.github/pull_request_template.md` and
       `.github/PULL_REQUEST_TEMPLATE.md` in the repo directly — no need to
       ask, just detect. If absent, note that PRs will be free-form.
     - *Slack*: check for a connected Slack MCP (ToolSearch for `slack`
       tools). If found, ask which channel and (optionally) a default
       reviewer to `@mention`. If no Slack MCP is connected at all, skip
       silently — don't ask about a channel for a tool that isn't there.
     - *Branch/commit convention*: read a handful of recent branch names
       (`git branch -r | tail -20`) and `git log --oneline -20` to infer the
       pattern rather than asking — most repos are consistent enough to
       reverse-engineer. Fall back to `<type>/<N>-<slug>` branches and
       Conventional Commits if history is sparse or inconsistent.
   - Write whatever was resolved (asked or inferred) back with
     `<skill-dir>/scripts/config.sh init` + editing the JSON, so the next run
     in this repo asks nothing. Tell the user you saved it and where, so they
     can edit or gitignore it if they want.
   - If the config file already has a value, trust it — don't re-ask or
     re-detect. If the user says a saved value is wrong mid-run, update the
     file immediately.

4. **Repo command conventions.** Look for `CLAUDE.md` / `AGENTS.md` at the
   repo root — most repos maintained with Claude Code have one describing
   lint/test/build/typecheck commands, directory layout, and gotchas specific
   to that codebase. If present, read it and follow it for Steps 5–6 instead
   of guessing. If absent, infer commands from `package.json` scripts (or the
   equivalent for the repo's language/toolchain) before running anything.

## Invocation and +skill params

The argument is the issue (URL, `#N`, or bare number), optionally followed by
extra skills prefixed with `+`:

```
/work-issue https://github.com/<owner>/<repo>/issues/302
/work-issue #302 +shadcn +animate
/work-issue 302 +systematic-debugging
```

Each `+name` is a skill to load in Step 2 **in addition to** the defaults.
This is the extension point: the user will keep adding skills to their
toolbox over time, so treat the list as open-ended. If a `+name` doesn't
match any available skill, say so briefly and continue without it — a typo
shouldn't sink the run.

### Worktree isolation — ask, don't assume

Before branching, ask the user (AskUserQuestion, one question) whether to run
in an isolated git worktree or directly in the working tree. Recommend
isolation when `git status` shows uncommitted changes — the pipeline creates
branches and commits, and doing that in a dirty tree risks tangling their
in-flight work. If they choose isolation, use EnterWorktree and run the whole
pipeline there; the working tree they were looking at never changes. If
they've answered before in this session or said "always isolate"/"never
ask", respect that instead of re-asking.

### Parallel mode — multiple issues

If the user passes more than one issue (`/work-issue #302 #305 #310`), run
each through the full pipeline in its own subagent with
`isolation: "worktree"` — isolation is not optional here, since parallel runs
would otherwise fight over branches and the working tree. Spawn the agents in
one message so they run concurrently, give each the full skill path and its
issue, and relay each PR URL as it lands. Anything that needs the shared
Chrome browser (GIF recording, GIF upload) serializes badly across parallel
agents — have each agent finish its PR and leave UI verification queued, then
do the Chrome-dependent steps yourself, one PR at a time, at the end.

## Division of labor — the main agent writes code, subagents do bookkeeping

The main agent's context is the scarcest resource in the run, and it should
be spent on the code: understanding, implementing, judging. Every
GitHub-mechanical action — issue comments, assignments, PR creation, labels,
milestones, board moves, Slack posts — is delegated to subagents. The split
is by *kind of work*, not by step:

- **Main agent authors content**: the plan text, the PR body, comment text,
  the Slack message. These need full session context and judgment.
- **Subagents perform mechanics**: they receive that content plus exact
  commands and run them, returning only what the main agent needs next (a PR
  URL, an item ID). They need no session context beyond what's in the prompt.
- **The one exception is Chrome** (screenshots, GIF recording, media
  upload): the browser is a single shared resource, so the main agent drives
  it directly.

## Pipeline

```
0. Resolve repo + config  →  1. Read issue  →  2. Load skills
→  3. Plan (+ before-screenshots if UI)  →  4. Housekeeping (subagent)
→  5. Branch + implement  →  6. Verify (+ GIF if UI)
→  7. Draft PR + board (subagent)  →  8. GIF + screenshots comment
→  9. Mark ready + Slack (subagent)
```

### Step 1 — Read the issue

Accept a full URL, `#N`, or a bare number. Gather everything in one pass:

```bash
gh issue view <N> --json number,title,body,labels,milestone,assignees,comments,url
```

Read the comments too — later comments often amend or overrule the original
body. If the issue references other issues/PRs (an epic parent, a "relates
to"), skim those for constraints. If the issue is genuinely ambiguous about
*what* to build (not *how* — that's your job), ask the user before touching
anything.

If the issue is already assigned to someone else or already In Progress on
the board, stop and ask the user before taking it over.

### Step 2 — Load the companion skills

Invoke via the Skill tool. Always load:

1. **`caveman`** — terse chat output for the session. Scope it: caveman
   applies to *conversation with the user only*. Everything written to
   GitHub or Slack (issue comments, PR body, commit messages, review
   announcements) is a permanent record read by other people — write those
   in normal, professional, full-sentence English.
2. **`efficient-fable`** — orchestration mode: you architect and judge;
   cheap subagents do bounded research/coding/testing legwork.

Conditionally load, when the issue is frontend work (a `frontend`/`UI`/`UX`
label, or the plan touches UI component/page files):

3. **`vercel-react-best-practices`** — React/Next.js performance patterns
   (skip if the repo isn't React/Next.js).
4. **`vercel-composition-patterns`** — component API and composition design
   (skip if the repo isn't React/Next.js).

Then load every `+skill` passed in the invocation (see "Invocation and
+skill params" above). When a loaded skill only applies to a sub-phase (e.g.
a design skill matters during implementation, not planning), apply it where
it fits rather than forcing it everywhere.

Do **not** invoke the full `improve` skill (it's a read-only advisor that
writes plan files under `plans/` and never implements). Instead, borrow its
posture for Step 3: survey first, read-only, and write the plan well enough
that someone with zero session context could follow it.

### Step 3 — Plan of attack

Before writing any code, survey the code the issue touches (read-only —
Explore subagents are good for this). Produce a short plan:

- **Root cause / current behavior** — what the code does today and why
  that's the issue.
- **Approach** — what will change, in which files.
- **Risks / blast radius** — what else touches this code. Check the repo's
  `CLAUDE.md`/`AGENTS.md` for documented gotchas (multi-tenancy, auth
  boundaries, basePath quirks, dual databases, feature flags — whatever that
  repo calls out) and weigh them here.
- **Test plan** — which checks will prove it works (commands + manual
  steps), using the commands discovered in Step 0.4.

This plan becomes the issue comment in Step 4 and the seed of the PR body in
Step 7, so write it once, well.

**Before-screenshots (UI issues only).** The only moment the "before" state
exists is now — once you've implemented, it's gone. If the issue touches
anything visible, open the affected screen(s) in Chrome while the code is
still untouched and take screenshots
(`mcp__claude-in-chrome__computer` screenshot action), saved as
`issue-<N>-before-<screen>.png`. Reviewers weigh a before/after pair far more
than a description of what changed. If the local app isn't running and
starting it is disruptive right now, note that "before" captures were
skipped and why.

### Step 4 — Housekeeping (spawn a subagent, don't block on it)

As soon as the plan exists, spawn one subagent to do the GitHub bookkeeping
while you start implementing. Give it the issue number, issue URL, the
resolved GitHub username, the plan text, and (if configured) the project
board owner/number, and have it run:

```bash
gh issue edit <N> --add-assignee <github-user-from-step-0>
if <board configured>; then
  ITEM=$(GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh find <owner>/<repo> <N>)
  [ -z "$ITEM" ] && ITEM=$(GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh add <issue-url>)
  GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh status "$ITEM" "In Progress"
fi
gh issue comment <N> --body-file <plan.md>
```

The comment should open with a one-line note that an AI agent is picking
this up, then the plan from Step 3. This is the public record teammates use
to see how the issue is being attacked — keep it factual and skimmable
(headers, short bullets).

### Step 5 — Branch and implement

Branch from up-to-date default branch (`gh repo view --json defaultBranchRef
-q .defaultBranchRef.name`), following the convention resolved in Step 0.4
(e.g. `fix/292-status-filter-options`, `feat/293-request-intake-module`).
Pick `type` from the issue's nature: `feat`, `fix`, `chore`, `refactor`,
`docs`.

Implement per the plan, using efficient-fable orchestration. Use the
commands and per-directory conventions discovered in Step 0.4
(`CLAUDE.md`/`AGENTS.md` or inferred from `package.json`/build config) — lint,
typecheck, test, build. If the tree has pre-existing lint/type errors
unrelated to your change, judge your diff by *new* errors on *changed files*
only, and say so in the PR. Follow whatever commit message convention Step
0.4 inferred, and end commits with the Co-Authored-By trailer.

Run the relevant checks before moving on; if the repo has a pre-push hook
(check `.githooks/` or `core.hooksPath` in git config) it'll typecheck/lint
anyway — failures are cheaper to catch now than at push time.

### Step 6 — Verify (GIF required for UI changes)

Decide: did this change anything a user can see or click (components, pages,
styles, client-side behavior)? If yes, this step is **mandatory**, because
the PR comment with the GIF is what tells the user "this needs your visual
sign-off".

1. Invoke the **`verify`** skill — exercise the changed flow end-to-end in
   the running app (check for a `run` skill or repo docs for how to start it
   and its local URL/basePath conventions).
2. While driving the flow in Chrome, record it with
   `mcp__claude-in-chrome__gif_creator`: start capture before the first
   action, capture extra frames before/after each step, and name the file
   after the issue (e.g. `issue-<N>-verification.gif`). Save it somewhere
   durable and note the path.
3. Take "after" screenshots of the same screens you captured in Step 3
   (`issue-<N>-after-<screen>.png`) so the PR comment can show matched
   before/after pairs.

For backend-only changes, `verify` at your judgment (run the integration
tests, exercise the endpoint), and skip the GIF.

### Step 7 — Draft pull request + board (delegated)

The main agent does exactly two things here: push the branch, and **author
the PR content** (title + body written to a file). Everything else —
creating the PR, labels, milestone, assignee, board item — goes to a
subagent so the main agent's context stays on the code.

Draft is deliberate: "In Review" on the board must mean *actually
reviewable*, so the PR stays a draft until checks pass and the visual
evidence is posted (Step 9 flips it). If a PR template was found in Step 0,
read it and fill **every** section rather than approximating from memory. If
no template exists, use this shape:

- **Description / Changes made** — from your plan + what actually happened.
- **Type of change** — feature / fix / chore / refactor / docs.
- **Relationship** — `Closes #<N>` (this is what auto-closes the issue and
  links the board items, if a board is in play).
- **Labels & checklist** — check the boxes you actually completed, right
  after you complete them below.
- **Testing** — this is the QA script. Two parts:
  - Checked boxes with the *exact commands run and their results*.
  - A **QA verification steps** list: numbered, concrete manual steps a QA
    person can follow without context.
- **Screenshots (if UI change)** — note that before/after screenshots and
  the GIF follow as a comment (Step 8) if the repo is private (attachments on
  a private repo can only be uploaded through the browser — public repos can
  usually take a direct `![]()` markdown link in the body instead).

Title follows the commit convention resolved in Step 0.4, typically
`type(#N): summary`.

The main agent also *decides* the metadata (labels mirrored from the issue,
milestone, size estimate) — deciding takes judgment, applying doesn't. Then
spawn the **PR subagent** with the body file path, the metadata values, and
the skill's script path, to run:

```bash
gh pr create --draft --title "<title>" --body-file <body.md>
gh pr edit <PR> --add-assignee <github-user> \
  --add-label <issue's labels, comma-separated> \
  --milestone "<issue's milestone, if any>"
if <board configured>; then
  PR_ITEM=$(GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh add <pr-url>)
  GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh status "$PR_ITEM" "In Progress"
  GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh priority "$PR_ITEM" <issue's P-label, if any>
  GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh size "$PR_ITEM" <XS/S/M/L/XL from main agent>
fi
```

The subagent reports back the **PR URL and `PR_ITEM` id** (if a board is
configured) — Steps 8 and 9 need both. While it runs, the main agent can
proceed with anything not blocked on the PR URL (e.g. final self-review of
the diff).

The PR's board status (if configured) starts at **In Progress** to match its
draft state; Step 9 moves it to In Review when the PR is marked ready. If
the issue has no milestone, use the open sprint/milestone whose date range
contains today (`gh api repos/<owner>/<repo>/milestones`), if the repo uses
milestones at all. Leave the **issue's** board status at In Progress — it
flips to Done automatically when the PR merges and closes it.

### Step 8 — Post the GIF + screenshots comment (UI changes only)

Check whether the repo is private (`gh repo view --json isPrivate`). If
private, raw file links won't render for other viewers — attachments must be
uploaded as real comment attachments, which only works through the browser:

1. Open the PR page in Chrome (claude-in-chrome tools).
2. In the comment box, attach the before-screenshots from Step 3, matching
   "after" screenshots or the verification GIF from Step 6, using
   `mcp__claude-in-chrome__file_upload`.
3. Comment text: label the images (Before / After / Flow recording), one or
   two sentences on what flow the GIF shows, and that the user should
   visually verify it before merging. Submit.

If the repo is public, you can instead embed the images/GIF directly in the
PR body or a `gh pr comment` markdown body via a hosted path, whichever is
simpler — the browser upload dance exists specifically to work around
private-repo attachment restrictions.

If the Chrome extension isn't available or the upload fails twice, don't
spin: post a text comment saying the verification media exists, and tell the
user the local file paths so they can drag-drop them themselves.

### Step 9 — Mark ready + Slack announcement (delegated)

The **decision** to graduate the PR from draft is the main agent's: it
happens only when checks ran clean (Step 5) and, for UI changes, the
verification media is posted (Step 8). If something is genuinely unresolved
(a check you couldn't fix, verification the user must do first), leave it as
a draft, leave the board at In Progress, and say exactly what's blocking in
the wrap-up — a premature "ready" wastes a reviewer's time and burns trust
in the board.

Once the main agent decides the PR is ready, it authors the Slack message
text (if Slack is configured — see Step 0) and spawns the **release
subagent** with the PR number, `PR_ITEM` (if any), the message, and the
channel, to execute:

1. ```bash
   gh pr ready <PR>
   # if board configured:
   GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number> <skill-dir>/scripts/board.sh status "$PR_ITEM" "In Review"
   ```
2. If Slack is configured, detect the Slack MCP via ToolSearch for `slack`
   message/post tools and post the message to the configured review channel.
3. Report back what succeeded (ready flipped? board moved? Slack posted?).

Slack is often a team's primary communication channel — a PR nobody sees is
a PR nobody reviews, so the announcement is what actually gets the work
reviewed, when Slack is in play. Two things make an announcement actually
land instead of sitting unaddressed:

- **It `@mentions` a reviewer**, if a default reviewer is configured (Step
  0). A post with no mention is easy to scroll past. Put the mention in its
  own leading line so it reads as a direct ask, not a passing reference
  buried in prose.
- **Links use Slack's link markup**, `<https://url|link text>`, never a bare
  URL. This isn't just style: a bare URL immediately followed by more text
  on the next line has been observed to get merged by the send tool into one
  broken link (`<https://.../pull/311\nCloses|...>` — the literal newline
  and the word "Closes" ended up inside the URL). Wrapping every link in
  `<url|text>` on one line avoids this and reads as a clean sentence instead
  of a dumped link. Give each link its own descriptive text so multiple
  links in one message (PR + issue) stay visually distinct.

Message format — short, scannable, written for teammates:

```
<@reviewer-slack-id> — new PR ready for your review.

:rocket: <PR URL|PR title>
Closes <issue URL|#<N>> — <one-line summary of the change>
QA steps are in the PR body. <"Includes before/after screenshots and a verification GIF in the comments." if UI>
```

If no default reviewer is configured and the user hasn't named one in this
session, post without a leading mention rather than blocking, and say so in
the wrap-up.

If no Slack MCP is connected, or Slack isn't configured for this repo, skip
the post and the main agent includes the ready-to-paste message in the
wrap-up instead, noting that connecting a Slack MCP (`claude mcp add`) and
configuring a channel would automate this step.

Only announce a PR that was actually marked ready — never a draft.

## Wrap-up report to the user

End with a terse (caveman-compliant) summary: PR URL, board status of issue +
PR (if a board is configured), checks run and their results, whether the GIF
was posted, whether Slack was notified, and anything that needs their eyes —
especially the visual verification if it was a UI change.

## Failure modes

- **Board command fails with unknown field/option** — the board's fields
  changed; re-run `gh project field-list <number> --owner <owner> --format
  json` to see current fields, `board.sh` resolves by name so this usually
  self-heals, but a genuinely renamed/removed field needs a config update.
- **No project board, no PR template, no Slack** — expected in a lot of
  repos. Skip those steps and say so in the wrap-up; this is not a failure.
- **Issue already assigned to someone else / already In Progress** — stop
  and ask the user before taking it over.
- **Plan invalidated mid-implementation** — post a short follow-up comment
  on the issue correcting the record; don't leave a stale plan as the last
  word.
- **Checks fail and the fix isn't obvious** — report honestly in the PR (or
  hold the PR and ask the user). Never check a Testing box that didn't
  actually pass.
