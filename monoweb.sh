#!/usr/bin/env bash
# =============================================================================
#   __  __                __        __      _
#  |  \/  | ___  _ __   ___\ \      / /__| |__
#  | |\/| |/ _ \| '_ \ / _ \\ \ /\ / / _ \ '_ \
#  | |  | | (_) | | | | (_) |\ V  V /  __/ |_) |
#  |_|  |_|\___/|_| |_|\___/  \_/\_/ \___|_.__/
#
#   MonoWeb Executor  ·  v2.0.0
#   Made by prime.dev1
#
#   One numbered menu to install, run, restart, update and delete MonoWeb
#   (https://github.com/Srccodeusr/MonoWeb), plus a Cloudflare Tunnel helper.
#
#   Optional environment overrides:
#     MONOWEB_REPO    git URL to clone            (default: the MonoWeb repo)
#     MONOWEB_BRANCH  branch to clone             (default: repo default)
#     MONOWEB_DIR     install directory           (default: ~/monoweb)
#     MONOWEB_HOME    logs / pids / state dir     (default: ~/.monoweb)
# =============================================================================

set -uo pipefail
shopt -s extglob

SCRIPT_NAME="MonoWeb Executor"
SCRIPT_VERSION="2.0.0"
SCRIPT_CREDIT="prime.dev1"

# -----------------------------------------------------------------------------
# Bootstrap
# -----------------------------------------------------------------------------
: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
: "${HOME:=/root}"
export HOME

# `curl … | bash` leaves stdin on the pipe — reattach the terminal so prompts work.
if [[ ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then exec </dev/tty; fi

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
REPO_URL="${MONOWEB_REPO:-https://github.com/Srccodeusr/MonoWeb.git}"
REPO_BRANCH="${MONOWEB_BRANCH:-}"
PROJECT_DIR="${MONOWEB_DIR:-$HOME/monoweb}"
PROJECT_DIR="${PROJECT_DIR%/}"

PANEL_PORT=3000            # hard-coded in MonoWeb's server.ts
NODE_MIN_MAJOR=20          # Vite 6 + @vitejs/plugin-react 5 need Node 20.19+
NODE_INSTALL_MAJOR=22      # LTS line installed when Node is missing/too old

# State lives OUTSIDE the project dir so re-cloning/deleting the panel never
# wipes logs, pid files or tunnel settings by accident.
STATE_DIR="${MONOWEB_HOME:-$HOME/.monoweb}"
LOG_DIR="$STATE_DIR/logs"
RUN_DIR="$STATE_DIR/run"
BACKUP_DIR="${MONOWEB_BACKUP_DIR:-$HOME/monoweb-backups}"

INSTALL_LOG="$LOG_DIR/install.log"
BUILD_LOG="$LOG_DIR/build.log"
PANEL_LOG="$LOG_DIR/panel.log"
TUNNEL_LOG="$LOG_DIR/tunnel.log"

PANEL_PID_FILE="$RUN_DIR/panel.pid"
PANEL_MODE_FILE="$RUN_DIR/panel.mode"
PANEL_START_FILE="$RUN_DIR/panel.started"
LAST_MODE_FILE="$RUN_DIR/last.mode"
BUILD_STAMP_FILE="$RUN_DIR/build.stamp"
TUNNEL_PID_FILE="$RUN_DIR/tunnel.pid"
TUNNEL_CONF_FILE="$RUN_DIR/tunnel.conf"
TUNNEL_TOKEN_FILE="$RUN_DIR/tunnel.token"

CLOUDFLARED_BIN="$HOME/.local/bin/cloudflared"

[[ -d "$HOME/.local/node/bin" ]] && PATH="$HOME/.local/node/bin:$PATH"
PATH="$PATH:$HOME/.local/bin"
export PATH

SETSID="$(command -v setsid 2>/dev/null || true)"

ANSWER=""; MODE=""; SKIP_PAUSE=0; SPIN_PID=""; BACKUP_LAST=""
STEP_TOTAL=0; STEP_N=0
CFG_EMAIL=""; CFG_URL=""; CFG_PASS_SHOWN=""
PRIV=()

# -----------------------------------------------------------------------------
# UI toolkit — colours, glyphs, boxes, spinner
# -----------------------------------------------------------------------------
ui_init() {
  UI_TTY=0; [[ -t 1 ]] && UI_TTY=1
  local ncolors=0
  if (( UI_TTY )) && [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    ncolors=$(tput colors 2>/dev/null || echo 8)
    [[ $ncolors =~ ^[0-9]+$ ]] || ncolors=8
  fi

  UI_UTF8=0
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UI_UTF8=1 ;;
  esac
  if (( ! UI_UTF8 )) && locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$'; then
    export LC_ALL=C.UTF-8
    UI_UTF8=1
  fi

  if (( ncolors >= 256 )); then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_ACC=$'\033[38;5;51m';  C_ACC2=$'\033[38;5;141m'
    C_OK=$'\033[38;5;84m';   C_WARN=$'\033[38;5;221m'; C_ERR=$'\033[38;5;203m'
    C_MUTE=$'\033[38;5;245m'; C_TXT=$'\033[38;5;255m'
    GRAD=($'\033[38;5;51m' $'\033[38;5;45m' $'\033[38;5;39m' $'\033[38;5;63m' $'\033[38;5;99m')
  elif (( ncolors >= 8 )); then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_ACC=$'\033[36m'; C_ACC2=$'\033[35m'
    C_OK=$'\033[32m';  C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
    C_MUTE=$'\033[2m'; C_TXT=$'\033[0m'
    GRAD=("$C_ACC" "$C_ACC" "$C_ACC" "$C_ACC2" "$C_ACC2")
  else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_ACC=''; C_ACC2=''
    C_OK=''; C_WARN=''; C_ERR=''; C_MUTE=''; C_TXT=''
    GRAD=('' '' '' '' '')
  fi

  if (( UI_UTF8 )); then
    G_TL='╭'; G_TR='╮'; G_BL='╰'; G_BR='╯'; G_H='─'; G_V='│'; G_ML='├'; G_MR='┤'
    G_OK='✔'; G_ERR='✖'; G_WARN='!'; G_ARROW='›'; G_DOT='●'; G_RING='○'
    G_BAR='▌'; G_ELL='…'; G_PROMPT='❯'; G_BUL='•'
    SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  else
    G_TL='+'; G_TR='+'; G_BL='+'; G_BR='+'; G_H='-'; G_V='|'; G_ML='+'; G_MR='+'
    G_OK='+'; G_ERR='x'; G_WARN='!'; G_ARROW='>'; G_DOT='*'; G_RING='o'
    G_BAR='|'; G_ELL='~'; G_PROMPT='>'; G_BUL='*'
    SPIN_FRAMES=('|' '/' '-' '\')
  fi
  ui_size
}

rep() { local s="" i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }

ui_size() {
  local cols=80
  (( UI_TTY )) && cols=$(tput cols 2>/dev/null || echo 80)
  [[ $cols =~ ^[0-9]+$ ]] || cols=80
  UI_COLS=$cols
  UI_W=$(( cols - 4 ))
  (( UI_W > 68 )) && UI_W=68
  (( UI_W < 40 )) && UI_W=40
  HLINE=$(rep "$G_H" "$UI_W")
}

ui_clear() { (( UI_TTY )) && printf '\033[3J\033[H\033[2J'; return 0; }

strip_ansi() { printf '%s' "${1//$'\033'\[*([0-9;?])[a-zA-Z]/}"; }

asc() { # on non-UTF-8 terminals swap the few typographic characters we use
  local t="$*"
  if (( ! UI_UTF8 )); then t=${t//—/-}; t=${t//·/|}; t=${t//…/~}; t=${t//→/->}; fi
  printf '%s' "$t"
}

fit() { # fit "text" max  — truncate plain text with an ellipsis
  local s="$1" max="$2"
  if (( ${#s} > max )); then
    if (( max > 1 )); then printf '%s%s' "${s:0:max-1}" "$G_ELL"; else printf '%s' "${s:0:max}"; fi
  else
    printf '%s' "$s"
  fi
}

short_path() { local p="$1" t='~'; printf '%s' "${p/#$HOME/$t}"; }

box_top() { printf '%s%s%s%s%s\n' "$C_MUTE" "$G_TL" "$HLINE" "$G_TR" "$C_RESET"; }
box_bot() { printf '%s%s%s%s%s\n' "$C_MUTE" "$G_BL" "$HLINE" "$G_BR" "$C_RESET"; }
box_sep() { printf '%s%s%s%s%s\n' "$C_MUTE" "$G_ML" "$HLINE" "$G_MR" "$C_RESET"; }
box_row() { # box_row "text with ansi"  — one padded row inside a box
  local txt vis pad
  txt=$(asc "$1")
  vis=$(strip_ansi "$txt")
  pad=$(( UI_W - 2 - ${#vis} )); (( pad < 0 )) && pad=0
  printf '%s%s%s %s%*s %s%s%s\n' "$C_MUTE" "$G_V" "$C_RESET" "$txt" "$pad" "" "$C_MUTE" "$G_V" "$C_RESET"
}
box_title() { box_row "${C_BOLD}${C_ACC}$1${C_RESET}"; }
box_kv() { # box_kv "Label" "plain value" [colour]
  local room=$(( UI_W - 2 - 12 ))
  box_row "$(printf '%s%-11s%s %s%s%s' "$C_MUTE" "$1" "$C_RESET" "${3:-$C_TXT}" "$(fit "$2" "$room")" "$C_RESET")"
}
menu_item() { # menu_item num "Label" "description" [colour]
  local n="$1" label="$2" desc="${3:-}" col="${4:-$C_ACC}" room=$(( UI_W - 2 - 5 - 19 ))
  (( room < 10 )) && desc=""
  box_row "$(printf '%s%s%s   %s%-18s%s %s%s%s' "$col$C_BOLD" "$n" "$C_RESET" "$C_TXT$C_BOLD" "$label" "$C_RESET" "$C_MUTE" "$(fit "$desc" "$room")" "$C_RESET")"
}
menu_group() { box_row "${C_ACC2}${C_BOLD}$1${C_RESET}"; }
box_stat() { # box_stat "Label" "glyph" "main text" "muted tail" colour — fitted status row
  local room=$(( UI_W - 2 - 10 - 2 )) main tail
  main=$(fit "$3" "$room")
  tail=""
  if [[ -n ${4:-} ]] && (( ${#main} < room - 2 )); then tail=" $(fit "$4" $(( room - ${#main} - 1 )))"; fi
  box_row "$(printf '%s%-9s%s %s%s %s%s%s%s%s' "$C_MUTE" "$1" "$C_RESET" "$5" "$2" "$main" "$C_RESET" "$C_MUTE" "$tail" "$C_RESET")"
}

ok()   { printf '  %s%s%s %s\n' "$C_OK"   "$G_OK"    "$C_RESET" "$(asc "$*")"; }
err()  { printf '  %s%s%s %s\n' "$C_ERR"  "$G_ERR"   "$C_RESET" "$(asc "$*")"; }
warn() { printf '  %s%s%s %s\n' "$C_WARN" "$G_WARN"  "$C_RESET" "$(asc "$*")"; }
info() { printf '  %s%s%s %s\n' "$C_ACC"  "$G_ARROW" "$C_RESET" "$(asc "$*")"; }
note() { printf '  %s%s%s\n' "$C_MUTE" "$(asc "$*")" "$C_RESET"; }

section() {
  printf '\n  %s%s %s%s\n' "$C_ACC$C_BOLD" "$G_BAR" "$1" "$C_RESET"
  printf '  %s%s%s\n' "$C_MUTE" "$(rep "$G_H" $(( UI_W - 2 )))" "$C_RESET"
}

step() {
  STEP_N=$(( STEP_N + 1 ))
  printf '\n  %s[%d/%d]%s %s%s%s\n' "$C_ACC2$C_BOLD" "$STEP_N" "$STEP_TOTAL" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

banner() {
  ui_clear; ui_size
  printf '\n'
  local i=0 l
  if (( UI_COLS >= 54 )); then
    for l in "${LOGO[@]}"; do
      printf '  %s%s%s\n' "${GRAD[i]:-}" "$l" "$C_RESET"
      i=$(( i + 1 ))
    done
    printf '  %s%s%s%s  %s' "$C_BOLD" "$C_TXT" "Executor" "$C_RESET" "$C_MUTE"
    asc "·  v$SCRIPT_VERSION  ·  made by $SCRIPT_CREDIT"; printf '%s\n' "$C_RESET"
  else
    printf '  %s%sMonoWeb%s %sExecutor%s\n' "${GRAD[0]:-}" "$C_BOLD" "$C_RESET" "$C_TXT" "$C_RESET"
    printf '  %sv%s | made by %s%s\n' "$C_MUTE" "$SCRIPT_VERSION" "$SCRIPT_CREDIT" "$C_RESET"
  fi
  printf '  %s%s%s\n' "$C_MUTE" "$(fit "${REPO_URL%.git}" $(( UI_W - 2 )))" "$C_RESET"
}

mapfile -t LOGO <<'EOF'
  __  __                   __        __   _
 |  \/  | ___  _ __   ___  \ \      / /__| |__
 | |\/| |/ _ \| '_ \ / _ \  \ \ /\ / / _ \ '_ \
 | |  | | (_) | | | | (_) |  \ V  V /  __/ |_) |
 |_|  |_|\___/|_| |_|\___/    \_/\_/ \___|_.__/
EOF

# -----------------------------------------------------------------------------
# Prompts
# -----------------------------------------------------------------------------
bye() {
  printf '\n\n  %s%s%s  %s%s v%s - made by %s%s\n\n' "$C_ACC" "$G_DOT" "$C_RESET" "$C_MUTE" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$SCRIPT_CREDIT" "$C_RESET"
  exit 0
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

ask() { # ask "Prompt" [default]  →  $ANSWER
  local text="$1" def="${2:-}" hint=""
  [[ -n $def ]] && hint=" ${C_MUTE}[${def}]${C_RESET}"
  printf '  %s%s%s %s%s %s%s%s ' "$C_ACC" "$G_ARROW" "$C_RESET" "$text" "$hint" "$C_ACC" "$G_PROMPT" "$C_RESET"
  IFS= read -r ANSWER || bye
  ANSWER=$(trim "$ANSWER")
  ANSWER="${ANSWER:-$def}"
}

ask_secret() { # ask_secret "Prompt"  →  $ANSWER (hidden input, not trimmed)
  printf '  %s%s%s %s %s%s%s ' "$C_ACC" "$G_ARROW" "$C_RESET" "$1" "$C_ACC" "$G_PROMPT" "$C_RESET"
  IFS= read -rs ANSWER || { printf '\n'; bye; }
  printf '\n'
}

confirm() { # confirm "Question" [y|n]
  local q="$1" def="${2:-n}" hint reply
  [[ $def == y ]] && hint="Y/n" || hint="y/N"
  printf '  %s?%s %s %s[%s]%s ' "$C_WARN$C_BOLD" "$C_RESET" "$q" "$C_MUTE" "$hint" "$C_RESET"
  IFS= read -r reply || bye
  reply=$(trim "$reply"); reply="${reply:-$def}"
  [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

pause() {
  printf '\n  %sPress Enter to return to the menu%s%s ' "$C_MUTE" "$G_ELL" "$C_RESET"
  IFS= read -r _ || bye
}

# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

ensure_dirs() { mkdir -p "$LOG_DIR" "$RUN_DIR" "$HOME/.local/bin" 2>/dev/null || true; chmod 700 "$STATE_DIR" "$RUN_DIR" 2>/dev/null || true; }

rand_hex()   { od -An -N"${1:-32}" -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'; }
rand_alnum() { { head -c 2048 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c "${1:-20}"; } 2>/dev/null || true; }

rotate_log() { # rotate a log once it passes ~5 MB
  local f="$1" size
  [[ -f $f ]] || return 0
  size=$(wc -c <"$f" 2>/dev/null || echo 0)
  (( size > 5242880 )) && mv -f "$f" "$f.1"
  return 0
}

fmt_dur() {
  local s=$1 d h m
  d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if   (( d )); then printf '%dd %dh' "$d" "$h"
  elif (( h )); then printf '%dh %dm' "$h" "$m"
  elif (( m )); then printf '%dm %ds' "$m" $(( s % 60 ))
  else printf '%ds' "$s"; fi
}

show_log_tail() { # show_log_tail file [lines]
  local f="$1" n="${2:-12}" l
  [[ -s $f ]] || return 0
  printf '  %s%s last %d lines of %s %s%s\n' "$C_MUTE" "$G_H$G_H" "$n" "$(short_path "$f")" "$G_H$G_H" "$C_RESET"
  tail -n "$n" "$f" 2>/dev/null | while IFS= read -r l; do
    printf '    %s%s%s\n' "$C_MUTE" "$(fit "$l" $(( UI_W - 4 )))" "$C_RESET"
  done
}

follow_file() {
  local f="$1"
  [[ -f $f ]] || { warn "No log yet: $(short_path "$f")"; return 0; }
  note "Following $(basename "$f") — press Ctrl+C to return to the menu."
  printf '\n'
  trap ':' INT
  tail -n 25 -f "$f"
  trap on_int INT
  printf '\n'
}

# -----------------------------------------------------------------------------
# Process management
# -----------------------------------------------------------------------------
children_of() {
  local target="$1" f rest pid ppid
  if [[ -r /proc/self/stat ]]; then
    for f in /proc/[0-9]*/stat; do
      [[ -r $f ]] || continue
      rest=$(<"$f") || continue
      rest=${rest##*) }
      read -r _ ppid _ <<<"$rest"
      if [[ ${ppid:-} == "$target" ]]; then pid=${f#/proc/}; printf '%s\n' "${pid%/stat}"; fi
    done
  elif have pgrep; then
    pgrep -P "$target"
  fi
} 2>/dev/null

kill_tree() { # kill_tree pid [signal]  — children first, then the process
  local pid="$1" sig="${2:-TERM}" c
  for c in $(children_of "$pid"); do kill_tree "$c" "$sig"; done
  kill "-$sig" "$pid" 2>/dev/null || true
}

proc_alive() { # proc_alive pidfile
  local p; p=$(cat "$1" 2>/dev/null) || return 1
  [[ $p =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null
}

stop_process() { # stop_process pidfile
  local pf="$1" pid i
  pid=$(cat "$pf" 2>/dev/null) || return 0
  if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    kill_tree "$pid" TERM
    for ((i = 0; i < 40; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    if kill -0 "$pid" 2>/dev/null; then kill_tree "$pid" KILL; sleep 0.5; fi
  fi
  rm -f "$pf"
}

spawn_bg() { # spawn_bg pidfile logfile cmd args…  — detached, survives this script
  local pidfile="$1" log="$2" i; shift 2
  rm -f "$pidfile"
  ${SETSID:+"$SETSID"} nohup bash -c 'echo $$ >"$1"; shift; exec "$@"' _ "$pidfile" "$@" </dev/null >>"$log" 2>&1 &
  for ((i = 0; i < 30; i++)); do [[ -s $pidfile ]] && break; sleep 0.1; done
}

spin_run() { # spin_run "label" logfile workdir cmd args…
  local label="$1" log="$2" dir="$3"; shift 3
  local start=$SECONDS rc=0 i=0 n=${#SPIN_FRAMES[@]} secs
  mkdir -p "$(dirname "$log")" 2>/dev/null
  printf '\n----- [%s] %s -----\n' "$(date '+%F %T')" "$label" >>"$log" 2>/dev/null
  ${SETSID:+"$SETSID"} bash -c 'cd "$1" || exit 1; shift; exec "$@"' _ "$dir" "$@" </dev/null >>"$log" 2>&1 &
  SPIN_PID=$!
  if (( UI_TTY )); then
    printf '\033[?25l'
    while kill -0 "$SPIN_PID" 2>/dev/null; do
      secs=$(( SECONDS - start ))
      printf '\r  %s%s%s %s %s(%ds)%s\033[K' "$C_ACC" "${SPIN_FRAMES[i % n]}" "$C_RESET" "$label" "$C_MUTE" "$secs" "$C_RESET"
      i=$(( i + 1 )); sleep 0.1
    done
    printf '\r\033[K\033[?25h'
  else
    printf '  ... %s\n' "$label"
  fi
  wait "$SPIN_PID"; rc=$?
  SPIN_PID=""
  secs=$(( SECONDS - start ))
  if (( rc == 0 )); then
    printf '  %s%s%s %s %s(%ds)%s\n' "$C_OK" "$G_OK" "$C_RESET" "$label" "$C_MUTE" "$secs" "$C_RESET"
  else
    printf '  %s%s%s %s %s(failed · exit %d)%s\n' "$C_ERR" "$G_ERR" "$C_RESET" "$label" "$C_MUTE" "$rc" "$C_RESET"
    show_log_tail "$log" 14
  fi
  return "$rc"
}

wait_spin() { # wait_spin "label" timeout check_fn → 0 ready · 1 process died · 2 timed out
  local label="$1" timeout="$2" fn="$3" start=$SECONDS i=0 n=${#SPIN_FRAMES[@]} rc result=2
  (( UI_TTY )) && printf '\033[?25l'
  while (( SECONDS - start < timeout )); do
    "$fn"; rc=$?
    if   (( rc == 0 )); then result=0; break
    elif (( rc == 2 )); then result=1; break; fi
    if (( UI_TTY )); then
      printf '\r  %s%s%s %s %s(%ds)%s\033[K' "$C_ACC" "${SPIN_FRAMES[i % n]}" "$C_RESET" "$label" "$C_MUTE" $(( SECONDS - start )) "$C_RESET"
    fi
    i=$(( i + 1 )); sleep 0.15
  done
  (( UI_TTY )) && printf '\r\033[K\033[?25h'
  return "$result"
}

cleanup() {
  if [[ -n "${SPIN_PID:-}" ]]; then kill_tree "$SPIN_PID" TERM; SPIN_PID=""; fi
  (( ${UI_TTY:-0} )) && printf '\033[?25h'
  return 0
}
on_int() { cleanup; printf '\n'; warn "Interrupted — nothing was left half-configured that a re-run can't fix."; exit 130; }

# -----------------------------------------------------------------------------
# State queries
# -----------------------------------------------------------------------------
panel_running()  { proc_alive "$PANEL_PID_FILE"; }
tunnel_running() { proc_alive "$TUNNEL_PID_FILE"; }
panel_pid()      { cat "$PANEL_PID_FILE" 2>/dev/null; }
panel_mode()     { cat "$PANEL_MODE_FILE" 2>/dev/null || printf '?'; }
panel_uptime() {
  local st; st=$(cat "$PANEL_START_FILE" 2>/dev/null) || return 0
  [[ $st =~ ^[0-9]+$ ]] && fmt_dur $(( $(date +%s) - st ))
}

is_installed()   { [[ -f $PROJECT_DIR/package.json && -f $PROJECT_DIR/server.ts ]]; }
deps_installed() { [[ -d $PROJECT_DIR/node_modules ]]; }
is_git()         { [[ -d $PROJECT_DIR/.git ]]; }
git_rev()        { git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || printf -- '-'; }
git_full_rev()   { git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || printf 'nogit'; }

port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/${PANEL_PORT}") 2>/dev/null; }
health_ok() {
  if have curl; then curl -fsS -m 2 "http://127.0.0.1:${PANEL_PORT}/api/health" >/dev/null 2>&1
  else port_in_use; fi
}

server_ip() { have hostname && hostname -I 2>/dev/null | awk '{print $1}'; }

# -----------------------------------------------------------------------------
# .env handling  (parsed by hand — never `source`d, so any password is safe)
# -----------------------------------------------------------------------------
unquote_env() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  case "$v" in
    \"*) v="${v#\"}"; v="${v%%\"*}" ;;
    \'*) v="${v#\'}"; v="${v%%\'*}" ;;
    \`*) v="${v#\`}"; v="${v%%\`*}" ;;
    *)   v="${v%%[[:space:]]#*}"; v="${v%"${v##*[![:space:]]}"}" ;;
  esac
  printf '%s' "$v"
}

get_env() { # get_env KEY [file]
  local key="$1" file="${2:-$PROJECT_DIR/.env}" line val=""
  [[ -f $file ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line%$'\r'}"
    [[ $line =~ ^[[:space:]]*(export[[:space:]]+)?${key}=(.*)$ ]] && val="${BASH_REMATCH[2]}"
  done <"$file"
  unquote_env "$val"
}

load_env_file() { # export every KEY=VALUE from a .env into the current shell
  local file="$1" line
  [[ -f $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line="${line%$'\r'}"
    [[ $line =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    export "${BASH_REMATCH[2]}=$(unquote_env "${BASH_REMATCH[3]}")"
  done <"$file"
}

env_quote() { # pick a quoting style dotenv can parse for this value
  local v="$1"
  [[ $v == *$'\n'* ]] && return 1
  if   [[ $v != *\"* && $v != *\\* ]]; then printf '"%s"' "$v"
  elif [[ $v != *\'* ]];               then printf "'%s'" "$v"
  elif [[ $v != *'`'* ]];              then printf '`%s`' "$v"
  else return 1; fi
}

set_env() { # set_env KEY VALUE [file]  — replace the line or append it
  local key="$1" val="$2" file="${3:-$PROJECT_DIR/.env}" q tmp
  q=$(env_quote "$val") || { err "Value for $key has characters that can't be stored safely in .env."; return 1; }
  tmp=$(mktemp) || return 1
  touch "$file"
  if grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file"; then
    ENV_KEY="$key" ENV_LINE="${key}=${q}" awk '
      BEGIN { k = ENVIRON["ENV_KEY"]; l = ENVIRON["ENV_LINE"]; done = 0 }
      { if (!done && $0 ~ ("^[ \t]*(export[ \t]+)?" k "=")) { print l; done = 1 } else print }
    ' "$file" >"$tmp"
  else
    { cat "$file"; [[ -s $file && $(tail -c1 "$file" | wc -l) -eq 0 ]] && printf '\n'; printf '%s=%s\n' "$key" "$q"; } >"$tmp"
  fi
  cat "$tmp" >"$file"; rm -f "$tmp"
}

del_env() { # del_env KEY [file]
  local key="$1" file="${2:-$PROJECT_DIR/.env}" tmp
  [[ -f $file ]] || return 0
  tmp=$(mktemp) || return 1
  awk -v k="$key" 'BEGIN { p = "^[ \t]*(export[ \t]+)?" k "=" } $0 !~ p' "$file" >"$tmp" && cat "$tmp" >"$file"
  rm -f "$tmp"
}

# -----------------------------------------------------------------------------
# System checks & installers
# -----------------------------------------------------------------------------
can_root() {
  if (( EUID == 0 )); then PRIV=(); return 0; fi
  have sudo || return 1
  if sudo -n true 2>/dev/null; then PRIV=(sudo -n); return 0; fi
  if (( UI_TTY )) && sudo -v 2>/dev/null; then PRIV=(sudo -n); return 0; fi
  return 1
}

pkg_manager() {
  if   have apt-get; then echo apt
  elif have dnf;     then echo dnf
  elif have yum;     then echo yum
  elif have apk;     then echo apk
  else echo none; fi
}

pkg_install() { # pkg_install pkg…
  local pm; pm=$(pkg_manager)
  if [[ $pm == none ]]; then warn "No supported package manager (apt/dnf/yum/apk) — please install: $*"; return 1; fi
  can_root || { warn "Root or sudo access is needed to install: $*"; return 1; }
  case "$pm" in
    apt)
      spin_run "Refreshing package index" "$INSTALL_LOG" / ${PRIV[@]+"${PRIV[@]}"} env DEBIAN_FRONTEND=noninteractive apt-get update -y || true
      spin_run "Installing $*" "$INSTALL_LOG" / ${PRIV[@]+"${PRIV[@]}"} env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
    dnf) spin_run "Installing $*" "$INSTALL_LOG" / ${PRIV[@]+"${PRIV[@]}"} dnf install -y "$@" ;;
    yum) spin_run "Installing $*" "$INSTALL_LOG" / ${PRIV[@]+"${PRIV[@]}"} yum install -y "$@" ;;
    apk) spin_run "Installing $*" "$INSTALL_LOG" / ${PRIV[@]+"${PRIV[@]}"} apk add --no-cache "$@" ;;
  esac
}

preflight() {
  local os arch ram disk
  os=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-$(uname -s)}" )
  arch=$(uname -m)
  ram=$(awk '/^MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  disk=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}')
  ok "$os · $arch · RAM ${ram:-?} MB · ${disk:-?} MB free"
  [[ $(uname -s) == Linux ]] || warn "This script is built for Linux — some steps may not work here."
  if [[ ${ram:-0} =~ ^[0-9]+$ ]] && (( ram > 0 && ram < 900 )); then
    warn "Under 1 GB of RAM: the production build may run out of memory. Adding swap helps."
  fi
  if [[ ${disk:-0} =~ ^[0-9]+$ ]] && (( disk > 0 && disk < 1500 )); then
    warn "Under 1.5 GB of free disk — node_modules and the build need room."
  fi
  return 0
}

ensure_system_packages() {
  local missing=() t
  for t in git curl tar gzip; do have "$t" || missing+=("$t"); done
  if (( ${#missing[@]} == 0 )); then ok "git, curl, tar and gzip are ready"; return 0; fi
  info "Missing: ${missing[*]}"
  pkg_install ca-certificates "${missing[@]}" || { err "Could not install: ${missing[*]}"; return 1; }
  hash -r
  for t in "${missing[@]}"; do have "$t" || { err "$t is still missing after install."; return 1; }; done
  ok "Installed ${missing[*]}"
}

node_major() {
  local v
  have node || { printf 0; return; }
  v=$(node -v 2>/dev/null); v=${v#v}
  printf '%s' "${v%%.*}"
}
node_ok() { local m; m=$(node_major); [[ $m =~ ^[0-9]+$ ]] && (( m >= NODE_MIN_MAJOR )) && have npm; }

install_node() {
  local tarch
  case "$(uname -m)" in
    x86_64|amd64)  tarch=x64 ;;
    aarch64|arm64) tarch=arm64 ;;
    armv7l|armv8l) tarch=armv7l ;;
    *) err "Unsupported CPU architecture: $(uname -m)"; return 1 ;;
  esac

  if [[ -f /etc/alpine-release ]]; then
    pkg_install nodejs npm
    return $?
  fi

  have curl || { err "curl is required to download Node.js."; return 1; }
  local base="https://nodejs.org/dist/latest-v${NODE_INSTALL_MAJOR}.x" tmp line file dir
  tmp=$(mktemp -d) || return 1

  spin_run "Resolving Node.js ${NODE_INSTALL_MAJOR}.x release" "$INSTALL_LOG" "$tmp" curl -fsSL -o SHASUMS256.txt "$base/SHASUMS256.txt" \
    || { rm -rf "$tmp"; return 1; }
  line=$(grep -E " node-v[0-9.]+-linux-${tarch}\.tar\.gz\$" "$tmp/SHASUMS256.txt" | head -n1)
  [[ -n $line ]] || { err "No official Node.js build found for linux-${tarch}."; rm -rf "$tmp"; return 1; }
  file=${line##* }

  spin_run "Downloading $file" "$INSTALL_LOG" "$tmp" curl -fsSL -o "$file" "$base/$file" || { rm -rf "$tmp"; return 1; }

  if have sha256sum; then
    if ( cd "$tmp" && printf '%s\n' "$line" | sha256sum -c - >/dev/null 2>&1 ); then
      ok "Checksum verified (sha256)"
    else
      err "Checksum mismatch — download discarded."; rm -rf "$tmp"; return 1
    fi
  else
    warn "sha256sum not found — skipping checksum verification."
  fi

  spin_run "Extracting Node.js" "$INSTALL_LOG" "$tmp" tar -xzf "$file" || { rm -rf "$tmp"; return 1; }
  dir="$tmp/${file%.tar.gz}"

  if can_root; then
    spin_run "Installing Node.js to /usr/local" "$INSTALL_LOG" "$tmp" \
      ${PRIV[@]+"${PRIV[@]}"} cp -a "$dir/bin" "$dir/include" "$dir/lib" "$dir/share" /usr/local/ \
      || { rm -rf "$tmp"; return 1; }
  else
    rm -rf "$HOME/.local/node"; mkdir -p "$HOME/.local"
    mv "$dir" "$HOME/.local/node" || { rm -rf "$tmp"; return 1; }
    PATH="$HOME/.local/node/bin:$PATH"; export PATH
    ok "Installed Node.js to $(short_path "$HOME/.local/node") (no root needed)"
    note "This script adds it to PATH automatically. For your own shell: export PATH=\"\$HOME/.local/node/bin:\$PATH\""
  fi
  rm -rf "$tmp"
  hash -r
}

ensure_node() {
  if node_ok; then ok "Node.js $(node -v) · npm $(npm -v)"; return 0; fi
  if have node; then warn "Node.js $(node -v) is too old — MonoWeb's toolchain needs v${NODE_MIN_MAJOR}+."
  else warn "Node.js is not installed."; fi
  confirm "Install Node.js ${NODE_INSTALL_MAJOR} (LTS) now?" y || { err "Node.js ${NODE_MIN_MAJOR}+ is required."; return 1; }
  install_node || return 1
  hash -r
  node_ok || { err "Node.js is still missing or too old ($(node -v 2>/dev/null || echo none))."; return 1; }
  ok "Node.js $(node -v) · npm $(npm -v)"
}

# -----------------------------------------------------------------------------
# Repository
# -----------------------------------------------------------------------------
clone_repo() {
  if [[ -e $PROJECT_DIR && -n $(ls -A "$PROJECT_DIR" 2>/dev/null) ]]; then
    if is_installed; then
      if is_git; then ok "Existing checkout found at $(short_path "$PROJECT_DIR") — using it (Update Panel pulls newer code)"
      else warn "Existing MonoWeb files found (not a git checkout) — using them as they are."; fi
      return 0
    fi
    err "$(short_path "$PROJECT_DIR") already exists and doesn't look like MonoWeb."
    note "Set MONOWEB_DIR to a different path, or remove that folder, then try again."
    return 1
  fi
  mkdir -p "$(dirname "$PROJECT_DIR")"
  local args=(clone)
  [[ -n $REPO_BRANCH ]] && args+=(-b "$REPO_BRANCH")
  args+=("$REPO_URL" "$PROJECT_DIR")
  if spin_run "Cloning ${REPO_URL%.git}" "$INSTALL_LOG" "$HOME" env GIT_TERMINAL_PROMPT=0 git "${args[@]}"; then
    return 0
  fi
  note "Check the URL and your network. For a private repo use MONOWEB_REPO='https://<token>@github.com/Srccodeusr/MonoWeb.git'"
  return 1
}

backup_data() { # backup_data label  →  $BACKUP_LAST
  local label="$1" ts out items=() f
  BACKUP_LAST=""
  [[ -d $PROJECT_DIR/data ]] && items+=(data)
  [[ -f $PROJECT_DIR/.env ]] && items+=(.env)
  (( ${#items[@]} )) || { note "Nothing to back up yet (no data/ or .env)."; return 0; }
  ts=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR" 2>/dev/null
  out="$BACKUP_DIR/monoweb-${label}-${ts}.tar.gz"
  if ( umask 077; tar -czf "$out" -C "$PROJECT_DIR" "${items[@]}" ) 2>>"$INSTALL_LOG"; then
    BACKUP_LAST="$out"
    ok "Backup saved → $(short_path "$out")"
    while IFS= read -r f; do rm -f -- "$f"; done < <(ls -1t "$BACKUP_DIR"/monoweb-*.tar.gz 2>/dev/null | tail -n +11)
    return 0
  fi
  err "Backup failed — see $(short_path "$INSTALL_LOG")"
  return 1
}

# -----------------------------------------------------------------------------
# Configuration (.env)
# -----------------------------------------------------------------------------
normalize_url() { # accepts "example.com", "https://example.com/", "localhost:3000"
  local u; u=$(trim "$1"); u="${u%%+(/)}"
  [[ -z $u ]] && return 1
  if [[ $u != *://* ]]; then
    if [[ $u =~ ^(localhost|127\.|10\.|192\.168\.) ]]; then u="http://$u"; else u="https://$u"; fi
  fi
  [[ $u =~ ^https?://[^[:space:]/]+$ ]] || return 1
  printf '%s' "$u"
}

apply_public_url() { # apply_public_url https://example.com
  local url="$1" origins="$1" old_url redirect
  old_url=$(get_env APP_URL)
  redirect=$(get_env DISCORD_REDIRECT_URI)
  [[ $url != "http://localhost:${PANEL_PORT}" ]] && origins+=",http://localhost:${PANEL_PORT}"
  origins+=",http://127.0.0.1:${PANEL_PORT}"
  set_env APP_URL "$url"
  set_env ALLOWED_ORIGINS "$origins"
  if [[ -z $redirect || -z $old_url || $redirect == "${old_url}/api/v1/auth/discord/callback" ]]; then
    set_env DISCORD_REDIRECT_URI "${url}/api/v1/auth/discord/callback"
  fi
  # auth.ts only trusts X-Forwarded-For when this is exactly "true"/"1"
  if [[ $url == http://localhost* || $url == http://127.* ]]; then set_env TRUST_PROXY "false"; else set_env TRUST_PROXY "true"; fi
}

configure_env() {
  local envf="$PROJECT_DIR/.env" template="" email pass pass2 url generated=0 f

  if [[ -f $envf ]]; then
    if confirm "An existing .env was found. Keep it as it is?" y; then
      ok "Keeping your existing configuration"
      return 0
    fi
    cp -p "$envf" "$envf.bak.$(date +%s)" && note "Old config saved as $(basename "$envf").bak.*"
  fi

  for f in "$PROJECT_DIR/.env.example" "$PROJECT_DIR/env.example"; do
    [[ -f $f ]] && { template="$f"; break; }
  done
  ( umask 077; if [[ -n $template ]]; then cp "$template" "$envf"; else : >"$envf"; fi )
  chmod 600 "$envf"

  if [[ -f $PROJECT_DIR/data/db.json ]]; then
    warn "A database already exists — the admin email/password below only apply to a brand-new database."
  fi

  printf '\n'
  note "Set the first super-admin account and your public address."
  printf '\n'

  while true; do
    ask "Admin email"
    email="$ANSWER"
    [[ $email =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && break
    warn "That doesn't look like an email address."
  done

  while true; do
    ask_secret "Admin password (Enter = generate a strong one)"
    pass="$ANSWER"
    if [[ -z $pass ]]; then pass=$(rand_alnum 20); generated=1; break; fi
    if (( ${#pass} < 8 )); then warn "Use at least 8 characters."; continue; fi
    ask_secret "Repeat password"
    pass2="$ANSWER"
    [[ $pass == "$pass2" ]] && break
    warn "Passwords didn't match — try again."
  done

  while true; do
    ask "Public URL of the site" "http://localhost:${PANEL_PORT}"
    if url=$(normalize_url "$ANSWER"); then break; fi
    warn "Enter a URL like https://example.com (no path)."
  done

  set_env JWT_SECRET "$(rand_hex 32)"                                       || return 1
  set_env AETHER_ADMIN_EMAIL "$email"                                       || return 1
  set_env AETHER_ADMIN_PASSWORD "$pass"                                     || return 1
  set_env AETHER_INSTALLATION_ID "inst_$(rand_hex 6)"                       || return 1
  set_env AETHER_INSTALLATION_SECRET "$(rand_hex 32)"                       || return 1
  apply_public_url "$url"                                                   || return 1
  del_env NODE_ENV   # the executor sets NODE_ENV per run mode (dev/prod)
  chmod 600 "$envf"

  CFG_EMAIL="$email"; CFG_URL="$url"; CFG_PASS_SHOWN=""
  (( generated )) && CFG_PASS_SHOWN="$pass"
  ok "Wrote $(short_path "$envf") (permissions 600)"
  return 0
}

# -----------------------------------------------------------------------------
# Dependencies & build
# -----------------------------------------------------------------------------
install_deps() {
  is_installed || { err "No package.json in $(short_path "$PROJECT_DIR") — did the download succeed?"; return 1; }
  if is_git && ! git -C "$PROJECT_DIR" diff --quiet -- package-lock.json 2>/dev/null; then
    git -C "$PROJECT_DIR" checkout -- package-lock.json 2>/dev/null || true
  fi
  spin_run "Installing dependencies (npm install)" "$INSTALL_LOG" "$PROJECT_DIR" \
    env NODE_ENV=development npm install --include=dev --no-audit --no-fund \
    || { err "npm install failed — details in $(short_path "$INSTALL_LOG")"; return 1; }
  if [[ ! -x $PROJECT_DIR/node_modules/.bin/tsx ]]; then
    err "Dependencies look incomplete (tsx not found). Check $(short_path "$INSTALL_LOG")"
    return 1
  fi
  return 0
}

env_fingerprint() { grep -E '^[[:space:]]*VITE_' "$PROJECT_DIR/.env" 2>/dev/null | cksum | awk '{print $1}'; }
build_stamp_now() { printf '%s|%s' "$(git_full_rev)" "$(env_fingerprint)"; }
build_needed() {
  [[ -f $PROJECT_DIR/dist/server.cjs && -f $PROJECT_DIR/dist/index.html ]] || return 0
  [[ "$(cat "$BUILD_STAMP_FILE" 2>/dev/null)" != "$(build_stamp_now)" ]]
}

build_panel() {
  local ram
  ram=$(awk '/^MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  [[ $ram =~ ^[0-9]+$ ]] && (( ram > 0 && ram < 900 )) && warn "Low memory (${ram} MB) — if the build is killed, add swap and retry."
  spin_run "Building production bundle (vite + esbuild)" "$BUILD_LOG" "$PROJECT_DIR" env NODE_ENV=production npm run build \
    || { err "Build failed — details in $(short_path "$BUILD_LOG")"; return 1; }
  if [[ ! -f $PROJECT_DIR/dist/server.cjs || ! -f $PROJECT_DIR/dist/index.html ]]; then
    err "Build finished but dist/ is incomplete."; return 1
  fi
  build_stamp_now >"$BUILD_STAMP_FILE"
}

ensure_build() {
  if build_needed; then build_panel; return $?; fi
  if is_git; then ok "Production bundle is current ($(git_rev))"; return 0; fi
  if confirm "Rebuild the production bundle?" n; then build_panel; return $?; fi
  ok "Using the existing production bundle"
}

# -----------------------------------------------------------------------------
# Run / stop / restart
# -----------------------------------------------------------------------------
chk_panel_ready() { panel_running || return 2; health_ok && return 0; return 1; }

start_panel_process() { # start_panel_process dev|prod
  local mode="$1" script
  [[ $mode == dev ]] && script=dev || script=start
  rotate_log "$PANEL_LOG"
  printf '\n===== [%s] starting MonoWeb (%s mode) =====\n' "$(date '+%F %T')" "$mode" >>"$PANEL_LOG"
  (
    cd "$PROJECT_DIR" || exit 1
    # server/auth.ts reads JWT_SECRET before dotenv runs, so real env vars matter.
    load_env_file "$PROJECT_DIR/.env"
    if [[ $mode == dev ]]; then export NODE_ENV=development; else export NODE_ENV=production; fi
    spawn_bg "$PANEL_PID_FILE" "$PANEL_LOG" npm run "$script"
  )
  [[ -s $PANEL_PID_FILE ]] || { err "Could not start the process."; return 1; }
  printf '%s' "$mode" >"$PANEL_MODE_FILE"
  printf '%s' "$mode" >"$LAST_MODE_FILE"
  date +%s >"$PANEL_START_FILE"
}

show_run_summary() {
  local mode url ip
  mode=$(panel_mode); url=$(get_env APP_URL); ip=$(server_ip)
  printf '\n'
  box_top
  box_title "MonoWeb is running"
  box_sep
  box_kv "Mode"    "$([[ $mode == prod ]] && echo 'Production' || echo 'Development')  ·  PID $(panel_pid)" "$C_OK"
  box_kv "Local"   "http://localhost:${PANEL_PORT}"
  [[ -n $ip ]] && box_kv "Network" "http://${ip}:${PANEL_PORT}"
  [[ -n $url && $url != "http://localhost:${PANEL_PORT}" ]] && box_kv "Public" "$url"
  box_kv "Logs"    "$(short_path "$PANEL_LOG")" "$C_MUTE"
  box_bot
}

launch_panel() { # launch_panel dev|prod
  local mode="$1" label timeout rc a
  if [[ $mode == prod ]]; then label="Production"; timeout=45; else label="Development"; timeout=90; fi
  section "Starting in ${label} mode"

  if [[ $mode == prod ]]; then ensure_build || return 1; fi

  if port_in_use && ! panel_running; then
    err "Port ${PANEL_PORT} is already used by another process."
    note "MonoWeb listens on ${PANEL_PORT} (fixed in server.ts). Stop whatever is using it and retry."
    return 1
  fi

  start_panel_process "$mode" || return 1
  wait_spin "Waiting for MonoWeb to come online" "$timeout" chk_panel_ready; rc=$?
  case $rc in
    0) ok "MonoWeb is online" ;;
    1) err "MonoWeb exited during startup."; show_log_tail "$PANEL_LOG" 18
       rm -f "$PANEL_PID_FILE" "$PANEL_MODE_FILE" "$PANEL_START_FILE"
       return 1 ;;
    *) warn "Still starting after ${timeout}s — it may just be slow. Check the log below." ;;
  esac
  show_run_summary

  SKIP_PAUSE=1
  printf '\n  %sEnter = back to menu  ·  L = follow the live log%s ' "$C_MUTE" "$C_RESET"
  IFS= read -r a || bye
  if [[ $a =~ ^[Ll]$ ]]; then follow_file "$PANEL_LOG"; fi
  return 0
}

choose_mode() { # sets $MODE (dev|prod); returns 1 if the user backs out
  local last; last=$(cat "$LAST_MODE_FILE" 2>/dev/null || true)
  printf '\n'
  box_top
  box_title "Run in which mode?"
  box_sep
  menu_item 1 "Dev"  "live compile · verbose$([[ $last == dev ]] && echo ' · last used')"
  menu_item 2 "Prod" "optimized build · for live traffic$([[ $last == prod ]] && echo ' · last used')"
  menu_item 0 "Back" "" "$C_ERR"
  box_bot
  printf '\n'
  while true; do
    ask "Select mode  (1 = Dev · 2 = Prod)"
    case "$ANSWER" in
      1|[Dd]|[Dd][Ee][Vv])           MODE=dev;  return 0 ;;
      2|[Pp]|[Pp][Rr][Oo][Dd])       MODE=prod; return 0 ;;
      0|"")                          return 1 ;;
      *) warn "Enter 1 for Dev or 2 for Prod (0 to go back)." ;;
    esac
  done
}

require_installed() {
  if is_installed && deps_installed; then return 0; fi
  warn "MonoWeb isn't installed yet."
  if confirm "Run the installer now?" y; then
    install_panel && is_installed && deps_installed && return 0
  fi
  return 1
}

stop_panel() {
  if ! panel_running; then
    rm -f "$PANEL_PID_FILE" "$PANEL_MODE_FILE" "$PANEL_START_FILE"
    ok "MonoWeb is not running"
    return 0
  fi
  info "Stopping MonoWeb (PID $(panel_pid))…"
  stop_process "$PANEL_PID_FILE"
  rm -f "$PANEL_MODE_FILE" "$PANEL_START_FILE"
  ok "MonoWeb stopped"
  port_in_use && warn "Port ${PANEL_PORT} is still busy — another process is listening on it."
  return 0
}

run_panel() {
  banner; section "Run Panel"
  require_installed || return 1
  if panel_running; then
    warn "MonoWeb is already running ($(panel_mode) mode · PID $(panel_pid) · up $(panel_uptime))."
    confirm "Stop it and start again?" n || return 0
    stop_panel
  fi
  choose_mode || return 0
  launch_panel "$MODE"
}

restart_panel() {
  banner; section "Restart Panel"
  require_installed || return 1
  local mode=""
  if panel_running; then mode=$(panel_mode); else mode=$(cat "$LAST_MODE_FILE" 2>/dev/null || true); fi
  if [[ $mode == dev || $mode == prod ]]; then
    if ! confirm "Restart in ${mode} mode?" y; then choose_mode || return 0; mode="$MODE"; fi
  else
    info "No previous run found — pick a mode."
    choose_mode || return 0; mode="$MODE"
  fi
  if panel_running; then stop_panel; else note "MonoWeb wasn't running — starting it fresh."; fi
  launch_panel "$mode"
}

stop_panel_menu() { banner; section "Stop Panel"; printf '\n'; stop_panel; }

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
install_panel() {
  banner; section "Install Panel"
  STEP_TOTAL=6; STEP_N=0
  CFG_EMAIL=""; CFG_URL=""; CFG_PASS_SHOWN=""
  ensure_dirs
  if is_installed; then
    warn "MonoWeb is already installed at $(short_path "$PROJECT_DIR")."
    confirm "Re-run setup? (your data is kept; you can keep your current .env)" y || return 0
  fi

  step "Preflight checks";     preflight
  step "System tools";         ensure_system_packages || return 1
  step "Node.js runtime";      ensure_node            || return 1
  step "Download MonoWeb";     clone_repo             || return 1
  step "Configuration";        configure_env          || return 1
  step "Install dependencies"; install_deps           || return 1

  [[ -n $CFG_EMAIL ]] || CFG_EMAIL=$(get_env AETHER_ADMIN_EMAIL)
  [[ -n $CFG_URL   ]] || CFG_URL=$(get_env APP_URL)
  printf '\n'
  box_top
  box_title "MonoWeb is installed"
  box_sep
  box_kv "Location" "$(short_path "$PROJECT_DIR")"
  box_kv "Config"   "$(short_path "$PROJECT_DIR/.env")"
  [[ -n $CFG_EMAIL ]] && box_kv "Admin" "$CFG_EMAIL"
  if [[ -n $CFG_PASS_SHOWN ]]; then
    box_kv "Password" "$CFG_PASS_SHOWN" "$C_WARN$C_BOLD"
    box_row "${C_WARN}Save this password now — it is only shown once.${C_RESET}"
  elif [[ -n $CFG_EMAIL ]]; then
    box_kv "Password" "(stored in .env)" "$C_MUTE"
  fi
  [[ -n $CFG_URL ]] && box_kv "Public URL" "$CFG_URL"
  box_bot
  printf '\n'
  info "Next: choose ${C_BOLD}2) Run Panel${C_RESET} and pick Dev or Prod."
}

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------
update_panel() {
  banner; section "Update Panel"
  if ! is_installed; then err "MonoWeb isn't installed yet — choose 1) Install Panel first."; return 1; fi
  if ! is_git; then
    err "This copy isn't a git checkout, so it can't be updated in place."
    note "Use 9) Delete Panel (your data is backed up) and 1) Install Panel to switch to a git checkout."
    return 1
  fi
  ensure_dirs
  local branch old new remote was_running=0 mode=""
  branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ -z $branch || $branch == HEAD ]]; then err "The checkout is on a detached HEAD — cannot update automatically."; return 1; fi

  printf '\n'
  backup_data "pre-update" || warn "Continuing without a fresh backup."

  spin_run "Fetching latest changes" "$INSTALL_LOG" "$PROJECT_DIR" env GIT_TERMINAL_PROMPT=0 git fetch --prune origin \
    || { err "Could not reach the repository."; return 1; }
  old=$(git_full_rev)
  remote=$(git -C "$PROJECT_DIR" rev-parse "origin/$branch" 2>/dev/null)
  if [[ -z $remote ]]; then err "Branch '$branch' no longer exists on origin."; return 1; fi

  if [[ $old == "$remote" ]]; then
    ok "Already up to date ($(git_rev) on $branch)"
    return 0
  fi

  git -C "$PROJECT_DIR" diff --quiet -- package-lock.json 2>/dev/null || git -C "$PROJECT_DIR" checkout -- package-lock.json 2>/dev/null
  if ! spin_run "Applying updates" "$INSTALL_LOG" "$PROJECT_DIR" git merge --ff-only "origin/$branch"; then
    warn "Fast-forward failed — you have local changes or the history diverged."
    if confirm "Discard local code changes and reset to origin/$branch? (.env and data/ are kept)" n; then
      spin_run "Resetting to origin/$branch" "$INSTALL_LOG" "$PROJECT_DIR" git reset --hard "origin/$branch" || return 1
    else
      warn "Update cancelled — your files were not touched."
      return 1
    fi
  fi
  new=$(git_full_rev)
  ok "Updated ${old:0:7} → ${new:0:7}"
  git -C "$PROJECT_DIR" log --oneline --no-decorate -n 8 "${old}..${new}" 2>/dev/null | while IFS= read -r l; do
    printf '    %s%s%s\n' "$C_MUTE" "$(fit "$l" $(( UI_W - 4 )))" "$C_RESET"
  done

  install_deps || return 1

  if panel_running; then
    was_running=1; mode=$(panel_mode)
    printf '\n'
    if confirm "MonoWeb is running in ${mode} mode. Restart now to apply the update?" y; then
      stop_panel
      launch_panel "$mode"
      return $?
    fi
    note "Not restarted — use 3) Restart Panel when you're ready."
  else
    note "Start it with 2) Run Panel (production mode rebuilds automatically)."
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Cloudflare Tunnel
# -----------------------------------------------------------------------------
install_cloudflared() {
  if have cloudflared; then
    CLOUDFLARED_BIN=$(command -v cloudflared)
    ok "cloudflared ready ($(cloudflared --version 2>&1 | head -n1))"; return 0
  fi
  if [[ -x $CLOUDFLARED_BIN ]]; then ok "cloudflared ready ($(short_path "$CLOUDFLARED_BIN"))"; return 0; fi
  local carch
  case "$(uname -m)" in
    x86_64|amd64)          carch=amd64 ;;
    aarch64|arm64)         carch=arm64 ;;
    armv7l|armv8l|armv6l)  carch=arm ;;
    i386|i686)             carch=386 ;;
    *) err "Unsupported CPU architecture for cloudflared: $(uname -m)"; return 1 ;;
  esac
  have curl || { err "curl is required to download cloudflared."; return 1; }
  mkdir -p "$(dirname "$CLOUDFLARED_BIN")"
  spin_run "Downloading cloudflared (linux-${carch})" "$INSTALL_LOG" / \
    curl -fsSL -o "$CLOUDFLARED_BIN.part" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${carch}" \
    || { rm -f "$CLOUDFLARED_BIN.part"; return 1; }
  chmod +x "$CLOUDFLARED_BIN.part" && mv -f "$CLOUDFLARED_BIN.part" "$CLOUDFLARED_BIN"
  ok "cloudflared installed at $(short_path "$CLOUDFLARED_BIN")"
}

chk_tunnel_ready() {
  tunnel_running || return 2
  grep -q 'Registered tunnel connection' "$TUNNEL_LOG" 2>/dev/null && return 0
  return 1
}

start_tunnel() {
  local conf name token rc
  conf=$(cat "$TUNNEL_CONF_FILE" 2>/dev/null) || { err "No saved tunnel settings yet."; return 1; }
  install_cloudflared || return 1
  stop_process "$TUNNEL_PID_FILE"
  rotate_log "$TUNNEL_LOG"
  printf '\n===== [%s] starting tunnel =====\n' "$(date '+%F %T')" >>"$TUNNEL_LOG"
  if [[ $conf == token ]]; then
    token=$(cat "$TUNNEL_TOKEN_FILE" 2>/dev/null)
    [[ -n $token ]] || { err "The saved token file is empty."; return 1; }
    ( export TUNNEL_TOKEN="$token"; spawn_bg "$TUNNEL_PID_FILE" "$TUNNEL_LOG" "$CLOUDFLARED_BIN" tunnel --no-autoupdate run )
  else
    name="${conf#named:}"
    spawn_bg "$TUNNEL_PID_FILE" "$TUNNEL_LOG" "$CLOUDFLARED_BIN" tunnel --no-autoupdate run --url "http://localhost:${PANEL_PORT}" "$name"
  fi
  wait_spin "Connecting to Cloudflare" 30 chk_tunnel_ready; rc=$?
  case $rc in
    0) ok "Tunnel connected" ;;
    1) err "The tunnel exited — Cloudflare said:"; show_log_tail "$TUNNEL_LOG" 12; rm -f "$TUNNEL_PID_FILE"; return 1 ;;
    *) warn "Tunnel is running but hasn't confirmed a connection yet — check the tunnel log." ;;
  esac
  panel_running || warn "The panel isn't running yet — visitors will see an error until you use 2) Run Panel."
  note "In Cloudflare, the public hostname's service must point to http://localhost:${PANEL_PORT}"
  return 0
}

set_public_url() {
  is_installed || { err "Install the panel first."; return 1; }
  [[ -f $PROJECT_DIR/.env ]] || { err "No .env found — run 1) Install Panel first."; return 1; }
  local url
  while true; do
    ask "Public URL (e.g. https://example.com) — Enter to skip"
    [[ -z $ANSWER ]] && return 0
    if url=$(normalize_url "$ANSWER"); then break; fi
    warn "Enter a URL like https://example.com (no path)."
  done
  apply_public_url "$url" || return 1
  ok "APP_URL, ALLOWED_ORIGINS and TRUST_PROXY updated for $url"
  if panel_running; then
    confirm "Restart MonoWeb now so the change takes effect?" y && { local m; m=$(panel_mode); stop_panel; launch_panel "$m"; }
  else
    note "Applied on the next start."
  fi
}

tunnel_menu() {
  local choice token name hostname saved
  while true; do
    banner; section "Cloudflare Tunnel"
    saved="none"
    [[ -f $TUNNEL_CONF_FILE ]] && saved=$(cat "$TUNNEL_CONF_FILE")
    printf '\n'
    box_top
    if tunnel_running; then
      box_row "${C_OK}${G_DOT}${C_RESET} ${C_BOLD}Tunnel running${C_RESET}  ${C_MUTE}PID $(cat "$TUNNEL_PID_FILE")${C_RESET}"
    else
      box_row "${C_MUTE}${G_RING} Tunnel stopped${C_RESET}"
    fi
    box_kv "Saved" "$saved" "$C_MUTE"
    box_sep
    menu_item 1 "Tunnel Token"     "paste the token from Zero Trust"
    menu_item 2 "Log in & create"    "named tunnel via your account"
    menu_item 3 "Start tunnel"     "reuse the last settings"
    menu_item 4 "Stop tunnel"        ""
    menu_item 5 "Set public URL"     "APP_URL + allowed origins"
    menu_item 0 "Back"               "" "$C_ERR"
    box_bot
    printf '\n'
    ask "Select an option"
    choice="$ANSWER"
    case "$choice" in
      1)
        install_cloudflared || { pause; continue; }
        if [[ -s $TUNNEL_TOKEN_FILE ]] && confirm "A saved token exists. Reuse it?" y; then
          token=$(cat "$TUNNEL_TOKEN_FILE")
        else
          printf '\n'; note "Zero Trust → Networks → Tunnels → your tunnel → Configure → copy the token."
          ask_secret "Paste the tunnel token"
          token=$(trim "$ANSWER")
          if [[ ! $token =~ ^[A-Za-z0-9=_-]{40,}$ ]]; then err "That doesn't look like a valid tunnel token."; pause; continue; fi
          ( umask 077; printf '%s' "$token" >"$TUNNEL_TOKEN_FILE" )
        fi
        printf 'token' >"$TUNNEL_CONF_FILE"
        printf '\n'
        start_tunnel && { printf '\n'; set_public_url; }
        pause ;;
      2)
        install_cloudflared || { pause; continue; }
        printf '\n'; info "A login link will appear — open it in your browser and authorize the tunnel."
        "$CLOUDFLARED_BIN" tunnel login 2>&1 | tee -a "$TUNNEL_LOG"
        ask "Tunnel name" "monoweb"
        name="$ANSWER"
        [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || { err "Use letters, numbers, dots, dashes or underscores."; pause; continue; }
        "$CLOUDFLARED_BIN" tunnel create "$name" 2>&1 | tee -a "$TUNNEL_LOG"
        ask "Hostname to route to it (e.g. app.example.com) — Enter to skip"
        hostname="$ANSWER"
        [[ -n $hostname ]] && "$CLOUDFLARED_BIN" tunnel route dns "$name" "$hostname" 2>&1 | tee -a "$TUNNEL_LOG"
        printf 'named:%s' "$name" >"$TUNNEL_CONF_FILE"
        printf '\n'
        start_tunnel && { [[ -n $hostname ]] && note "Then set your public URL to https://$hostname"; printf '\n'; set_public_url; }
        pause ;;
      3) printf '\n'; start_tunnel; pause ;;
      4) printf '\n'
         if tunnel_running; then stop_process "$TUNNEL_PID_FILE"; ok "Tunnel stopped"; else ok "Tunnel is not running"; fi
         pause ;;
      5) printf '\n'; set_public_url; pause ;;
      0|"") return 0 ;;
      *) warn "Choose a number from the menu."; sleep 1 ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# Status, logs, delete
# -----------------------------------------------------------------------------
status_info() {
  banner; section "Status & Info"
  local ram disk os mode
  os=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-$(uname -s)}" )
  ram=$(awk '/^MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "?")
  disk=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}')
  printf '\n'
  box_top
  box_title "Panel"
  box_sep
  if is_installed; then
    box_kv "Location" "$(short_path "$PROJECT_DIR")"
    if is_git; then box_kv "Version" "$(git_rev) on $(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    else box_kv "Version" "not a git checkout" "$C_WARN"; fi
    box_kv "Deps" "$(deps_installed && echo 'installed' || echo 'missing — run Install Panel')"
    box_kv "Build" "$( [[ -f $PROJECT_DIR/dist/server.cjs ]] && { build_needed && echo 'stale — rebuilds on next Prod run' || echo 'current'; } || echo 'none yet' )"
    box_kv "Config" "$( [[ -f $PROJECT_DIR/.env ]] && echo ".env present · admin $(get_env AETHER_ADMIN_EMAIL)" || echo 'no .env' )"
    box_kv "Public URL" "$(u=$(get_env APP_URL); echo "${u:-not set}")"
    box_kv "Data" "$( [[ -f $PROJECT_DIR/data/db.json ]] && echo "db.json $(du -h "$PROJECT_DIR/data/db.json" 2>/dev/null | cut -f1)" || echo 'no database yet' )"
  else
    box_kv "Location" "not installed" "$C_WARN"
  fi
  box_sep
  box_title "Runtime"
  box_sep
  if panel_running; then
    mode=$(panel_mode)
    box_kv "Panel" "running · ${mode} · PID $(panel_pid) · up $(panel_uptime)" "$C_OK"
    box_kv "Health" "$(health_ok && echo "online at http://localhost:${PANEL_PORT}" || echo 'process is up but not answering yet')" "$(health_ok && echo "$C_OK" || echo "$C_WARN")"
  else
    box_kv "Panel" "stopped" "$C_MUTE"
  fi
  box_kv "Tunnel" "$(tunnel_running && echo "running · PID $(cat "$TUNNEL_PID_FILE")" || echo 'stopped')" "$(tunnel_running && echo "$C_OK" || echo "$C_MUTE")"
  box_sep
  box_title "System"
  box_sep
  box_kv "OS" "$os · $(uname -m)"
  box_kv "Resources" "RAM ${ram} MB · ${disk:-?} MB free disk"
  box_kv "Node.js" "$(have node && echo "$(node -v) · npm $(npm -v 2>/dev/null)" || echo 'not installed')" "$(node_ok && echo "$C_TXT" || echo "$C_WARN")"
  box_kv "git / curl" "$(have git && echo yes || echo NO) / $(have curl && echo yes || echo NO)"
  box_bot
}

view_logs() {
  local choice file a
  while true; do
    banner; section "View Logs"
    printf '\n'
    box_top
    menu_item 1 "Panel log"      "$(short_path "$PANEL_LOG")"
    menu_item 2 "Install / update" "$(short_path "$INSTALL_LOG")"
    menu_item 3 "Build log"      "$(short_path "$BUILD_LOG")"
    menu_item 4 "Tunnel log"     "$(short_path "$TUNNEL_LOG")"
    menu_item 0 "Back"           "" "$C_ERR"
    box_bot
    printf '\n'
    ask "Select a log"
    case "$ANSWER" in
      1) file="$PANEL_LOG" ;; 2) file="$INSTALL_LOG" ;; 3) file="$BUILD_LOG" ;; 4) file="$TUNNEL_LOG" ;;
      0|"") return 0 ;;
      *) warn "Choose a number from the menu."; sleep 1; continue ;;
    esac
    printf '\n'
    if [[ -s $file ]]; then
      show_log_tail "$file" 30
      printf '\n'
      confirm "Follow it live?" n && follow_file "$file"
    else
      warn "That log is empty — nothing has run yet."
    fi
    pause
  done
}

safe_to_delete() { # refuse anything that isn't clearly a MonoWeb checkout
  local d="$1"
  [[ -n $d && $d != / && $d != "$HOME" && $d != "$HOME/" ]] || return 1
  [[ $d == /*/* ]] || return 1
  [[ -f $d/package.json && -f $d/server.ts ]]
}

delete_panel() {
  banner; section "Delete Panel"
  BACKUP_LAST=""
  if ! [[ -e $PROJECT_DIR ]]; then
    warn "Nothing to delete — $(short_path "$PROJECT_DIR") doesn't exist."
    return 0
  fi
  if ! safe_to_delete "$PROJECT_DIR"; then
    err "$(short_path "$PROJECT_DIR") doesn't look like a MonoWeb install — refusing to delete it."
    note "Remove it by hand if you're sure."
    return 1
  fi
  local ident="/etc/aetherpanel/installation.json" rm_ident=0 typed
  printf '\n'
  box_top
  box_title "This permanently removes"
  box_sep
  box_row "${C_ERR}${G_BUL}${C_RESET} $(fit "$(short_path "$PROJECT_DIR")  (source, node_modules, build, .env, database)" $(( UI_W - 6 )))"
  box_row "${C_ERR}${G_BUL}${C_RESET} Logs, pid files and tunnel settings in $(short_path "$STATE_DIR")"
  box_row "${C_ERR}${G_BUL}${C_RESET} The panel and the Cloudflare tunnel are stopped first"
  box_bot
  printf '\n'
  note "Node.js, git and the cloudflared binary stay installed."

  if confirm "Save a backup of data/ and .env first?" y; then
    backup_data "before-delete" || { confirm "Backup failed. Delete anyway?" n || return 1; }
  fi
  if [[ -f $ident ]]; then
    confirm "Also remove the saved installation identity ($ident)?" n && rm_ident=1
  fi

  printf '\n'
  ask "Type DELETE to confirm (anything else cancels)"
  typed="$ANSWER"
  [[ $typed == DELETE ]] || { ok "Cancelled — nothing was removed."; return 0; }

  printf '\n'
  panel_running  && stop_panel
  tunnel_running && { stop_process "$TUNNEL_PID_FILE"; ok "Tunnel stopped"; }
  if rm -rf -- "$PROJECT_DIR"; then ok "Removed $(short_path "$PROJECT_DIR")"; else err "Could not remove everything in $(short_path "$PROJECT_DIR")"; return 1; fi
  if (( rm_ident )); then
    if [[ $EUID -eq 0 ]]; then rm -f "$ident" && ok "Removed $ident"
    elif have sudo && sudo -n rm -f "$ident" 2>/dev/null; then ok "Removed $ident"
    else warn "Couldn't remove $ident without root."; fi
  fi
  rm -rf -- "$STATE_DIR" && ok "Removed $(short_path "$STATE_DIR")"
  ensure_dirs
  printf '\n'
  if [[ -n $BACKUP_LAST ]]; then info "Your backup: $(short_path "$BACKUP_LAST")"; fi
  info "Use 1) Install Panel whenever you want a fresh copy."
}

# -----------------------------------------------------------------------------
# Main menu
# -----------------------------------------------------------------------------
draw_home() {
  banner
  printf '\n'
  box_top
  if panel_running; then
    box_stat "Panel" "$G_DOT" "Running" "$(panel_mode) · PID $(panel_pid) · up $(panel_uptime)" "$C_OK"
    if health_ok; then box_stat "Web" "$G_DOT" "http://localhost:${PANEL_PORT}" "" "$C_OK"
    else box_stat "Web" "$G_WARN" "starting / not answering yet" "" "$C_WARN"; fi
  else
    box_stat "Panel" "$G_RING" "Stopped" "" "$C_MUTE"
  fi
  if tunnel_running; then box_stat "Tunnel" "$G_DOT" "Connected" "" "$C_OK"
  else box_stat "Tunnel" "$G_RING" "Stopped" "" "$C_MUTE"; fi
  if is_installed; then
    box_stat "Install" "$G_OK" "$(short_path "$PROJECT_DIR")$(is_git && echo " @ $(git_rev)")" "" "$C_OK"
  else
    box_stat "Install" "$G_ERR" "Not installed — start with 1" "" "$C_WARN"
  fi
  box_sep
  menu_group "SETUP"
  menu_item 1 "Install Panel"   "clone, configure, install deps"
  menu_group "RUN"
  menu_item 2 "Run Panel"       "choose Dev or Prod mode"
  menu_item 3 "Restart Panel"   "apply changes or recover"
  menu_item 4 "Stop Panel"      "shut the panel down"
  menu_group "MANAGE"
  menu_item 5 "Update Panel"    "pull the latest code"
  menu_item 6 "Cloudflare Tunnel" "connect your domain"
  menu_item 7 "Status & Info"   "versions, health, config"
  menu_item 8 "View Logs"       "panel, build, tunnel"
  menu_item 9 "Delete Panel"    "remove all panel files" "$C_ERR"
  box_sep
  menu_item 0 "Exit" "" "$C_MUTE"
  box_bot
  printf '\n'
}

main_menu() {
  local choice
  while true; do
    ensure_dirs
    draw_home
    ask "Select an option  [0-9]"
    choice="$ANSWER"
    SKIP_PAUSE=0
    case "$choice" in
      1) install_panel ;;
      2) run_panel ;;
      3) restart_panel ;;
      4) stop_panel_menu ;;
      5) update_panel ;;
      6) tunnel_menu; SKIP_PAUSE=1 ;;
      7) status_info ;;
      8) view_logs; SKIP_PAUSE=1 ;;
      9) delete_panel ;;
      0|q|Q|exit) bye ;;
      "") continue ;;
      *) warn "Invalid selection '$choice' — choose a number from the menu."; sleep 1.2; continue ;;
    esac
    (( SKIP_PAUSE )) || pause
  done
}

usage() {
  cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION  ·  made by $SCRIPT_CREDIT

Usage: $(basename "$0") [--help | --version]

Run it with no arguments to open the interactive menu.

Environment overrides:
  MONOWEB_REPO    git URL to clone      (default: https://github.com/Srccodeusr/MonoWeb.git)
  MONOWEB_BRANCH  branch to clone       (default: the repo's default branch)
  MONOWEB_DIR     install directory     (default: ~/monoweb)
  MONOWEB_HOME    logs / pids / state   (default: ~/.monoweb)
EOF
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------
case "${1:-}" in
  -h|--help)    usage; exit 0 ;;
  -v|--version) printf '%s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
esac

ui_init
trap on_int INT TERM
trap cleanup EXIT
ensure_dirs
main_menu
