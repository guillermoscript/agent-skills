---
name: pr-review-watch
description: Review someone else's pull request on a loop until it merges — run /code-review (plus /security-review) over the diff, submit a real GitHub review that approves or requests changes, then poll on an in-session cron so every new push gets re-reviewed incrementally and every author reply gets an answer, resolving threads once addressed and cleaning up the local checkout after the merge. Stateless — GitHub is the only state, so it resumes after a dead session. Use when the user says "review this PR", "watch PR #N for me", "keep reviewing this until it merges", "I'm the reviewer on this one", or pastes a PR URL they did not author.
---

# PR Review Watch — the reviewer's side of the loop

`pr-review-loop` shepherds **our** PR through someone else's review. This
skill is the mirror: we are the **reviewer** on someone else's PR. It runs
the actual review, submits a verdict GitHub recognizes, and keeps
re-reviewing as the author pushes fixes — until the PR merges.

The two skills never run on the same PR. Which one applies is decided by
authorship, checked before anything else (see the gate below).

Three doctrines govern everything here:

- **Stateless — GitHub is the only state.** No watermark files. Each cycle
  rebuilds its work from the PR: the head SHA versus the SHA we last
  reviewed, and our own unresolved threads where the author had the last
  word. A dead session, an expired cron, or a manual re-invoke all resume
  identically.
- **Incremental after the first pass.** The first cycle reviews the whole
  diff. Every later cycle reviews only what changed since our last review —
  re-reviewing 2,000 unchanged lines every seven minutes wastes the run and
  produces duplicate comments, which is how automated reviewers get muted.
- **A review is a permanent record with the user's name on it.** Chat may
  be terse; every comment, thread reply and review body is normal,
  professional, full-sentence English, and specific enough that the author
  can act without asking a follow-up.

Config (project board, Slack channel) comes from
`.claude/gh-workflow.config.json` via **`gh-repo-config`**; board moves go
through **`gh-board`**; local cleanup uses the shared
`pr-review-loop/scripts/cleanup.sh`.

## Invocation and arming

```
/pr-review-watch <pr-url | #N | N>
```

1. **Authorship gate.** `gh pr view <N> --json author,state,isDraft,url` and
   `gh api user -q .login`. If the PR's author **is** the authenticated
   user, this is the wrong skill — say so and point at
   `/pr-review-loop #<N>` instead of reviewing our own code. A **draft** PR
   is not ready for review: tell the user and stop, unless they explicitly
   ask to review the draft anyway.
2. **Resolve the board item once**, if a board is configured, so later steps
   don't re-discover it:

   ```bash
   export GH_PROJECT_OWNER=<owner> GH_PROJECT_NUMBER=<number>
   PR_ITEM=$(<gh-board-dir>/scripts/board.sh find <owner>/<repo> <N>)
   ```

   No board configured means every board step below is skipped silently.
3. **Run one cycle immediately** — that's the first, full review.
4. **Arm the cron.** Check `CronList` first — one cron per PR, never two,
   and never a `pr-review-watch` cron on a PR that already has a
   `pr-review-loop` cron. If absent, `CronCreate` on a ~7-minute off-minute
   schedule (e.g. `*/7 * * * *`) with the prompt:
   `Run one pr-review-watch cycle for PR #<N> in <owner>/<repo> (skill: pr-review-watch).`
5. **Tell the user the cron's lifespan**: session-scoped, expires after 7
   days. If the session ends first, `/pr-review-watch #<N>` catches up and
   re-arms — the designed resume path, not a failure.

## One cycle

### 1. State gate

```bash
gh pr view <N> --json state,mergedAt,headRefOid,isDraft,url,title
```

- `MERGED` → disarm the cron, run the close-out and cleanup below.
- `CLOSED` unmerged → disarm, tell the user, stop. Nothing to review, and
  it isn't our PR to reopen.
- Converted back to **draft** → the author is reworking it. Skip the cycle
  silently and leave the cron armed; a draft gets no review comments.

### 2. Find the review baseline — stateless

The baseline is the commit we last reviewed. Read it from our own review
history, not from a local file:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews \
  --jq '[.[] | select(.user.login=="<me>")] | last | {sha: .commit_id, state, submitted_at}'
```

- **No prior review of ours** → baseline is the merge base; this is the
  first, full pass: `gh pr diff <N>`.
- **Prior review exists** → baseline is its `commit_id`. The incremental
  diff is what to review:

  ```bash
  git fetch -q origin
  git diff <baseline-sha>..<headRefOid>
  ```

  If `headRefOid` equals the baseline SHA, **no new code since our last
  review**. Skip straight to step 5 (author replies) — do not re-review.

A force-push can make the baseline SHA unreachable (`git cat-file -e
<sha>^{commit}` fails). Don't guess at a range: fall back to a full-diff
pass and say in the review body that the branch was force-pushed, so the
author understands why the whole thing is being re-reviewed.

### 3. Review the diff

Get the PR branch available locally — this is the only checkout this skill
makes, and it's the only thing it will clean up later:

```bash
gh pr checkout <N>   # or: git fetch origin pull/<N>/head
```

If the user's tree is dirty, don't stomp it — review from `gh pr diff`
instead and note in the wrap-up that repo checks weren't run locally.

Then run both built-in reviews over the diff in scope (full on the first
cycle, incremental after):

- **`/code-review`** — correctness, simplification, efficiency, test
  coverage. It reports via `ReportFindings` with verdicts; keep only
  findings that survive verification.
- **`/security-review`** — the security pass. Its findings carry more weight
  in the verdict below: a confirmed vulnerability is a blocker even when the
  code is otherwise clean.

Run the repo's own checks too when the branch is checked out (lint,
typecheck, test — per `gh-repo-config` discovery). A failing test we can
reproduce locally is a legitimate review finding; a failing check in CI is
the author's business, not a review comment (see the verdict rules).

Judge each finding before it becomes a comment. Three filters, in order:

- **Is it in scope?** A pre-existing problem the diff merely sits next to is
  not this PR's job. Mention at most one, in the review body, as a
  non-blocking note — never as a change request.
- **Is it real?** Drop anything that didn't survive verification. A confident
  wrong comment costs the author more time than saying nothing.
- **Is it worth the author's attention?** Style a formatter or linter would
  catch isn't a review comment. Taste dressed as correctness isn't either;
  if it's a preference, say so in the body and don't block on it.

### 4. Submit a real GitHub review

One review per cycle, with inline comments attached to lines — not a pile of
loose conversation comments. Build the payload and submit it in one call so
the author gets one notification:

```bash
cat > review-pr-<N>-cycle.json <<'JSON'
{
  "commit_id": "<headRefOid>",
  "body": "<the review body>",
  "event": "REQUEST_CHANGES",
  "comments": [
    {"path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "..."}
  ]
}
JSON
gh api repos/<owner>/<repo>/pulls/<N>/reviews --input review-pr-<N>-cycle.json
```

Inline comments must land on lines **present in the diff** — a comment on an
untouched line is rejected and takes the whole review with it. If a
submission fails on position, retry that comment as a file-level comment
(omit `line`, keep `path`) or move it into the body rather than dropping the
finding silently.

**The verdict:**

- **`REQUEST_CHANGES`** — at least one confirmed blocking finding: a
  correctness bug, a confirmed security finding, a test that fails on the
  branch, or a change that contradicts the linked issue's intent.
- **`APPROVE`** — no blocking findings. Approve on **code quality alone**:
  CI status is deliberately *not* a gate here. Red checks are the author's
  to fix and the merge itself is gated on them; holding an approval hostage
  to someone else's flaky pipeline just stalls the PR. Do mention a red
  build in the body as a heads-up, then approve anyway.
- **`COMMENT`** — only when nothing blocks but a question genuinely needs an
  answer before an approval would mean anything. Prefer approving with notes
  over parking the PR in `COMMENT` forever.

Both verdicts submit automatically — that is the point of a loop. The review
body is a short paragraph: what the change does, what was reviewed this
cycle (full or "the three commits pushed since my last review"), the verdict
and why, plus any non-blocking notes. On an approval, keep it to two or
three sentences; on a change request, list the blockers so the author can
work top-down.

**Never approve our own PR** — the authorship gate already stopped that, but
if a cycle ever finds the authenticated user is the author, disarm and stop.

### 5. Answer the author on our own threads

Our unresolved threads where the author had the last word are pending work.
Same GraphQL query as `pr-review-loop`, filtered to threads we started:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            id isResolved
            comments(first:50) { nodes { databaseId author{login} body path line url createdAt } }
          }
        }
      }
    }
  }' -F owner=<owner> -F repo=<repo> -F pr=<N>
```

For each such thread, read the author's reply and decide:

- **They fixed it** — verify the fix in the current code, not just the
  claim. Then reply confirming, and **resolve the thread**. Resolving is the
  reviewer's job (this is the inverse of `pr-review-loop`, which never
  resolves) — an addressed thread left open is what makes a PR look
  perpetually unfinished.

  ```bash
  gh api graphql -f query='mutation($t:ID!){ resolveReviewThread(input:{threadId:$t}){ thread { isResolved } } }' -F t=<thread-id>
  ```

- **They pushed back and they're right** — say so plainly, drop the point,
  resolve the thread. Being wrong in public and correcting fast is cheaper
  than defending a bad comment.
- **They pushed back and the point stands** — reply with the reasoning, or
  concrete failing input. Leave it unresolved.
- **They asked a question** — answer it. Leave it unresolved until the
  underlying point is actually settled.

Replies go on the thread, not as new top-level comments:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment-id>/replies -f body='...'
```

**Nothing new to review and no pending replies → end the cycle silently.** A
quiet poll is the normal case; don't narrate it.

### 6. Keep the board honest

The board should say who owes the next move, and a PR under review swings
between the two:

- **We requested changes** (author owes work) → `Changes Requested` if the
  board has that option, else leave the item where it is.
- **We approved** → `Approved` if the board has it, else `In Review`.

Read before writing — re-setting the same status every seven minutes is
noise in the activity feed:

```bash
CUR=$(<gh-board-dir>/scripts/board.sh get-field "$PR_ITEM" Status)
[ "$CUR" = "<state>" ] || <gh-board-dir>/scripts/board.sh status "$PR_ITEM" "<state>"
```

Learn the board's real option names once per run (`field-list` in
`gh-board`) rather than guessing. An unknown option warns and exits 0, so a
wrong guess is a no-op — but it also means the board quietly stops
reflecting reality, so check the names.

**Never merge.** Approving is the reviewer's authority; merging is the
author's call (or their `pr-review-loop`'s). Even with permission to push
the button, don't — an approval the author didn't expect to merge instantly
is how reviewers lose trust.

## After the merge — close-out, cleanup, disarm

The author's side posts the "what shipped" record; the reviewer's close-out
is smaller and different in kind. In order:

1. **Final review comment**, only if it adds something the thread doesn't
   already say: confirmation the merged state matches what was approved, or
   any non-blocking follow-up worth an issue. If the last review already
   said it, skip this — a redundant "LGTM, merged!" is noise on a permanent
   record.
2. **Cleanup — only what this skill created.** The author's branch and the
   user's other work are off-limits. Use the shared script:

   ```bash
   <pr-review-loop-dir>/scripts/cleanup.sh all <pr-branch> [worktree-path]
   ```

   Every deletion in it is guarded (uncommitted changes, stashes, unpushed
   commits, and a squash-merge–aware patch check). A guard that trips prints
   `SKIPPED: <reason>` and exits 0 — that is a **result to report to the
   user, not an error to retry**. If we never checked the branch out
   (reviewed from `gh pr diff`), there is nothing to clean up; run
   `cleanup.sh main` alone to return to an up-to-date default branch.
3. **Scratch artifacts** — drop this PR's review payloads:

   ```bash
   <pr-review-loop-dir>/scripts/cleanup.sh scratch <scratchpad-dir> 'review-pr-<N>-*.json'
   ```

4. **Disarm the cron** (`CronDelete`).
5. **Terse wrap-up**: verdict history (how many cycles, how many change
   requests before the approval), findings raised versus confirmed, threads
   resolved, what cleanup did — including anything a guard held back and why
   — and the board status.

## Division of labor

Same doctrine as the rest of the chain (see `work-issue`): the main agent
performs the review itself and authors every comment — that's judgment work
and cannot be delegated. Subagents do GitHub mechanics (submitting the
built review payload, fetching comment dumps, resolving threads). Delegated
prompts mark every noun as *given* or *to-produce* ("this file already
exists and is final — do NOT create, edit, or overwrite it"), authored files
get unique names (`review-pr-<N>-cycle-<sha>.json`), and after a subagent
posts anything, fetch what was actually published and compare it against
what you authored — exit codes lie, content doesn't.

## Failure modes

- **PR is ours** — wrong skill; point at `/pr-review-loop #<N>` and stop.
- **PR is a draft** — not reviewable; stop unless the user insists.
- **Force-push invalidated the baseline** — fall back to a full re-review
  and say why in the review body.
- **Inline comment position rejected** — retry as a file-level comment or
  move the point into the review body; never drop the finding silently.
- **Author disagrees and is right** — concede on the thread, resolve it,
  move on. Don't defend a bad comment across cycles.
- **Nothing new for many cycles** — the PR is waiting on the author, not on
  us. Stay quiet and keep polling; don't manufacture comments to look busy.
- **A cleanup guard trips** — expected and correct. Report which one and
  what it protected; never force past it.
- **Board lacks `Changes Requested` / `Approved`** — expected on simpler
  boards; fall back to `In Review` or leave the item alone. `set-field`
  warns and exits 0, so this never breaks a cycle.
