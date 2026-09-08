# shellcheck shell=bash
# Interactive tasks. Each runs inside the "task" popup pane.

MARS_TASKS="start attach dashboard logs pause resume remove proxy upload download validate new-spec doctor exec checkpoint port-forward"

# mars_pick_session <header> [status-regex] -> "id<TAB>name" on stdout.
mars_pick_session() {
  local header="$1" filter="${2:-^(?!SESSION_STATUS_DESTROYED)}" rows id name kind status created value
  if [[ -n "${MARS_PRESELECTED_SESSION:-}" ]]; then
    printf '%s\n' "$MARS_PRESELECTED_SESSION"
    return 0
  fi
  rows="$(mars_sessions_tsv "$filter")" || return 1
  if [[ -z "$rows" ]]; then
    ui_error "No matching sessions."
    return 1
  fi
  value="$(while IFS=$'\t' read -r id name kind status created; do
    printf '%s\t%s\t%s\n' "$(mars_session_display "$id" "$name" "$kind" "$status" "$created")" "$id" "$name"
  done <<<"$rows" | ui_pick "$header")" || return 1
  printf '%s\n' "$value"
}

mars_pick_spec() {
  local cwd specs display path
  cwd="$(mars_cwd)"
  specs="$(mars_find_specs "$cwd")"
  if [[ -z "$specs" ]]; then
    ui_error "No agent manifests found in $cwd or MARS_SPEC_DIRS ($MARS_SPEC_DIRS)."
    ui_info "Create one with the 'new-spec' action, or put agents.yaml in the working directory."
    return 1
  fi
  path="$(while IFS= read -r path; do
    display="$(mars_relpath "$path" "$cwd")"
    printf '%s  (%s)\t%s\n' "$display" "$(mars_spec_name "$path")" "$path"
  done <<<"$specs" | ui_pick "Choose an agent manifest")" || return 1
  printf '%s\n' "$path"
}

# Open a split pane that runs one doctl subcommand. Args after label are doctl args.
# mars_open_run <label> <hold 0|1> <args...>
mars_open_run() {
  local label="$1" hold="$2"
  shift 2
  local args_json
  args_json="$(printf '%s\n' "$@" | jq -R . | jq -s -c .)"
  herdr_open_split run "$label" "MARS_RUN_ARGS=$args_json" "MARS_RUN_HOLD=$hold" "MARS_RUN_LABEL=$label"
}

mars_open_attach() {
  local id="$1" name="$2"
  herdr_open_split attach "mars: ${name:-$id}" "MARS_SESSION=$id" "MARS_SESSION_NAME=${name:-$id}"
}

# git remote -> owner/repo, used as a default for --gh-repo.
mars_guess_repo() {
  local cwd="$1" url
  url="$(git -C "$cwd" remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || return 0
  url="${url%.git}"
  case "$url" in
    https://github.com/*) printf '%s\n' "${url#https://github.com/}" ;;
    git@github.com:*) printf '%s\n' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf '%s\n' "${url#ssh://git@github.com/}" ;;
  esac
}

task_start() {
  local cwd source spec name repo prompt label
  cwd="$(mars_cwd)"
  ui_header "Start a Managed Agents session"
  source="$(printf '%s\n' \
    $'From an agent manifest (agents.yaml)\tspec' \
    $'From a saved Agent Config\tconfig' \
    $'Quick start: pick a harness, no manifest\tharness' | MARS_PICK_AUTOSELECT_SINGLE=0 ui_pick "How do you want to start?")" || return 1

  local args=(start)
  case "$source" in
    spec)
      spec="$(mars_pick_spec)" || return 1
      mars_remember last-spec "$spec"
      name="$(ui_ask "Session name (blank keeps the manifest name or auto-generates)" "")" || return 1
      args+=(--spec "$spec")
      [[ -n "$name" ]] && args+=(--name "$name")
      label="${name:-$(mars_spec_name "$spec")}"
      ;;
    config)
      local rows id cname created chosen
      rows="$(mars_configs_tsv)" || return 1
      [[ -n "$rows" ]] || { ui_error "No Agent Configs found."; return 1; }
      chosen="$(while IFS=$'\t' read -r id cname created; do
        printf '%s  (%s)\t%s\t%s\n' "$cname" "${created:0:10}" "$id" "$cname"
      done <<<"$rows" | ui_pick "Choose an Agent Config")" || return 1
      id="${chosen%%$'\t'*}"
      cname="${chosen#*$'\t'}"
      name="$(ui_ask "Session name (required)" "$cname-$(date +%m%d%H%M)")" || return 1
      [[ -n "$name" ]] || return 1
      args+=(--config-id "$id" --name "$name")
      label="$name"
      ;;
    harness)
      local harness
      harness="$(printf '%s\n' $'claude-code\tclaude-code' $'codex\tcodex' $'opencode\topencode' | MARS_PICK_AUTOSELECT_SINGLE=0 ui_pick "Choose a harness")" || return 1
      name="$(ui_ask "Session name (blank auto-generates)" "")" || return 1
      args+=(--harness "$harness")
      [[ -n "$name" ]] && args+=(--name "$name")
      label="${name:-$harness}"
      ;;
  esac

  if [[ "$source" != "config" ]]; then
    repo="$(ui_ask "GitHub repo to clone (owner/repo, blank for none)" "$(mars_guess_repo "$cwd")")" || return 1
    [[ -n "$repo" ]] && args+=(--gh-repo "$repo")
  fi
  prompt="$(ui_ask "Initial prompt (blank for none)" "")" || return 1
  [[ -n "$prompt" ]] && args+=(--prompt "$prompt")

  ui_info ""
  ui_info "Opening a pane: $(ohr_display "${args[@]}")"
  mars_open_run "mars: ${label:-session}" 1 "${args[@]}" >/dev/null || return 1
  herdr_notify "Mars: starting session" "${label:-session} is starting in a new pane."
}

task_attach() {
  local chosen id name
  chosen="$(mars_pick_session "Attach to a session" '^(?!SESSION_STATUS_DESTROYED)')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  mars_remember last-session "$id"
  mars_open_attach "$id" "$name" >/dev/null || return 1
}

task_logs() {
  local chosen id name
  chosen="$(mars_pick_session "Replay history for a session" '.')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  mars_open_run "mars logs: $name" 1 logs "$id" >/dev/null
}

# mars_lifecycle <verb> <header> <status-regex> [confirm 0|1]
mars_lifecycle() {
  local verb="$1" header="$2" filter="$3" confirm="${4:-0}" chosen id name
  chosen="$(mars_pick_session "$header" "$filter")" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  if [[ "$confirm" == "1" ]]; then
    ui_confirm "Really $verb '$name' ($id)?" || { ui_info "Cancelled."; return 1; }
  fi
  ui_info "$(ohr_display "$verb" "$id")"
  if ohr "$verb" "$id"; then
    herdr_notify "Mars: $verb" "$name: $verb succeeded." "done"
  else
    herdr_notify "Mars: $verb failed" "$name: see the Mars popup." request
    return 1
  fi
}

task_pause() {
  local status=0
  mars_lifecycle pause "Pause a session" '^SESSION_STATUS_(READY|RUNNING|ACTIVE)' || status=$?
  ui_hold
  return "$status"
}

task_resume() {
  local status=0
  mars_lifecycle resume "Resume a paused session" '^SESSION_STATUS_PAUSED' || status=$?
  ui_hold
  return "$status"
}

task_remove() {
  local status=0
  mars_lifecycle remove "Remove a session (tears down its sandbox)" '^(?!SESSION_STATUS_DESTROYED)' 1 || status=$?
  ui_hold
  return "$status"
}

task_checkpoint() {
  local chosen id name label
  chosen="$(mars_pick_session "Checkpoint a session (between agent turns)" '^(?!SESSION_STATUS_DESTROYED)')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  label="$(ui_ask "Checkpoint label (optional)" "")" || return 1
  local args=(checkpoint create "$id")
  [[ -n "$label" ]] && args+=(--label "$label")
  ui_info "$(ohr_display "${args[@]}")"
  local status=0
  if ohr "${args[@]}"; then
    herdr_notify "Mars: checkpoint saved" "$name${label:+: $label}" "done"
  else
    status=$?
  fi
  ui_hold
  return "$status"
}

task_proxy() {
  local chosen id name port pane cwd agent_pane agent_name n
  chosen="$(mars_pick_session "Bridge a session to the local ${MARS_PROXY_TYPE} CLI" '^(?!SESSION_STATUS_DESTROYED)')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  port="$(ui_ask "Local proxy port" "$MARS_PROXY_PORT")" || return 1
  cwd="$(mars_cwd)"

  pane="$(mars_open_run "mars proxy: $name" 1 start-proxy --type "$MARS_PROXY_TYPE" --session "$id" --port "$port")" || return 1
  ui_info "Proxy pane: $pane. Waiting for it to listen on 127.0.0.1:$port ..."
  if ! herdr_wait_output "$pane" "(?i)(listening|ws://|127\\.0\\.0\\.1:$port|:$port\\b)" 30000; then
    ui_error "The proxy did not report a listening address within 30s. Check the proxy pane."
    ui_hold
    return 1
  fi

  if ! mars_flag_on "$MARS_PROXY_AUTOSTART_AGENT" || [[ "$MARS_PROXY_TYPE" != "codex" ]] || ! mars_have codex; then
    ui_info "Connect your client with: codex --remote ws://127.0.0.1:$port"
    herdr_notify "Mars: proxy ready" "codex --remote ws://127.0.0.1:$port" "done"
    ui_hold
    return 0
  fi

  agent_pane="$(herdr_split_plain "$pane" down "$cwd")" || { ui_error "Could not split a pane for Codex."; ui_hold; return 1; }
  agent_name="$(mars_agent_name "$name")"
  for n in "" -2 -3 -4; do
    if herdr_agent_start "${agent_name}${n}" codex "$agent_pane" --remote "ws://127.0.0.1:$port" >/dev/null 2>&1; then
      herdr_notify "Mars: Codex connected" "Agent '${agent_name}${n}' is bridged to $name." "done"
      return 0
    fi
  done
  ui_error "Herdr could not start Codex in pane $agent_pane. Run manually: codex --remote ws://127.0.0.1:$port"
  ui_hold
  return 1
}

task_exec() {
  local chosen id name cmd
  chosen="$(mars_pick_session "Run a command in a session sandbox" '^(?!SESSION_STATUS_DESTROYED)')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  cmd="$(ui_ask "Command to run in /workspace" "ls -la")" || return 1
  [[ -n "$cmd" ]] || return 1
  mars_open_run "mars exec: $name" 1 exec "$id" -- sh -c "$cmd" >/dev/null
}

task_port_forward() {
  local chosen id name ports
  chosen="$(mars_pick_session "Forward local ports into a sandbox" '^(?!SESSION_STATUS_DESTROYED)')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  ports="$(ui_ask "Ports ([local:]remote, space separated)" "3000")" || return 1
  [[ -n "$ports" ]] || return 1
  # shellcheck disable=SC2206 # intentional word splitting of the port list
  local port_args=($ports)
  mars_open_run "mars ports: $name" 1 port-forward "$id" "${port_args[@]}" >/dev/null
}

task_upload() {
  local chosen id name cwd local_file default_local workspace_path selected
  chosen="$(mars_pick_session "Upload a file into a session workspace" '^(?!SESSION_STATUS_DESTROYED)')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  cwd="$(mars_cwd)"
  selected="$(mars_ctx selected_text | head -n 1 | tr -d '\r')"
  default_local=""
  if [[ -n "$selected" && -f "$cwd/$selected" ]]; then
    default_local="$cwd/$selected"
  elif [[ -n "$selected" && -f "$selected" ]]; then
    default_local="$selected"
  fi
  local_file="$(ui_ask "Local file" "$default_local")" || return 1
  local_file="${local_file/#\~/$HOME}"
  [[ "$local_file" = /* ]] || local_file="$cwd/$local_file"
  [[ -f "$local_file" ]] || { ui_error "Not a file: $local_file"; ui_hold; return 1; }
  workspace_path="$(ui_ask "Destination path under /workspace" "$(basename "$local_file")")" || return 1
  ui_info "$(ohr_display upload "$id" --local-file "$local_file" --workspace-path "$workspace_path")"
  local status=0
  if ohr upload "$id" --local-file "$local_file" --workspace-path "$workspace_path"; then
    herdr_notify "Mars: uploaded" "$(basename "$local_file") -> $name:/workspace/$workspace_path" "done"
  else
    status=$?
  fi
  ui_hold
  return "$status"
}

task_download() {
  local chosen id name cwd workspace_path save_to
  chosen="$(mars_pick_session "Download a file from a session workspace" '^(?!SESSION_STATUS_DESTROYED)')" || return 1
  id="${chosen%%$'\t'*}"
  name="${chosen#*$'\t'}"
  cwd="$(mars_cwd)"
  workspace_path="$(ui_ask "Source path under /workspace" "$(mars_ctx selected_text | head -n 1 | tr -d '\r')")" || return 1
  [[ -n "$workspace_path" ]] || return 1
  save_to="$(ui_ask "Save to" "$cwd/$(basename "$workspace_path")")" || return 1
  save_to="${save_to/#\~/$HOME}"
  [[ "$save_to" = /* ]] || save_to="$cwd/$save_to"
  ui_info "$(ohr_display download "$id" --workspace-path "$workspace_path" --save-to "$save_to")"
  local status=0
  if ohr download "$id" --workspace-path "$workspace_path" --save-to "$save_to"; then
    herdr_notify "Mars: downloaded" "$name:/workspace/$workspace_path -> $save_to" "done"
  else
    status=$?
  fi
  ui_hold
  return "$status"
}

task_validate() {
  local spec
  spec="$(mars_pick_spec)" || return 1
  ui_header "Validating $spec"
  local status=0
  if ohr validate "$spec"; then
    ui_info "OK: manifest accepted by the client-side validator."
  else
    status=$?
  fi
  ui_info "The API remains the authoritative validator; confirm policy behavior on a live session."
  ui_hold
  return "$status"
}

task_new_spec() {
  local cwd template name dest label
  cwd="$(mars_cwd)"
  template="$(for f in "$MARS_ROOT"/specs/*.yaml; do
    label="$(sed -n -E 's/^# template:[[:space:]]*//p' "$f" | head -n 1)"
    printf '%s\t%s\n' "${label:-$(basename "$f")}" "$f"
  done | MARS_PICK_AUTOSELECT_SINGLE=0 ui_pick "Choose a template")" || return 1
  name="$(ui_ask "Session name" "$(basename "$cwd" | tr -c 'A-Za-z0-9-\n' '-')-agent")" || return 1
  [[ -n "$name" ]] || return 1
  dest="$(ui_ask "Write manifest to" "$cwd/agents.yaml")" || return 1
  dest="${dest/#\~/$HOME}"
  [[ "$dest" = /* ]] || dest="$cwd/$dest"
  if [[ -e "$dest" ]]; then
    ui_confirm "$dest exists. Overwrite?" || { ui_info "Cancelled."; return 1; }
  fi
  mkdir -p "$(dirname "$dest")"
  sed -E "s/^name:.*/name: $name/" "$template" | grep -v -E '^# template:' >"$dest"
  mars_remember last-spec "$dest"
  ui_info "Wrote $dest"
  ui_info "Secrets use \${VAR} placeholders; doctl expands them from your environment and prompts when missing."
  ui_info "Never put credentials under 'env:'. Keep them under 'secrets:'."
  if ui_confirm "Validate it now?"; then
    ohr validate "$dest" && ui_info "OK: manifest accepted."
  fi
  ui_hold
}

task_doctor() {
  local ok=0 fail=0 herdr_version account
  ui_header "Mars doctor"
  check() {
    if "$@" >/dev/null 2>&1; then
      ok=$((ok + 1))
      return 0
    fi
    fail=$((fail + 1))
    return 1
  }
  if check doctl_resolve; then
    ui_info "✔ doctl with Managed Agents commands: $MARS_DOCTL $MARS_DOCTL_GROUP ($("$MARS_DOCTL" version 2>/dev/null | head -n 1))"
    if account="$("$MARS_DOCTL" account get -o json 2>/dev/null)"; then
      ok=$((ok + 1))
      ui_info "✔ doctl auth: $(jq -r '.email // .uuid // "ok"' <<<"$account" 2>/dev/null)"
    else
      fail=$((fail + 1))
      ui_error "✘ doctl auth: run '$MARS_DOCTL auth init' and paste a Personal Access Token."
    fi
    if check ohr list -o json --page-size 1; then
      ui_info "✔ Managed Agents API reachable (session list succeeded)."
    else
      ui_error "✘ Managed Agents API call failed. A 404 usually means the feature is not enabled for your team yet."
    fi
  else
    ui_error "✘ No doctl build with the Managed Agents commands found (tried: ${MARS_DOCTL_BIN:-doctl-beta, doctl}). Install the doctl beta or set MARS_DOCTL_BIN in $(mars_config_dir)/.env."
  fi
  if check mars_have jq; then ui_info "✔ jq"; else ui_error "✘ jq is required."; fi
  if mars_have fzf; then ui_info "✔ fzf (fuzzy pickers enabled)"; else ui_info "· fzf not found; numbered menus will be used."; fi
  if mars_have codex; then ui_info "✔ codex CLI (proxy action can auto-connect it)"; else ui_info "· codex CLI not found; the proxy action prints connection instructions instead."; fi
  herdr_version="$(herdr_cmd --version 2>/dev/null || true)"
  if [[ -n "$herdr_version" ]]; then ui_info "✔ ${herdr_version} via ${HERDR_BIN_PATH:-herdr}"; else ui_error "✘ herdr binary not reachable via HERDR_BIN_PATH."; fi
  ui_info "· config dir: $(mars_config_dir) $([[ -f "$(mars_config_dir)/.env" ]] && echo '(.env present)' || echo '(no .env, defaults in use)')"
  ui_info "· state dir:  $(mars_state_dir)"
  ui_info "· spec dirs:  $MARS_SPEC_DIRS"
  ui_info "· target pane: $(mars_target_pane) (panes open next to this one); cwd: $(mars_cwd)"
  ui_info "· specs visible from $(mars_cwd): $(mars_find_specs "$(mars_cwd)" | wc -l | tr -d ' ')"
  ui_info ""
  ui_info "$ok checks passed, $fail failed."
  ui_hold
  [[ "$fail" -eq 0 ]]
}

task_dashboard() {
  local chosen id name action
  while true; do
    chosen="$( {
      mars_sessions_tsv '.' | while IFS=$'\t' read -r id name kind status created; do
        printf '%s\t%s\t%s\n' "$(mars_session_display "$id" "$name" "$kind" "$status" "$created")" "$id" "$name"
      done
      printf '+ start a new session\t__start\t\n'
      printf '↻ refresh\t__refresh\t\n'
      printf 'q quit\t__quit\t\n'
    } | MARS_PICK_AUTOSELECT_SINGLE=0 ui_pick "Managed Agents sessions")" || return 0
    id="${chosen%%$'\t'*}"
    name="${chosen#*$'\t'}"
    case "$id" in
      __quit) return 0 ;;
      __refresh) continue ;;
      __start) task_start; return $? ;;
    esac
    action="$(printf '%s\n' \
      $'attach\tattach' $'logs\tlogs' $'show details\tshow' $'pause\tpause' $'resume\tresume' \
      $'checkpoint\tcheckpoint' $'proxy (codex)\tproxy' $'exec command\texec' $'port-forward\tport-forward' \
      $'upload file\tupload' $'download file\tdownload' $'remove\tremove' $'back\tback' \
      | MARS_PICK_AUTOSELECT_SINGLE=0 ui_pick "$name: choose an action")" || continue
    case "$action" in
      back) continue ;;
      show)
        ohr show "$id" -o json | jq . >&2 || true
        ui_hold
        ;;
      attach) mars_open_attach "$id" "$name" >/dev/null; return $? ;;
      logs) mars_open_run "mars logs: $name" 1 logs "$id" >/dev/null; return $? ;;
      pause | resume)
        ohr "$action" "$id" && herdr_notify "Mars: $action" "$name" "done"
        ;;
      remove)
        if ui_confirm "Really remove '$name' ($id)?"; then
          ohr remove "$id" && herdr_notify "Mars: removed" "$name" "done"
        fi
        ;;
      checkpoint)
        local label
        label="$(ui_ask "Checkpoint label (optional)" "")" || continue
        if [[ -n "$label" ]]; then ohr checkpoint create "$id" --label "$label"; else ohr checkpoint create "$id"; fi
        ui_hold
        ;;
      proxy | exec | port-forward | upload | download)
        MARS_PRESELECTED_SESSION="$id"$'\t'"$name" "task_${action//-/_}"
        return $?
        ;;
    esac
  done
}

task_run() {
  local task="$1"
  case " $MARS_TASKS " in
    *" $task "*) ;;
    *) mars_die "Unknown task '$task'. Known tasks: $MARS_TASKS" ;;
  esac
  mars_require_jq
  if [[ "$task" != "doctor" ]]; then
    doctl_resolve || {
      ui_error "No doctl build with the Managed Agents commands was found."
      ui_info "Install the doctl beta (doctl-beta) or set MARS_DOCTL_BIN in $(mars_config_dir)/.env."
      ui_hold
      return 1
    }
  fi
  "task_${task//-/_}"
}
