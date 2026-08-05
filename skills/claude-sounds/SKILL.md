---
name: claude-sounds
description: Play a different meme sound when Claude Code finishes a turn, picked by outcome (completed / needs input / failed) and scaled by how much code was written — a 1000-line turn ends in a 10-second "I GOT THIS FAAAAAHHHH". Use when the user wants audio notifications for turn endings, asks for sounds when Claude finishes, mentions install/uninstall/customizing claude-sounds, wants to know why a sound played or didn't, or wants to share this setup with someone else.
---

# claude-sounds — hear how the turn ended

A `Stop` hook that plays a sound every time Claude Code hands control back,
chosen by **how the turn ended** and **how big it was**. Small fix: a quick
vine boom. Thousand-line refactor: a ten-second scream.

The point is ambient awareness — you can walk away from a long run and know
from the next room whether it landed, died, or is waiting on you.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/guillermoscript/agent-skills/main/skills/claude-sounds/install.sh | bash
```

Then **restart Claude Code, or open `/hooks` once** — the settings watcher
does not pick up a new hook mid-session.

Requires `jq`, `curl`, and an audio player (`afplay` ships with macOS;
`mpv`, `ffplay`, `mpg123`, or `paplay` work on Linux).

Flags: `--uninstall`, `--no-sounds` (hook only, spoken fallbacks),
`--dry-run`, `--yes`.

## What plays when

Status comes from the last assistant message of the turn. The three
background-job markers are exact; everything else is a heuristic.

| Trigger | Status | Sound |
|---|---|---|
| message contains `result:` | completed | scales with size, below |
| contains `needs input:` | needs-input | hmmm |
| contains `failed:` | failed | BRUH |
| ends with `?` | needs-input | hmmm |
| contains error/failed/couldn't/blocked | failed | BRUH |
| anything else | other | taco bell bong |

**Completed scales** with lines written or edited in that turn (`Write`
content + `Edit` new_string, counted only since the last user prompt):

| Lines | Sound | Length |
|---|---|---|
| <50 | vine boom | 1.3s |
| 50+ | FAAAH | 2.0s |
| 200+ | Faaaa | 2.6s |
| 500+ | boosted FAAAH | 8.9s |
| 1000+ | **I GOT THIS FAAAAAHHHH** | 10.8s |

A failure over 200 lines gets the sad trombone instead of BRUH — a big run
that died deserves more than a one-syllable reaction.

## Files

| Path | What |
|---|---|
| `~/.claude/hooks/status-sound.sh` | the hook |
| `~/.claude/hooks/sounds/*.mp3` | audio, one file per slot |
| `~/.claude/settings.json` | `Stop` hook entry (merged, never replaced) |

## Customizing

**Swap a sound**: drop any mp3 over the slot file — no script edit.

```bash
cp ~/Downloads/my-sound.mp3 ~/.claude/hooks/sounds/done_epic.mp3
```

The installer also fetches five unused extras (`extra_metal_pipe`,
`extra_anime_wow`, `extra_sad_violin`, `extra_rizz`, `extra_aughhh`) — copy
one over a slot to use it.

**Change thresholds**: edit the `case "${STATUS}"` block in the hook.

**Mute** without uninstalling: `STATUS_SOUND_OFF=1`.

## When it does the wrong thing

**No sound at all.** Almost always the settings watcher — restart or open
`/hooks`. Then check the hook is registered and the audio exists:

```bash
jq '.hooks.Stop' ~/.claude/settings.json
ls ~/.claude/hooks/sounds/
```

**Wrong sound.** Turn on the log and read what it decided:

```bash
STATUS_SOUND_DEBUG=1   # writes ~/.claude/status-sound.log
```

Each line records the status, line count, and chosen slot. Force a specific
reaction to test one:

```bash
STATUS_SOUND_TEST_STATUS=completed STATUS_SOUND_TEST_LINES=1500 \
  sh -c 'echo "{}" | ~/.claude/hooks/status-sound.sh'
```

**Spurious BRUH.** The heuristic reads any message *mentioning* an error as a
failure, so a turn that merely discusses one triggers it. The `result:` /
`failed:` markers are the reliable path; the keyword rules are best-effort.

## Notes on the audio

Sounds are downloaded from myinstants.com **to the user's own machine at
install time** — this repo ships a URL manifest (`sounds.txt`), not audio.
They are third-party uploads of copyrighted clips: fine as personal
notification sounds, not something to redistribute.

If a URL dies the installer says so and that slot falls back to a spoken
reaction via `say`. Fix by putting any mp3 at the slot path, or by editing
the URL in `sounds.txt` and re-running.

Heads-up when adding URLs: myinstants serves a **generic fallback file for
dead slugs**, so different-looking URLs can return byte-identical audio.
Check with `md5` before assuming a new sound is distinct.
