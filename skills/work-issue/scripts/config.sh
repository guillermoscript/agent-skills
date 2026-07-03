#!/usr/bin/env bash
# Reads/writes the per-repo work-issue config: <repo-root>/.claude/work-issue.config.json
# Repo root is discovered via `git rev-parse --show-toplevel` from the cwd.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  config.sh path                 Print the config file path for the current repo (may not exist)
  config.sh read                 Print the config JSON, or "{}" if none exists
  config.sh get <jq-path>        Print one value, e.g. config.sh get .projectBoard.number
  config.sh init                 Create .claude/ dir + empty config if missing
EOF
  exit 1
}

_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || { echo "not a git repo" >&2; exit 1; }
}

_config_path() {
  echo "$(_repo_root)/.claude/work-issue.config.json"
}

cmd="${1:-}"
[ $# -ge 1 ] && shift
case "$cmd" in
  path)
    _config_path
    ;;
  read)
    p="$(_config_path)"
    [ -f "$p" ] && cat "$p" || echo "{}"
    ;;
  get)
    [ $# -eq 1 ] || usage
    p="$(_config_path)"
    if [ -f "$p" ]; then
      jq -r "$1 // empty" "$p"
    fi
    ;;
  init)
    p="$(_config_path)"
    mkdir -p "$(dirname "$p")"
    [ -f "$p" ] || echo '{}' > "$p"
    echo "$p"
    ;;
  *) usage ;;
esac
