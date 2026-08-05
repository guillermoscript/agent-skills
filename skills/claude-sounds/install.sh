#!/usr/bin/env bash
# claude-sounds installer — meme sounds for Claude Code turn endings.
#
#   curl -fsSL https://raw.githubusercontent.com/guillermoscript/agent-skills/main/skills/claude-sounds/install.sh | bash
#
# Flags:
#   --uninstall   remove the hook and sounds, restore settings
#   --no-sounds   install the hook but skip downloading audio (uses `say`)
#   --dry-run     show what would change, touch nothing
#   --yes         don't prompt
#
# Installs to:
#   ~/.claude/hooks/status-sound.sh    the hook
#   ~/.claude/hooks/sounds/*.mp3       the audio
#   ~/.claude/settings.json            a Stop hook entry (merged, not replaced)

set -uo pipefail

REPO_RAW="${CLAUDE_SOUNDS_RAW:-https://raw.githubusercontent.com/guillermoscript/agent-skills/main/skills/claude-sounds}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
HOOK_DIR="${CLAUDE_DIR}/hooks"
SOUND_DIR="${HOOK_DIR}/sounds"
HOOK_PATH="${HOOK_DIR}/status-sound.sh"
SETTINGS="${CLAUDE_DIR}/settings.json"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

DO_UNINSTALL=0; DO_SOUNDS=1; DRY_RUN=0; ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) DO_UNINSTALL=1 ;;
    --no-sounds) DO_SOUNDS=0 ;;
    --dry-run)   DRY_RUN=1 ;;
    --yes|-y)    ASSUME_YES=1 ;;
    --help|-h)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

say_step() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
say_ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$1"; }
say_warn() { printf '\033[1;33m  !!\033[0m %s\n' "$1"; }
say_err()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; }

# ------------------------------------------------------------- prerequisites --
command -v jq >/dev/null 2>&1 || {
  say_err "jq is required but not installed."
  echo "  macOS:  brew install jq"
  echo "  Debian: sudo apt install jq"
  exit 1
}
command -v curl >/dev/null 2>&1 || { say_err "curl is required."; exit 1; }

# A player is needed for real audio; without one we degrade to `say`.
PLAYER=""
for p in afplay mpv ffplay mpg123 paplay; do
  command -v "$p" >/dev/null 2>&1 && { PLAYER="$p"; break; }
done

# ----------------------------------------------------------------- uninstall --
if [ "$DO_UNINSTALL" = "1" ]; then
  say_step "Uninstalling claude-sounds"
  if [ -f "$SETTINGS" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      say_ok "[dry-run] would remove the Stop hook entry from $SETTINGS"
    else
      cp "$SETTINGS" "${SETTINGS}.bak.$(date +%s)"
      tmp=$(mktemp)
      # Drop our hook, then drop any Stop group left with no hooks.
      jq '(.hooks.Stop // []) |= (map(.hooks |= map(select((.command // "") | test("status-sound") | not)))
            | map(select((.hooks | length) > 0)))
          | if (.hooks.Stop // []) == [] then del(.hooks.Stop) else . end' \
         "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      say_ok "removed hook entry (backup saved)"
    fi
  fi
  if [ "$DRY_RUN" = "1" ]; then
    say_ok "[dry-run] would delete $HOOK_PATH and $SOUND_DIR"
  else
    rm -f "$HOOK_PATH"; rm -rf "$SOUND_DIR"
    say_ok "removed hook and sounds"
  fi
  echo; say_step "Done. Restart Claude Code (or open /hooks) to apply."
  exit 0
fi

# -------------------------------------------------------------------- install --
echo
echo "  claude-sounds — meme sounds for Claude Code"
echo "  Plays a different sound depending on how each turn ended,"
echo "  scaled by how much code was written."
echo

[ "$DRY_RUN" = "1" ] && say_warn "dry-run: nothing will be written"

if [ "$ASSUME_YES" != "1" ] && [ "$DRY_RUN" != "1" ] && [ -t 0 ]; then
  printf "Install to %s? [Y/n] " "$CLAUDE_DIR"
  read -r reply </dev/tty || reply=y
  case "$reply" in [nN]*) echo "aborted."; exit 0 ;; esac
fi

# 1. hook script
say_step "Installing hook"
if [ "$DRY_RUN" = "1" ]; then
  say_ok "[dry-run] would write $HOOK_PATH"
else
  mkdir -p "$HOOK_DIR"
  if [ -f "${SCRIPT_SRC:-}" ]; then
    cp "$SCRIPT_SRC" "$HOOK_PATH"
  else
    curl -fsSL "${REPO_RAW}/status-sound.sh" -o "$HOOK_PATH" || {
      say_err "could not download status-sound.sh"; exit 1; }
  fi
  chmod +x "$HOOK_PATH"
  say_ok "$HOOK_PATH"
fi

# 2. sounds
if [ "$DO_SOUNDS" = "1" ]; then
  say_step "Downloading sounds"
  if [ "$DRY_RUN" = "1" ]; then
    say_ok "[dry-run] would download sounds to $SOUND_DIR"
  else
    mkdir -p "$SOUND_DIR"
    manifest=$(mktemp)
    if [ -f "${MANIFEST_SRC:-}" ]; then cp "$MANIFEST_SRC" "$manifest"
    else curl -fsSL "${REPO_RAW}/sounds.txt" -o "$manifest" || {
      say_err "could not download sounds.txt"; exit 1; }
    fi

    got=0; missed=0
    while read -r slot url; do
      case "$slot" in ''|\#*) continue ;; esac
      [ -z "${url:-}" ] && continue
      if curl -fsSL -A "$UA" -e "https://www.myinstants.com/" --max-time 30 \
           "$url" -o "${SOUND_DIR}/${slot}.mp3" 2>/dev/null \
         && [ -s "${SOUND_DIR}/${slot}.mp3" ]; then
        got=$((got+1))
      else
        rm -f "${SOUND_DIR}/${slot}.mp3"; missed=$((missed+1))
        say_warn "could not fetch ${slot} — will fall back to a spoken sound"
      fi
    done < "$manifest"
    rm -f "$manifest"
    say_ok "${got} sounds in ${SOUND_DIR}"
    [ "$missed" -gt 0 ] && say_warn "${missed} unavailable (source may have removed them)"
  fi
else
  say_step "Skipping sounds (--no-sounds); the hook will use spoken fallbacks"
fi

# 3. settings.json — merge, never clobber
say_step "Wiring the Stop hook"
if [ "$DRY_RUN" = "1" ]; then
  say_ok "[dry-run] would add a Stop hook entry to $SETTINGS"
else
  mkdir -p "$CLAUDE_DIR"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

  if ! jq empty "$SETTINGS" 2>/dev/null; then
    say_err "$SETTINGS is not valid JSON — fix it first, nothing was changed."
    exit 1
  fi

  cp "$SETTINGS" "${SETTINGS}.bak.$(date +%s)"
  tmp=$(mktemp)
  # Remove any prior copy of our hook, then append a fresh entry. Existing
  # unrelated Stop hooks are preserved.
  jq --arg cmd "$HOOK_PATH" '
      .hooks //= {}
    | .hooks.Stop //= []
    | .hooks.Stop |= (map(.hooks |= map(select((.command // "") | test("status-sound") | not)))
                      | map(select((.hooks | length) > 0)))
    | .hooks.Stop += [{ matcher: "", hooks: [{ type: "command", command: $cmd, async: true }] }]
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

  if jq -e --arg c "$HOOK_PATH" '.hooks.Stop[].hooks[] | select(.command == $c)' \
       "$SETTINGS" >/dev/null 2>&1; then
    say_ok "hook registered in $SETTINGS (backup saved)"
  else
    say_err "failed to register the hook; your backup is beside $SETTINGS"
    exit 1
  fi
fi

# 4. demo
if [ "$DRY_RUN" != "1" ] && [ "$DO_SOUNDS" = "1" ] && [ -n "$PLAYER" ] \
   && [ -r "${SOUND_DIR}/done_epic.mp3" ]; then
  say_step "Preview: what a 1000+ line turn sounds like"
  ( STATUS_SOUND_TEST_STATUS=completed STATUS_SOUND_TEST_LINES=1500 \
    sh -c "echo '{}' | '$HOOK_PATH'" ) >/dev/null 2>&1
fi

echo
say_step "Installed."
[ -z "$PLAYER" ] && say_warn "no audio player found (afplay/mpv/ffplay/mpg123/paplay) — install one for real audio"
cat <<EOF

  Sounds by status:
    completed  <50 lines   vine boom
               50+         FAAAH
               200+        Faaaa
               500+        boosted FAAAH
               1000+       I GOT THIS FAAAAAHHHH   (10.8s)
    needs input            hmmm
    failed                 BRUH  (sad trombone for big ones)

  Restart Claude Code (or open /hooks once) to activate.

  Customize:  swap any file in ${SOUND_DIR}
  Mute:       STATUS_SOUND_OFF=1
  Uninstall:  curl -fsSL ${REPO_RAW}/install.sh | bash -s -- --uninstall

EOF
