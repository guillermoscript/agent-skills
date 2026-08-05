#!/usr/bin/env bash
# claude-sounds — Stop hook that announces how each turn ended with a meme
# sound, scaled by how much work actually happened.
#
# Claude Code pipes the Stop event to stdin as JSON:
#   { "session_id": "...", "cwd": "...", "transcript_path": "...", ... }
# We read the last assistant text to classify status, and count the lines
# written/edited in that turn to size the reaction.
#
# STATUS (first match wins):
#   1. `result:`      -> completed     (background-job marker)
#   2. `needs input:` -> needs-input   (background-job marker)
#   3. `failed:`      -> failed        (background-job marker)
#   4. ends with '?'  -> needs-input   (heuristic)
#   5. error keywords -> failed        (heuristic)
#   6. otherwise      -> other
#
# MAGNITUDE (completed only) — lines written/edited this turn:
#   <50 tiny | 50+ small | 200+ medium | 500+ big | 1000+ epic
#
# Always exits 0 and never blocks; playback is detached so a long sound
# never delays the next prompt.
#
#   Mute:  STATUS_SOUND_OFF=1
#   Debug: STATUS_SOUND_DEBUG=1   -> ~/.claude/status-sound.log
#   Test:  STATUS_SOUND_TEST_STATUS=completed STATUS_SOUND_TEST_LINES=1500

set +e

[ "${STATUS_SOUND_OFF:-}" = "1" ] && exit 0

SOUND_DIR="${STATUS_SOUND_DIR:-${HOME}/.claude/hooks/sounds}"

PAYLOAD="$(cat 2>/dev/null || true)"

TRANSCRIPT=""
if [ -n "${PAYLOAD}" ] && command -v jq >/dev/null 2>&1; then
  TRANSCRIPT="$(printf '%s' "${PAYLOAD}" | jq -r '.transcript_path // empty' 2>/dev/null)"
fi

# ---------------------------------------------------------------- classify ---
LAST_MSG=""
if [ -n "${TRANSCRIPT}" ] && [ -r "${TRANSCRIPT}" ] && command -v jq >/dev/null 2>&1; then
  LAST_MSG="$(jq -r 'select(.type=="assistant")
      | .message.content[]?
      | select(.type=="text")
      | .text' "${TRANSCRIPT}" 2>/dev/null \
    | grep -v '^[[:space:]]*$' \
    | tail -40)"
fi

# macOS ships bash 3.2, so no ${x,,}.
LOWER="$(printf '%s' "${LAST_MSG}" | tr '[:upper:]' '[:lower:]')"
LAST_LINE="$(printf '%s' "${LAST_MSG}" | tail -1 | sed 's/[[:space:]]*$//')"

STATUS="other"
if printf '%s' "${LOWER}" | grep -qE '(^|[[:space:]])result:'; then
  STATUS="completed"
elif printf '%s' "${LOWER}" | grep -qE '(^|[[:space:]])needs input:'; then
  STATUS="needs-input"
elif printf '%s' "${LOWER}" | grep -qE '(^|[[:space:]])failed:'; then
  STATUS="failed"
elif printf '%s' "${LAST_LINE}" | grep -q '?$'; then
  STATUS="needs-input"
elif printf '%s' "${LOWER}" | grep -qE "error|failed|couldn't|could not|unable to|blocked"; then
  STATUS="failed"
fi

# ---------------------------------------------------------------- magnitude ---
# Lines written/edited since the last user prompt = the size of THIS turn.
LINES=0
if [ -n "${TRANSCRIPT}" ] && [ -r "${TRANSCRIPT}" ] && command -v jq >/dev/null 2>&1; then
  REVERSED="$(tac "${TRANSCRIPT}" 2>/dev/null || tail -r "${TRANSCRIPT}" 2>/dev/null)"
  LINES="$(printf '%s\n' "${REVERSED}" \
    | jq -rs '
        (map(select(.type=="user" or .type=="assistant"))
         | (map(.type=="user") | index(true)) // length) as $stop
        | .[0:$stop]
        | map(.message.content[]? // empty
              | select(.type=="tool_use")
              | if   .name=="Write" then (.input.content    // "")
                elif .name=="Edit"  then (.input.new_string // "")
                else "" end
              | split("\n") | length)
        | add // 0' 2>/dev/null)"
fi
case "${LINES}" in ''|*[!0-9]*) LINES=0 ;; esac

# Test overrides
[ -n "${STATUS_SOUND_TEST_STATUS:-}" ] && STATUS="${STATUS_SOUND_TEST_STATUS}"
[ -n "${STATUS_SOUND_TEST_LINES:-}" ]  && LINES="${STATUS_SOUND_TEST_LINES}"

# ------------------------------------------------------------------ react ---
case "${STATUS}" in
  completed)
    if   [ "${LINES}" -ge 1000 ]; then PICK="done_epic";   LABEL="I got this faaaaahhh"
    elif [ "${LINES}" -ge 500 ];  then PICK="done_big";    LABEL="faaaaaaaaaaaa"
    elif [ "${LINES}" -ge 200 ];  then PICK="done_medium"; LABEL="faaaaaaa"
    elif [ "${LINES}" -ge 50 ];   then PICK="done_small";  LABEL="faaaa"
    else                               PICK="done_tiny";   LABEL="yep"
    fi
    ;;
  needs-input) PICK="needs_input"; LABEL="hmmm" ;;
  failed)
    if [ "${LINES}" -ge 200 ]; then PICK="failed_big"; LABEL="wah wah wah"
    else                            PICK="failed";     LABEL="bruh"
    fi
    ;;
  *)           PICK="other";       LABEL="ok" ;;
esac

SOUND="${SOUND_DIR}/${PICK}.mp3"

if [ "${STATUS_SOUND_DEBUG:-}" = "1" ]; then
  printf '%s status=%-12s lines=%-6s sound=%-12s (%s)\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${STATUS}" "${LINES}" "${PICK}" "${LABEL}" \
    >> "${HOME}/.claude/status-sound.log"
fi

# Detach playback so a long sound never delays the session.
play() {
  if   command -v afplay      >/dev/null 2>&1; then afplay "$1"
  elif command -v mpv         >/dev/null 2>&1; then mpv --no-video --really-quiet "$1"
  elif command -v ffplay      >/dev/null 2>&1; then ffplay -nodisp -autoexit -loglevel quiet "$1"
  elif command -v mpg123      >/dev/null 2>&1; then mpg123 -q "$1"
  elif command -v paplay      >/dev/null 2>&1; then paplay "$1"
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -c "(New-Object Media.SoundPlayer '$1').PlaySync()"
  else return 1; fi
}

if [ -r "${SOUND}" ]; then
  ( play "${SOUND}" >/dev/null 2>&1 & ) >/dev/null 2>&1
elif command -v say >/dev/null 2>&1; then
  # Sound library missing — fall back to a spoken reaction.
  ( say -v Boing "${LABEL}" >/dev/null 2>&1 & ) >/dev/null 2>&1
fi

exit 0
