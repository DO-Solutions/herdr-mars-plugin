# shellcheck shell=bash
# Shared helpers: logging, JSON access, invocation context, plugin state.

MARS_PLUGIN_ID="${HERDR_PLUGIN_ID:-digitalocean.mars}"
export MARS_PLUGIN_ID

mars_log() {
  printf 'mars: %s\n' "$*" >&2
}

mars_die() {
  mars_log "$@"
  exit 1
}

mars_have() {
  command -v "$1" >/dev/null 2>&1
}

mars_require_jq() {
  mars_have jq || mars_die "jq is required. Install it and try again."
}

# mars_json_get <key> <json>
mars_json_get() {
  local key="$1" json="${2:-}"
  [[ -n "$json" ]] || return 0
  jq -r --arg k "$key" '.[$k] // empty' <<<"$json" 2>/dev/null || true
}

# Field from HERDR_PLUGIN_CONTEXT_JSON (focused_pane_id, focused_pane_cwd, selected_text, ...).
mars_ctx() {
  mars_json_get "$1" "${HERDR_PLUGIN_CONTEXT_JSON:-}"
}

# Pane the plugin should split next to. Popup processes do not get HERDR_PANE_ID,
# so actions forward the focused pane through MARS_TARGET_PANE.
mars_target_pane() {
  local pane="${MARS_TARGET_PANE:-}"
  [[ -n "$pane" ]] || pane="$(mars_ctx focused_pane_id)"
  [[ -n "$pane" ]] || pane="${HERDR_PANE_ID:-}"
  printf '%s\n' "$pane"
}

# Working directory the user is looking at.
mars_cwd() {
  local cwd="${MARS_CWD:-}"
  [[ -n "$cwd" ]] || cwd="$(mars_ctx focused_pane_cwd)"
  [[ -n "$cwd" ]] || cwd="$(mars_ctx workspace_cwd)"
  [[ -n "$cwd" && -d "$cwd" ]] || cwd="$PWD"
  printf '%s\n' "$cwd"
}

mars_state_dir() {
  local dir="${HERDR_PLUGIN_STATE_DIR:-}"
  if [[ -z "$dir" ]]; then
    dir="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-mars-plugin"
  fi
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

mars_config_dir() {
  local dir="${HERDR_PLUGIN_CONFIG_DIR:-}"
  if [[ -z "$dir" ]]; then
    dir="${XDG_CONFIG_HOME:-$HOME/.config}/herdr-mars-plugin"
  fi
  printf '%s\n' "$dir"
}

# Small key/value memory for defaults (last spec, last session).
mars_remember() {
  local key="$1" value="$2"
  printf '%s\n' "$value" >"$(mars_state_dir)/$key"
}

mars_recall() {
  local file
  file="$(mars_state_dir)/$1"
  if [[ -f "$file" ]]; then
    head -n 1 "$file"
  fi
}

# Herdr agent names must match [a-z][a-z0-9_-]{0,31}.
mars_agent_name() {
  local raw="$1" prefix="${MARS_AGENT_NAME_PREFIX:-mars}" name
  name="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//')"
  name="${prefix}-${name}"
  name="${name:0:32}"
  name="${name%-}"
  printf '%s\n' "$name"
}

mars_relpath() {
  local path="$1" base="$2" tilde='~'
  case "$path" in
    "$base"/*) printf '%s\n' "${path#"$base"/}" ;;
    "$HOME"/*) printf '%s/%s\n' "$tilde" "${path#"$HOME"/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}
