#!/usr/bin/env bash
# Test suite for the Mars plugin. Runs bin/mars against fake doctl/herdr binaries.
# Usage: tests/run.sh [test-name-filter]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKES="$ROOT/tests/fakes"
TMP="$ROOT/tests/.tmp"
FILTER="${1:-}"
PASS=0
FAIL=0
CURRENT=""

rm -rf "$TMP"
mkdir -p "$TMP"
chmod +x "$FAKES"/*

export PATH="$FAKES:/usr/bin:/bin"
export HERDR_BIN_PATH="$FAKES/herdr"
export HERDR_ENV=1
export HERDR_PLUGIN_ID="digitalocean.mars"
export HERDR_PLUGIN_ROOT="$ROOT"
export MARS_USE_FZF=0
export MARS_NO_HOLD=1
export HOME="$TMP/home"
mkdir -p "$HOME"

# ---------------------------------------------------------------- harness

t() {
  CURRENT="$1"
  if [[ -n "$FILTER" && "$CURRENT" != *"$FILTER"* ]]; then
    CURRENT=""
    return 1
  fi
  local dir="$TMP/$CURRENT"
  mkdir -p "$dir/config" "$dir/state" "$dir/cwd"
  export HERDR_PLUGIN_CONFIG_DIR="$dir/config"
  export HERDR_PLUGIN_STATE_DIR="$dir/state"
  export MARS_FAKE_LOG="$dir/fake.log"
  export TEST_CWD="$dir/cwd"
  export HERDR_PLUGIN_CONTEXT_JSON
  HERDR_PLUGIN_CONTEXT_JSON="$(jq -n -c --arg cwd "$TEST_CWD" '{focused_pane_id:"w1:p3",focused_pane_cwd:$cwd,workspace_id:"w1",tab_id:"w1:t1"}')"
  : >"$MARS_FAKE_LOG"
  unset MARS_TASK MARS_RUN_ARGS MARS_RUN_HOLD MARS_SESSION MARS_SESSION_NAME MARS_TARGET_PANE MARS_CWD
  unset MARS_DOCTL_BIN MARS_SPLIT_DIRECTION MARS_PROXY_PORT MARS_ASSUME_YES FAKE_DOCTL_EXIT FAKE_HERDR_TALL
  unset FAKE_HERDR_WAIT_EXIT FAKE_HERDR_AGENT_EXIT FAKE_DOCTL_GROUP MARS_SPEC_DIRS MARS_DOCTL MARS_DOCTL_GROUP
  OUT="$dir/stdout"
  ERR="$dir/stderr"
  return 0
}

# run_mars <stdin-text> <args...>; sets STATUS.
run_mars() {
  local input="$1"
  shift
  printf '%b' "$input" | bash "$ROOT/bin/mars" "$@" >"$OUT" 2>"$ERR"
  STATUS=$?
}

# run_pane <entrypoint> <stdin-text> [VAR=VALUE ...]
run_pane() {
  local entrypoint="$1" input="$2"
  shift 2
  printf '%b' "$input" | env HERDR_PLUGIN_ENTRYPOINT_ID="$entrypoint" "$@" bash "$ROOT/bin/mars" pane >"$OUT" 2>"$ERR"
  STATUS=$?
}

ok() {
  PASS=$((PASS + 1))
}

fail() {
  FAIL=$((FAIL + 1))
  printf '\033[31mFAIL\033[0m %s: %s\n' "$CURRENT" "$1"
  if [[ -f "$ERR" ]]; then
    sed 's/^/    stderr: /' "$ERR" | head -n 12
  fi
  if [[ -f "$MARS_FAKE_LOG" ]]; then
    sed 's/^/    log: /' "$MARS_FAKE_LOG" | head -n 12
  fi
}

assert_status() {
  if [[ "$STATUS" -eq "$1" ]]; then ok; else fail "expected exit $1, got $STATUS"; fi
}

assert_log() {
  if grep -q -F -- "$1" "$MARS_FAKE_LOG"; then ok; else fail "fake log missing: $1"; fi
}

assert_not_log() {
  if grep -q -F -- "$1" "$MARS_FAKE_LOG"; then fail "fake log unexpectedly has: $1"; else ok; fi
}

assert_out() {
  if grep -q -F -- "$1" "$OUT" "$ERR"; then ok; else fail "output missing: $1"; fi
}

assert_file_has() {
  if [[ -f "$1" ]] && grep -q -F -- "$2" "$1"; then ok; else fail "$1 missing: $2"; fi
}

assert_eq() {
  if [[ "$1" == "$2" ]]; then ok; else fail "expected '$2', got '$1'"; fi
}

write_spec() {
  local path="$1" name="$2"
  mkdir -p "$(dirname "$path")"
  # shellcheck disable=SC2016 # the ${OPENAI_API_KEY} placeholder is meant for doctl, not bash
  printf 'name: %s\nagent: codex\nsize: mv-2vcpu-4gb\nsecrets:\n  OPENAI_API_KEY: "${OPENAI_API_KEY}"\n' "$name" >"$path"
}

# ---------------------------------------------------------------- tests

if t tasks_lists_all_tasks; then
  run_mars "" tasks
  assert_status 0
  assert_out "dashboard"
  assert_out "new-spec"
fi

if t unknown_command_exits_2; then
  run_mars "" bogus
  assert_status 2
fi

if t action_opens_popup_with_context; then
  run_mars "" action start
  assert_status 0
  assert_log "herdr|plugin|pane|open|--plugin|digitalocean.mars|--entrypoint|task|--env|MARS_TASK=start|--env|MARS_TARGET_PANE=w1:p3|--env|MARS_CWD=$TEST_CWD"
  assert_not_log "--placement"
fi

if t action_rejects_unknown_task; then
  run_mars "" action nope
  assert_status 1
  assert_not_log "plugin|pane|open"
fi

if t start_from_single_spec_uses_defaults; then
  write_spec "$TEST_CWD/agents.yaml" demo-agent
  run_pane task "1\n\n\n\n" MARS_TASK=start
  assert_status 0
  assert_log "herdr|plugin|pane|open|--plugin|digitalocean.mars|--entrypoint|run|--placement|split|--direction|right|--focus|--target-pane|w1:p3|--env|MARS_CWD=$TEST_CWD|--env|MARS_RUN_ARGS=[\"start\",\"--spec\",\"$TEST_CWD/agents.yaml\"]|--env|MARS_RUN_HOLD=1|--env|MARS_RUN_LABEL=mars: demo-agent"
  assert_log "herdr|pane|rename|w1:p9|mars: demo-agent"
  assert_log "herdr|notification|show|Mars: starting session"
  assert_eq "$(cat "$HERDR_PLUGIN_STATE_DIR/last-spec")" "$TEST_CWD/agents.yaml"
fi

if t start_passes_name_repo_and_prompt; then
  write_spec "$TEST_CWD/agents.yaml" demo-agent
  run_pane task "1\nmy-sess\nowner/repo\nhello world\n" MARS_TASK=start
  assert_status 0
  assert_log "MARS_RUN_ARGS=[\"start\",\"--spec\",\"$TEST_CWD/agents.yaml\",\"--name\",\"my-sess\",\"--gh-repo\",\"owner/repo\",\"--prompt\",\"hello world\"]"
  assert_log "MARS_RUN_LABEL=mars: my-sess"
fi

if t start_picks_among_multiple_specs_and_spec_dirs; then
  write_spec "$TEST_CWD/agents.yaml" first
  write_spec "$HERDR_PLUGIN_CONFIG_DIR/specs/second.yaml" second
  printf 'not: a spec\n' >"$TEST_CWD/notes.yaml"
  run_pane task "1\n2\n\n\n\n" MARS_TASK=start
  assert_status 0
  assert_out "agents.yaml  (first)"
  assert_out "second.yaml  (second)"
  assert_log "MARS_RUN_ARGS=[\"start\",\"--spec\",\"$HERDR_PLUGIN_CONFIG_DIR/specs/second.yaml\"]"
  if grep -q "notes.yaml" "$ERR"; then fail "non-spec yaml offered"; else ok; fi
fi

if t start_quick_harness; then
  run_pane task "3\n2\n\n\n\n" MARS_TASK=start
  assert_status 0
  assert_log "MARS_RUN_ARGS=[\"start\",\"--harness\",\"codex\"]"
fi

if t start_from_agent_config; then
  run_pane task "2\n1\nfrom-cfg\n\n" MARS_TASK=start
  assert_status 0
  assert_log "doctl|harness-runtime|config|list|-o|json"
  assert_log "MARS_RUN_ARGS=[\"start\",\"--config-id\",\"cfg-1\",\"--name\",\"from-cfg\"]"
fi

if t start_without_specs_fails_cleanly; then
  run_pane task "1\n" MARS_TASK=start
  assert_status 1
  assert_out "No agent manifests found"
fi

if t attach_excludes_destroyed_and_opens_attach_pane; then
  run_pane task "2\n" MARS_TASK=attach
  assert_status 0
  assert_out "alpha"
  assert_out "beta"
  if grep -q "gamma" "$ERR"; then fail "destroyed session offered"; else ok; fi
  assert_log "herdr|plugin|pane|open|--plugin|digitalocean.mars|--entrypoint|attach|--placement|split|--direction|right|--focus|--target-pane|w1:p3|--env|MARS_CWD=$TEST_CWD|--env|MARS_SESSION=01a0-beta|--env|MARS_SESSION_NAME=beta"
  assert_log "herdr|pane|rename|w1:p9|mars: beta"
  assert_eq "$(cat "$HERDR_PLUGIN_STATE_DIR/last-session")" "01a0-beta"
fi

if t pause_only_offers_ready_sessions; then
  run_pane task "" MARS_TASK=pause
  assert_status 0
  assert_log "doctl|harness-runtime|pause|01a0-alpha"
  assert_log "herdr|notification|show|Mars: pause|--sound|done"
fi

if t resume_only_offers_paused_sessions; then
  run_pane task "" MARS_TASK=resume
  assert_status 0
  assert_log "doctl|harness-runtime|resume|01a0-beta"
fi

if t remove_requires_confirmation; then
  run_pane task "1\nn\n" MARS_TASK=remove
  assert_status 1
  assert_not_log "doctl|harness-runtime|remove"
  run_pane task "1\ny\n" MARS_TASK=remove
  assert_status 0
  assert_log "doctl|harness-runtime|remove|01a0-alpha"
fi

if t lifecycle_failure_notifies_and_fails; then
  FAKE_DOCTL_EXIT=1 run_pane task "" MARS_TASK=pause
  assert_status 1
  assert_log "herdr|notification|show|Mars: pause failed|--sound|request"
fi

if t logs_opens_holding_run_pane; then
  run_pane task "3\n" MARS_TASK=logs
  assert_status 0
  assert_log "--entrypoint|run|--placement|split|--direction|right|--focus|--target-pane|w1:p3|--env|MARS_CWD=$TEST_CWD|--env|MARS_RUN_ARGS=[\"logs\",\"01a0-gamma\"]|--env|MARS_RUN_HOLD=1|--env|MARS_RUN_LABEL=mars logs: gamma"
fi

if t proxy_starts_proxy_then_codex_agent; then
  run_pane task "1\n\n" MARS_TASK=proxy
  assert_status 0
  assert_log "MARS_RUN_ARGS=[\"start-proxy\",\"--type\",\"codex\",\"--session\",\"01a0-alpha\",\"--port\",\"1144\"]"
  assert_log "herdr|pane|wait-output|w1:p9|--regex|"
  assert_log "herdr|pane|split|w1:p9|--direction|down|--cwd|$TEST_CWD|--focus"
  assert_log "herdr|agent|start|mars-alpha|--kind|codex|--pane|w1:p10|--|--remote|ws://127.0.0.1:1144"
  assert_log "herdr|notification|show|Mars: Codex connected"
fi

if t proxy_retries_agent_name_then_gives_up; then
  FAKE_HERDR_AGENT_EXIT=1 run_pane task "1\n\n" MARS_TASK=proxy
  assert_status 1
  assert_log "herdr|agent|start|mars-alpha-4|--kind|codex"
  assert_out "codex --remote ws://127.0.0.1:1144"
fi

if t proxy_wait_timeout_fails_without_agent; then
  FAKE_HERDR_WAIT_EXIT=1 run_pane task "1\n\n" MARS_TASK=proxy
  assert_status 1
  assert_not_log "herdr|agent|start"
  assert_out "did not report a listening address"
fi

if t proxy_honors_env_file_and_env_precedence; then
  printf 'MARS_PROXY_PORT=2222\nMARS_SPLIT_DIRECTION="down"\n' >"$HERDR_PLUGIN_CONFIG_DIR/.env"
  run_pane task "1\n\n" MARS_TASK=proxy
  assert_status 0
  assert_log "\"--port\",\"2222\"]"
  assert_log "--placement|split|--direction|down|"
  MARS_PROXY_PORT=3333 run_pane task "1\n\n" MARS_TASK=proxy
  assert_log "\"--port\",\"3333\"]"
fi

if t split_direction_follows_pane_shape; then
  FAKE_HERDR_TALL=1 run_pane task "1\n" MARS_TASK=attach
  assert_status 0
  assert_log "--placement|split|--direction|down|"
fi

if t exec_runs_shell_command_in_run_pane; then
  run_pane task "1\nls -la /workspace\n" MARS_TASK=exec
  assert_status 0
  assert_log "MARS_RUN_ARGS=[\"exec\",\"01a0-alpha\",\"--\",\"sh\",\"-c\",\"ls -la /workspace\"]"
fi

if t port_forward_splits_port_list; then
  run_pane task "1\n3000 8080:8000\n" MARS_TASK=port-forward
  assert_status 0
  assert_log "MARS_RUN_ARGS=[\"port-forward\",\"01a0-alpha\",\"3000\",\"8080:8000\"]"
fi

if t checkpoint_with_label; then
  run_pane task "1\nbefore-refactor\n" MARS_TASK=checkpoint
  assert_status 0
  assert_log "doctl|harness-runtime|checkpoint|create|01a0-alpha|--label|before-refactor"
fi

if t upload_defaults_to_selected_text_file; then
  printf 'hello\n' >"$TEST_CWD/README.md"
  HERDR_PLUGIN_CONTEXT_JSON="$(jq -c '. + {selected_text:"README.md"}' <<<"$HERDR_PLUGIN_CONTEXT_JSON")"
  run_pane task "1\n\n\n" MARS_TASK=upload
  assert_status 0
  assert_log "doctl|harness-runtime|upload|01a0-alpha|--local-file|$TEST_CWD/README.md|--workspace-path|README.md"
fi

if t upload_rejects_missing_file; then
  run_pane task "1\nnope.txt\n" MARS_TASK=upload
  assert_status 1
  assert_not_log "doctl|harness-runtime|upload"
fi

if t download_defaults_save_path_to_cwd; then
  run_pane task "1\nout/result.txt\n\n" MARS_TASK=download
  assert_status 0
  assert_log "doctl|harness-runtime|download|01a0-alpha|--workspace-path|out/result.txt|--save-to|$TEST_CWD/result.txt"
fi

if t validate_runs_doctl_validate; then
  write_spec "$TEST_CWD/agents.yaml" demo
  run_pane task "" MARS_TASK=validate
  assert_status 0
  assert_log "doctl|harness-runtime|validate|$TEST_CWD/agents.yaml"
fi

if t new_spec_writes_template_with_name; then
  run_pane task "2\nx-agent\n\nn\n" MARS_TASK=new-spec
  assert_status 0
  assert_file_has "$TEST_CWD/agents.yaml" "name: x-agent"
  assert_file_has "$TEST_CWD/agents.yaml" "agent: codex"
  if grep -q "# template:" "$TEST_CWD/agents.yaml"; then fail "template marker leaked"; else ok; fi
  assert_eq "$(cat "$HERDR_PLUGIN_STATE_DIR/last-spec")" "$TEST_CWD/agents.yaml"
fi

if t new_spec_refuses_overwrite_without_confirm; then
  printf 'keep\n' >"$TEST_CWD/agents.yaml"
  run_pane task "1\nx\n\nn\n" MARS_TASK=new-spec
  assert_status 1
  assert_eq "$(cat "$TEST_CWD/agents.yaml")" "keep"
fi

if t dashboard_pause_then_quit; then
  run_pane task "1\n4\n6\n" MARS_TASK=dashboard
  assert_status 0
  assert_log "doctl|harness-runtime|pause|01a0-alpha"
  assert_out "+ start a new session"
fi

if t dashboard_attach_exits_after_opening_pane; then
  run_pane task "2\n1\n" MARS_TASK=dashboard
  assert_status 0
  assert_log "--entrypoint|attach|"
  assert_log "MARS_SESSION=01a0-beta"
fi

if t dashboard_proxy_uses_preselected_session; then
  run_pane task "1\n7\n\n" MARS_TASK=dashboard
  assert_status 0
  assert_log "\"--session\",\"01a0-alpha\""
fi

if t doctor_passes_with_fakes; then
  run_pane task "" MARS_TASK=doctor
  assert_status 0
  assert_out "doctl with Managed Agents commands"
  assert_out "0 failed"
fi

if t doctor_fails_without_beta_doctl; then
  MARS_DOCTL_BIN=/nonexistent/doctl run_pane task "" MARS_TASK=doctor
  assert_status 1
  assert_out "No doctl build with the Managed Agents commands"
fi

if t tasks_fail_cleanly_without_beta_doctl; then
  MARS_DOCTL_BIN=/nonexistent/doctl run_pane task "" MARS_TASK=attach
  assert_status 1
  assert_out "No doctl build with the Managed Agents commands"
fi

if t doctl_falls_back_to_legacy_group; then
  FAKE_DOCTL_GROUP=open-harness-runtime run_pane task "" MARS_TASK=pause
  assert_status 0
  assert_log "doctl|open-harness-runtime|pause|01a0-alpha"
fi

if t pane_run_executes_args_and_holds; then
  run_pane run "\n" MARS_RUN_ARGS='["logs","abc"]' MARS_RUN_HOLD=1 MARS_NO_HOLD=0
  assert_status 0
  assert_log "doctl|harness-runtime|logs|abc"
  assert_out "Done. Press Enter to close."
fi

if t pane_run_reports_failure_status; then
  FAKE_DOCTL_EXIT=3 run_pane run "\n" MARS_RUN_ARGS='["logs","abc"]' MARS_RUN_HOLD=0
  assert_status 3
  assert_out "Exited with status 3"
fi

if t split_panes_never_override_cwd; then
  run_pane task "1\n" MARS_TASK=attach
  assert_status 0
  assert_not_log "|--cwd|"
  assert_log "--env|MARS_CWD=$TEST_CWD"
fi

if t pane_run_changes_into_mars_cwd; then
  run_pane run "" MARS_RUN_ARGS='["logs","abc"]' MARS_RUN_HOLD=0 MARS_CWD="$TEST_CWD"
  assert_status 0
  assert_log "doctl-cwd|$TEST_CWD"
  run_pane run "" MARS_RUN_ARGS='["logs","abc"]' MARS_RUN_HOLD=0 MARS_CWD="$TEST_CWD/missing"
  assert_status 0
  assert_log "doctl-cwd|$ROOT"
fi

if t pane_attach_runs_doctl_attach; then
  run_pane attach "" MARS_SESSION=01a0-alpha MARS_SESSION_NAME=alpha
  assert_status 0
  assert_log "doctl|harness-runtime|attach|01a0-alpha"
  assert_out "attached to alpha"
fi

if t pane_run_holds_when_doctl_missing; then
  MARS_DOCTL_BIN=/nonexistent/doctl MARS_NO_HOLD=0 run_pane run "\n" MARS_RUN_ARGS='["logs","abc"]'
  assert_status 1
  assert_out "No doctl build with the Managed Agents commands"
  assert_out "Exited with status 1. Press Enter to close."
fi

if t path_is_augmented_with_user_bin_dirs; then
  mkdir -p "$HOME/.local/bin"
  cp "$FAKES/doctl" "$HOME/.local/bin/doctl-beta"
  PATH="/usr/bin:/bin" MARS_FAKE_SESSIONS="$ROOT/tests/fixtures/sessions.json" run_pane task "" MARS_TASK=pause
  assert_status 0
  assert_log "doctl|harness-runtime|pause|01a0-alpha"
  rm -f "$HOME/.local/bin/doctl-beta"
fi

if t agent_name_sanitizing; then
  # shellcheck source=lib/common.sh
  source "$ROOT/lib/common.sh"
  assert_eq "$(MARS_AGENT_NAME_PREFIX=mars mars_agent_name 'My Session!! Name')" "mars-my-session-name"
  assert_eq "$(MARS_AGENT_NAME_PREFIX=mars mars_agent_name 'a-very-long-session-name-that-exceeds-limits')" "mars-a-very-long-session-name-th"
  assert_eq "$(MARS_AGENT_NAME_PREFIX=mars mars_agent_name '---')" "mars"
fi

if t spec_name_parsing; then
  # shellcheck source=lib/doctl.sh
  source "$ROOT/lib/common.sh"
  source "$ROOT/lib/doctl.sh"
  printf 'name: "quoted name"  # comment\nagent: codex\n' >"$TEST_CWD/a.yaml"
  printf "name: 'single'\nagent: codex\n" >"$TEST_CWD/b.yaml"
  printf 'agent: codex\n' >"$TEST_CWD/c.yaml"
  assert_eq "$(mars_spec_name "$TEST_CWD/a.yaml")" "quoted name"
  assert_eq "$(mars_spec_name "$TEST_CWD/b.yaml")" "single"
  assert_eq "$(mars_spec_name "$TEST_CWD/c.yaml")" ""
fi

# ---------------------------------------------------------------- summary

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
