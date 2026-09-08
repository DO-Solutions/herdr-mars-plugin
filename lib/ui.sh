# shellcheck shell=bash
# Terminal UI for the popup: pickers, prompts, confirmations.
# Prompts and menus go to stderr; chosen values go to stdout.
# User input is read from MARS_INPUT_FD (fd 3, the original stdin saved by bin/mars)
# because pickers receive their option list on stdin.

MARS_INPUT_FD="${MARS_INPUT_FD:-3}"

# ui_read <read-args...>: read one line of user input.
ui_read() {
  read -r "$@" <&"$MARS_INPUT_FD"
}

ui_use_fzf() {
  case "${MARS_USE_FZF:-auto}" in
    0 | false | no | off) return 1 ;;
  esac
  mars_have fzf && [[ -t 2 ]]
}

ui_header() {
  printf '\n\033[1m%s\033[0m\n' "$*" >&2
}

ui_info() {
  printf '%s\n' "$*" >&2
}

ui_error() {
  printf '\033[31m%s\033[0m\n' "$*" >&2
}

# ui_pick <header> <<< "display<TAB>value" lines. Prints the chosen value, or fails when cancelled.
ui_pick() {
  local header="$1" lines choice
  lines="$(cat)"
  [[ -n "$lines" ]] || return 1
  if [[ "$(printf '%s\n' "$lines" | wc -l | tr -d ' ')" == "1" && "${MARS_PICK_AUTOSELECT_SINGLE:-1}" == "1" ]]; then
    printf '%s\n' "${lines#*$'\t'}"
    return 0
  fi
  if ui_use_fzf; then
    choice="$(printf '%s\n' "$lines" | fzf --delimiter=$'\t' --with-nth=1 --header="$header" --prompt='> ' --layout=reverse --height=100% --no-multi --exit-0)" || return 1
    printf '%s\n' "${choice#*$'\t'}"
    return 0
  fi
  local -a displays=() values=()
  local line n
  while IFS= read -r line; do
    displays+=("${line%%$'\t'*}")
    values+=("${line#*$'\t'}")
  done <<<"$lines"
  ui_header "$header"
  for n in "${!displays[@]}"; do
    printf '  %2d) %s\n' "$((n + 1))" "${displays[$n]}" >&2
  done
  while true; do
    ui_read -p "Choose [1-${#displays[@]}], or q to cancel: " choice || return 1
    case "$choice" in
      q | Q | "") return 1 ;;
    esac
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#displays[@]})); then
      printf '%s\n' "${values[$((choice - 1))]}"
      return 0
    fi
    ui_error "Invalid choice."
  done
}

# ui_ask <prompt> [default] -> answer (default when empty).
ui_ask() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    ui_read -p "$prompt [$default]: " answer || return 1
  else
    ui_read -p "$prompt: " answer || return 1
  fi
  printf '%s\n' "${answer:-$default}"
}

# ui_confirm <question> -> 0 for yes. MARS_ASSUME_YES=1 skips the prompt.
ui_confirm() {
  mars_flag_on "${MARS_ASSUME_YES:-0}" && return 0
  local answer
  ui_read -p "$1 [y/N]: " answer || return 1
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Keep the popup open until the user has read the output.
ui_hold() {
  mars_flag_on "${MARS_NO_HOLD:-0}" && return 0
  printf '\nPress Enter to close.' >&2
  ui_read _ || true
}
