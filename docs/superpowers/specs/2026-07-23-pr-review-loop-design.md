# pr-review-loop — design spec

**Date:** 2026-07-23
**Status:** Approved by user (brainstorming session)

## Purpose

Close the last gap in the GitHub-workflow skill chain: after `ship-pr`
announces a PR, nothing watches it. `pr-review-loop` polls the PR for
reviewer feedback, addresses each comment with code or an answer, iterates
until the PR is approved, then merges it and triggers the existing
`ship-pr` close-out (final PR comment + issue comment). The loop is fully
autonomous through the merge — the user chose auto-merge on approval.

## Decisions made during brainstorming

1. **Polling home:** in-session cron (`CronCreate`), designed to be
   resumable — re-invoking the skill after a dead session or cron expiry
   catches up and re-arms. No cloud routine.
2. **Loop inputs:** inline review comments and top-level conversation
   comments. **Not** CI failures — red checks are reported to the user,
   never auto-fixed by the loop.
3. **Merge gate:** auto-merge on approval (no user confirmation), provided
   the queue is empty and checks are green.
4. **Structure:** new standalone skill (Approach 1), **stateless — GitHub
   is the only state**. No watermark file. Rejected: local watermark file
   (stale/lost state risk), growing `ship-pr` (already the largest skill,
   different lifecycle phase).
5. **Judgment calls (approved):** the loop never resolves review threads
   itself (the reviewer resolves; "handled" = last word is ours, not
   "resolved"), and on merge it posts a one-line "merged" follow-up to the
   configured Slack channel.

## Place in the chain

- New skill: `skills/pr-review-loop/SKILL.md`.
- `work-issue` gains a final pipeline step after ship-pr's announcement:
  arm the review loop. Companion table, pipeline diagram, and wrap-up
  report updated.
- `ship-pr` keeps ownership of close-out; `pr-review-loop` invokes it
  after merging. `ship-pr`'s announce step gets a one-line pointer to the
  loop.
- Config (Slack channel, reviewer, board) via `gh-repo-config`; board via
  `gh-board` (no board action needed at merge — automation flips items to
  Done, per ship-pr).
- `README.md` gains a `pr-review-loop` section and updated composition
  blurb (six companions, not five).

## Invocation

```
/pr-review-loop <pr-url | #N | N>
/pr-review-loop            # resolves PR from the current branch via gh pr view
```

On start:

1. Resolve repo + PR; verify the PR is open and ours to shepherd.
2. Run one cycle immediately (catch up on anything already posted).
3. Check `CronList`; if no cron for this PR exists, create one
   (`CronCreate`, roughly every 7 minutes on an off-minute), prompt:
   "run one pr-review-loop cycle for PR #N in <owner>/<repo>".
4. Tell the user: cron is session-only (dies with the session, expires
   after 7 days) and re-invoking the skill resumes seamlessly.

Only one cron per PR — check before arming.

## One polling cycle (the core algorithm)

1. **PR state.** `gh pr view --json state,reviewDecision,mergeStateStatus,
   headRefName,...`. If merged by someone else → disarm cron, run
   close-out. If closed unmerged → disarm, report to user.
2. **Build the work queue from GitHub alone.** "Ours" = authenticated
   `gh api user -q .login`; the loop never reacts to its own comments.
   - Unresolved review threads whose last comment is not ours (GraphQL
     `pullRequest.reviewThreads` → `isResolved`, comment authors).
   - Conversation (issue-style) comments newer than our last activity
     (last push or last comment by us) and not authored by us.
   - `CHANGES_REQUESTED` review bodies not yet answered by us.
3. **Empty queue, not approved** → end cycle silently. No user noise.
4. **Classify each item:** *question* → answer on the thread, no code;
   *change request* → implement; *ambiguous / contradicts issue intent /
   scope expansion* → reply asking clarification and surface to the user
   in-session; never guess large changes.
5. **Implement** on the PR branch: main agent writes the code, runs the
   repo's checks (conventions from `gh-repo-config` step-0 facts), commits
   per convention with the Co-Authored-By trailer, pushes.
6. **Reply to every handled thread** with what changed and the commit SHA
   (inline-thread replies via `gh api`; conversation replies via
   `gh pr comment`). Never resolve threads.
7. **Approval check:** `reviewDecision == APPROVED` AND queue empty AND
   checks green (`gh pr checks`). Red checks → hold and report to user
   (CI fixing is out of scope). Otherwise merge (see below).

## Merge and close-out

- Merge method read from repo settings (`gh repo view --json
  squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed`); prefer
  squash when allowed. Use `--delete-branch`.
- Merge conflict with base: attempt a clean update (merge/rebase the base
  branch); if conflicts need judgment, escalate to the user instead.
- After merge: invoke `ship-pr` close-out (final "what shipped" PR
  comment + short issue comment), disarm the cron (`CronDelete`), post a
  one-line "merged" follow-up to the configured Slack channel (skip
  silently if no Slack), then give the user a terse wrap-up.

## Division of labor and tone

Same doctrine as the chain: the main agent authors all content (replies,
code, Slack line) and judges classifications; subagents perform GitHub
mechanics with the delegation guardrail — mark every noun (given vs
to-produce), verify posted content against authored content (not exit
codes), uniquely-named authored files. Caveman tone applies to chat only;
everything on GitHub/Slack is professional full-sentence English.

## Failure modes

- **PR closed without merge** → disarm, report.
- **Cron expired (7 days) or session died** → re-invoke to resume; the
  stateless queue rebuild makes catch-up identical to a normal cycle.
- **Reviewer pushes back on a fix** → it is simply a new unresolved
  thread; the loop iterates.
- **Red checks at merge time** → hold, report to user; never auto-fix CI.
- **Ambiguous feedback** → clarify on-thread + surface to user; the item
  stays in the queue until the reviewer replies (their reply makes the
  last word theirs again).

## Files touched

| File | Change |
|---|---|
| `skills/pr-review-loop/SKILL.md` | New skill |
| `skills/work-issue/SKILL.md` | Companion table row, pipeline step, wrap-up mention |
| `skills/ship-pr/SKILL.md` | One-line pointer from announce step to the loop |
| `README.md` | New section + composition blurb update |

## Testing

Skills are markdown; verification is a dry-run walkthrough of the cycle
algorithm against a real PR's API responses (`gh pr view`, GraphQL
`reviewThreads`) plus a review pass for consistency with the chain's
existing rules (delegation guardrail, ready gate, close-out ownership).
