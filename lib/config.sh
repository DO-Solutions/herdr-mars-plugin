# shellcheck shell=bash
# Configuration: .env loading and defaults.
#
# Precedence: process environment > HERDR_PLUGIN_CONFIG_DIR/.env > plugin-root .env (dev only) > defaults.

mars_load_env_file() {
  local file="$1" line key value
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#export }"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -n "${!key+x}" ]] && continue
    export "$key=$value"
  done <"$file"
}

# Herdr launches plugin commands with a minimal PATH, so user-level tool
# directories (doctl-beta, fzf, codex) are appended when they exist.
mars_augment_path() {
  local dir
  local -a dirs=()
  local IFS=':'
  # shellcheck disable=SC2206 # intentional split of a colon-separated list
  dirs=(${MARS_PATH_EXTRA:-})
  unset IFS
  dirs+=("$HOME/.local/bin" "$HOME/bin" "$HOME/.fzf/bin" "$HOME/.cargo/bin" "$HOME/.npm-global/bin"
    "$HOME/.bun/bin" "/opt/homebrew/bin" "/usr/local/bin" "/snap/bin")
  for dir in "${dirs[@]}"; do
    [[ -n "$dir" && -d "$dir" ]] || continue
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) PATH="$PATH:$dir" ;;
    esac
  done
  export PATH
}

mars_load_config() {
  local config_dir
  config_dir="$(mars_config_dir)"
  mars_load_env_file "${MARS_ENV_FILE:-$config_dir/.env}"
  mars_load_env_file "$MARS_ROOT/.env"
  mars_augment_path

  : "${MARS_DOCTL_BIN:=}"
  : "${MARS_SPEC_DIRS:=$config_dir/specs}"
  : "${MARS_PROXY_PORT:=1144}"
  : "${MARS_PROXY_TYPE:=codex}"
  : "${MARS_PROXY_AUTOSTART_AGENT:=1}"
  : "${MARS_SPLIT_DIRECTION:=auto}"
  : "${MARS_NOTIFY:=1}"
  : "${MARS_USE_FZF:=auto}"
  : "${MARS_AGENT_NAME_PREFIX:=mars}"
  : "${MARS_LIST_PAGE_SIZE:=100}"
  export MARS_DOCTL_BIN MARS_SPEC_DIRS MARS_PROXY_PORT MARS_PROXY_TYPE MARS_PROXY_AUTOSTART_AGENT
  export MARS_SPLIT_DIRECTION MARS_NOTIFY MARS_USE_FZF MARS_AGENT_NAME_PREFIX MARS_LIST_PAGE_SIZE
}

mars_flag_on() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    0 | false | no | off | "") return 1 ;;
    *) return 0 ;;
  esac
}
