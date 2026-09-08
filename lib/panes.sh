# shellcheck shell=bash
# Entry points for manifest [[panes]]. Herdr sets HERDR_PLUGIN_ENTRYPOINT_ID.

pane_banner() {
  printf '\033[1m%s\033[0m\n' "$*"
}

# Hold the pane open so the user can read failures before it closes.
pane_finish() {
  local status="$1" hold="${2:-0}"
  if [[ "$status" -ne 0 ]]; then
    printf '\nExited with status %s. Press Enter to close.' "$status"
    ui_read _ || true
  elif mars_flag_on "$hold"; then
    printf '\nDone. Press Enter to close.'
    ui_read _ || true
  fi
  return "$status"
}

# Print a fatal error and keep the pane open so it can be read.
pane_fatal() {
  printf '\033[31mmars: %s\033[0m\n' "$*"
  pane_finish 1 0
}

pane_require_doctl() {
  doctl_resolve && return 0
  pane_fatal "No doctl build with the Managed Agents commands was found (tried: ${MARS_DOCTL_BIN:-doctl-beta, doctl}). Install the doctl beta or set MARS_DOCTL_BIN in $(mars_config_dir)/.env."
}

pane_attach() {
  local id="${MARS_SESSION:-}" name="${MARS_SESSION_NAME:-${MARS_SESSION:-}}" status=0
  [[ -n "$id" ]] || { pane_fatal "MARS_SESSION is not set."; return 1; }
  pane_require_doctl || return 1
  pane_banner "Mars: attached to $name  (Ctrl-D detaches and keeps the session; y/n answers approvals; /help lists commands)"
  ohr attach "$id" || status=$?
  pane_finish "$status" 0
}

pane_run() {
  local hold="${MARS_RUN_HOLD:-0}" status=0 arg
  local -a args=()
  [[ -n "${MARS_RUN_ARGS:-}" ]] || { pane_fatal "MARS_RUN_ARGS is not set."; return 1; }
  pane_require_doctl || return 1
  while IFS= read -r arg; do
    args+=("$arg")
  done < <(jq -r '.[]' <<<"$MARS_RUN_ARGS")
  pane_banner "${MARS_RUN_LABEL:-Mars}: $(ohr_display "${args[@]}")"
  ohr "${args[@]}" || status=$?
  pane_finish "$status" "$hold"
}

pane_task() {
  local task="${MARS_TASK:-dashboard}" status=0
  task_run "$task" || status=$?
  if [[ "$status" -ne 0 ]] && ! mars_flag_on "${MARS_NO_HOLD:-0}"; then
    ui_hold
  fi
  return "$status"
}

pane_main() {
  local entrypoint="${HERDR_PLUGIN_ENTRYPOINT_ID:-task}"
  # Herdr starts pane commands in the plugin root; move to the user's directory once loaded.
  if [[ -n "${MARS_CWD:-}" && -d "$MARS_CWD" ]]; then
    cd "$MARS_CWD" || true
  fi
  case "$entrypoint" in
    task) pane_task ;;
    attach) pane_attach ;;
    run) pane_run ;;
    *) mars_die "Unknown pane entrypoint '$entrypoint'." ;;
  esac
}
