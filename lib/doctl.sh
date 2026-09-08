# shellcheck shell=bash
# doctl wrappers for the Managed Agents Runtime Services (M.A.R.S) command group.
#
# The beta doctl exposes the group as `harness-runtime` (aliases: agent, agents, ohr).
# Older beta builds used `open-harness-runtime`; both are probed.

MARS_DOCTL_GROUPS=(harness-runtime open-harness-runtime)

# Resolve the doctl binary and command group once; exports MARS_DOCTL and MARS_DOCTL_GROUP.
doctl_resolve() {
  if [[ -n "${MARS_DOCTL:-}" && -n "${MARS_DOCTL_GROUP:-}" ]]; then
    return 0
  fi
  local candidates=() bin group
  if [[ -n "${MARS_DOCTL_BIN:-}" ]]; then
    candidates=("$MARS_DOCTL_BIN")
  else
    candidates=(doctl-beta doctl)
  fi
  for bin in "${candidates[@]}"; do
    mars_have "$bin" || [[ -x "$bin" ]] || continue
    for group in "${MARS_DOCTL_GROUPS[@]}"; do
      if "$bin" "$group" --help >/dev/null 2>&1; then
        export MARS_DOCTL="$bin" MARS_DOCTL_GROUP="$group"
        return 0
      fi
    done
  done
  return 1
}

doctl_require() {
  doctl_resolve || mars_die "No doctl build with the Managed Agents commands was found. Install the doctl beta (doctl-beta) or set MARS_DOCTL_BIN. See README."
}

# ohr <args...>: run a Managed Agents subcommand.
ohr() {
  doctl_require
  "$MARS_DOCTL" "$MARS_DOCTL_GROUP" "$@"
}

# Human-readable command line for headers and logs.
ohr_display() {
  doctl_resolve || true
  printf '%s %s %s\n' "${MARS_DOCTL:-doctl}" "${MARS_DOCTL_GROUP:-harness-runtime}" "$*"
}

mars_pretty_status() {
  local s="${1#SESSION_STATUS_}"
  printf '%s\n' "$s" | tr '[:upper:]' '[:lower:]'
}

mars_pretty_kind() {
  local k="${1#AGENT_KIND_}"
  printf '%s\n' "$k" | tr '[:upper:]' '[:lower:]' | tr '_' '-'
}

# mars_sessions_tsv [status-regex]
# Prints: session_id<TAB>name<TAB>kind<TAB>status<TAB>created
mars_sessions_tsv() {
  local filter="${1:-.}" json
  json="$(ohr list -o json --page-size "${MARS_LIST_PAGE_SIZE:-100}")" || return 1
  jq -r --arg re "$filter" '
    def s(f): (f // "") | tostring;
    (if type == "array" then . else (.sessions // .items // []) end)
    | map(select((s(.status) | test($re))))
    | .[]
    | [ s(.session_id // .id), s(.name), s(.agent_kind // .agent), s(.status), s(.created_at) ]
    | @tsv' <<<"$json"
}

# Session display line for pickers: "● name  kind · status · created".
mars_session_display() {
  local id="$1" name="$2" kind="$3" status="$4" created="$5" dot pstatus
  pstatus="$(mars_pretty_status "$status")"
  case "$pstatus" in
    ready | running) dot="●" ;;
    paused) dot="○" ;;
    *) dot="·" ;;
  esac
  created="${created:0:16}"
  created="${created/T/ }"
  printf '%s %s  %s · %s · %s' "$dot" "${name:-$id}" "$(mars_pretty_kind "$kind")" "$pstatus" "$created"
}

# mars_configs_tsv: id<TAB>name<TAB>created
mars_configs_tsv() {
  local json
  json="$(ohr config list -o json)" || return 1
  jq -r '
    def s(f): (f // "") | tostring;
    (if type == "array" then . else (.configs // .items // []) end)
    | .[] | [ s(.id), s(.name), s(.created_at) ] | @tsv' <<<"$json"
}

# Top-level `name:` from a flat manifest (best effort, no YAML parser needed).
mars_spec_name() {
  sed -n -E 's/^name:[[:space:]]*["'"'"']?([^"'"'"'#]*[^"'"'"'#[:space:]])["'"'"']?[[:space:]]*(#.*)?$/\1/p' "$1" | head -n 1
}

mars_is_spec() {
  [[ -f "$1" ]] && grep -q -E '^(agent|kind|spec):' "$1" 2>/dev/null
}

# mars_find_specs <cwd>: prints absolute paths, most recently used first, deduplicated.
mars_find_specs() {
  local cwd="$1" dir f last
  local dirs=("$cwd" "$cwd/specs" "$cwd/.mars")
  local IFS=':'
  for dir in ${MARS_SPEC_DIRS:-}; do
    dirs+=("$dir")
  done
  unset IFS
  last="$(mars_recall last-spec)"
  {
    [[ -n "$last" ]] && mars_is_spec "$last" && printf '%s\n' "$last"
    for dir in "${dirs[@]}"; do
      [[ -d "$dir" ]] || continue
      for f in "$dir"/*.yaml "$dir"/*.yml "$dir"/*.json; do
        mars_is_spec "$f" && printf '%s\n' "$f"
      done
    done
  } | awk '!seen[$0]++'
}
