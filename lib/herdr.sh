# shellcheck shell=bash
# Calls back into Herdr through HERDR_BIN_PATH (the documented plugin API).

herdr_cmd() {
  "${HERDR_BIN_PATH:-herdr}" "$@"
}

# herdr_notify <title> [body] [sound]
herdr_notify() {
  mars_flag_on "${MARS_NOTIFY:-1}" || return 0
  local title="$1" body="${2:-}" sound="${3:-none}"
  local args=(notification show "$title" --sound "$sound")
  [[ -n "$body" ]] && args+=(--body "$body")
  herdr_cmd "${args[@]}" >/dev/null 2>&1 || true
}

# Pick a split direction for a target pane: wide panes split right, tall panes split down.
herdr_split_direction() {
  local target="$1" layout dir
  case "${MARS_SPLIT_DIRECTION:-auto}" in
    right | down)
      printf '%s\n' "$MARS_SPLIT_DIRECTION"
      return 0
      ;;
  esac
  dir="right"
  if [[ -n "$target" ]]; then
    layout="$(herdr_cmd pane layout --pane "$target" 2>/dev/null || true)"
    if [[ -n "$layout" ]]; then
      dir="$(jq -r --arg p "$target" '
        (.result.layout.panes[]? | select(.pane_id == $p) | .rect) as $r
        | if ($r.width // 0) >= (($r.height // 0) * 2.2) then "right" else "down" end' <<<"$layout" 2>/dev/null || true)"
      [[ "$dir" == "right" || "$dir" == "down" ]] || dir="right"
    fi
  fi
  printf '%s\n' "$dir"
}

# herdr_open_split <entrypoint> <label> [KEY=VALUE ...]
# Opens a plugin-owned split pane next to the target pane and prints its pane id.
# The pane must start in the plugin root because the manifest command is the relative
# path "bash bin/mars", so the user's directory is passed as MARS_CWD instead of --cwd.
herdr_open_split() {
  local entrypoint="$1" label="$2"
  shift 2
  local target cwd dir out pane_id kv
  target="$(mars_target_pane)"
  cwd="$(mars_cwd)"
  dir="$(herdr_split_direction "$target")"
  local args=(plugin pane open --plugin "$MARS_PLUGIN_ID" --entrypoint "$entrypoint" --placement split --direction "$dir" --focus)
  [[ -n "$target" ]] && args+=(--target-pane "$target")
  [[ -n "$cwd" ]] && args+=(--env "MARS_CWD=$cwd")
  for kv in "$@"; do
    args+=(--env "$kv")
  done
  out="$(herdr_cmd "${args[@]}")" || return 1
  pane_id="$(jq -r '.result.plugin_pane.pane.pane_id // .result.pane.pane_id // empty' <<<"$out" 2>/dev/null || true)"
  if [[ -n "$pane_id" && -n "$label" ]]; then
    herdr_cmd pane rename "$pane_id" "$label" >/dev/null 2>&1 || true
  fi
  printf '%s\n' "$pane_id"
}

# herdr_open_popup <entrypoint> [KEY=VALUE ...]
# The popup placement comes from the manifest, so no --placement is passed.
herdr_open_popup() {
  local entrypoint="$1"
  shift
  local kv
  local args=(plugin pane open --plugin "$MARS_PLUGIN_ID" --entrypoint "$entrypoint")
  for kv in "$@"; do
    args+=(--env "$kv")
  done
  herdr_cmd "${args[@]}" >/dev/null
}

# herdr_wait_output <pane_id> <rust-regex> <timeout_ms>
herdr_wait_output() {
  herdr_cmd pane wait-output "$1" --regex "$2" --timeout "$3" >/dev/null 2>&1
}

# herdr_split_plain <pane_id> <direction> <cwd> -> new pane id
herdr_split_plain() {
  local out
  out="$(herdr_cmd pane split "$1" --direction "$2" --cwd "$3" --focus)" || return 1
  jq -r '.result.pane.pane_id // empty' <<<"$out"
}

# herdr_agent_start <name> <kind> <pane_id> [agent-args...]
herdr_agent_start() {
  local name="$1" kind="$2" pane="$3"
  shift 3
  herdr_cmd agent start "$name" --kind "$kind" --pane "$pane" -- "$@"
}
