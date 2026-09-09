#!/usr/bin/env bash
# ============================================================================
#  MonoHost Installation Script
#  Made by PRIME.DEV1
#
#  One-click installer / updater for the MonoHost web panel, plus a
#  Cloudflare Tunnel installer. Works in CodeSandbox containers and on
#  regular Debian/Ubuntu VPS boxes.
# ============================================================================

# ---------------------------------------------------------------------------
# Config (override with env vars before running if you need to)
# ---------------------------------------------------------------------------
REPO_URL="${REPO_URL:-https://github.com/Srccodeusr/Aetherpanel-only-frontend-Made-by-Zensei-.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/monohost}"
APP_NAME="monohost"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'

trap 'echo -e "\n${RED}Interrupted.${RESET}"; exit 1' INT

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
show_menu() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║                                                ║"
  echo "  ║             MonoHost Installation             ║"
  echo "  ║                    Script                     ║"
  echo "  ║                                                ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo -e "${MAGENTA}                 Made by PRIME.DEV1${RESET}"
  echo
  echo -e "   ${YELLOW}${BOLD}[1]${RESET} Install the Website"
  echo -e "   ${YELLOW}${BOLD}[2]${RESET} Update the Website"
  echo -e "   ${YELLOW}${BOLD}[3]${RESET} Install Cloudflared"
  echo -e "   ${YELLOW}${BOLD}[0]${RESET} Exit"
  echo
}

print_header() {
  echo -e "${BOLD}${CYAN}== $1 ==${RESET}"
  echo
}

pause_return() {
  echo
  read -rp "$(echo -e "${MAGENTA}Press enter to return to menu...${RESET}")" _unused
}

# Runs $3 (a function name) in the background, shows a spinner next to the
# label in $2 tagged with the step number in $1, and reports Done/Failed.
run_step() {
  local step_num="$1"
  local label="$2"
  local func="$3"
  local logfile
  logfile="$(mktemp)"

  "$func" >"$logfile" 2>&1 &
  local pid=$!

  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#spin} ))
    printf "\r${CYAN}[%s]${RESET} %s  ${YELLOW}Loading %s${RESET}     " "$step_num" "$label" "${spin:$i:1}"
    sleep 0.1
  done

  wait "$pid"
  local status=$?

  if [ "$status" -eq 0 ]; then
    printf "\r${CYAN}[%s]${RESET} %s  ${GREEN}Done ✔${RESET}                  \n" "$step_num" "$label"
  else
    printf "\r${CYAN}[%s]${RESET} %s  ${RED}Failed ✘${RESET}                  \n" "$step_num" "$label"
    echo -e "${RED}---- error output ----${RESET}"
    tail -n 25 "$logfile"
    echo -e "${RED}----------------------${RESET}"
  fi
  rm -f "$logfile"
  return "$status"
}

as_sudo() {
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    echo "sudo"
  else
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Step functions: Install the Website
# ---------------------------------------------------------------------------
step_install_deps() {
  set -e
  export DEBIAN_FRONTEND=noninteractive
  local SUDO; SUDO="$(as_sudo)"

  $SUDO apt-get update -y
  $SUDO apt-get install -y curl git build-essential ca-certificates gnupg

  if ! command -v node >/dev/null 2>&1 || [ "$(node -v | sed 's/v//;s/\..*//')" -lt 18 ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
    $SUDO apt-get install -y nodejs
  fi

  if ! command -v pm2 >/dev/null 2>&1; then
    $SUDO npm install -g pm2
  fi
}

step_clone_repo() {
  set -e
  rm -rf "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
}

step_build_site() {
  set -e
  cd "$INSTALL_DIR"
  npm install

  if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    if command -v openssl >/dev/null 2>&1; then
      local secret; secret="$(openssl rand -hex 32)"
      sed -i "s|^JWT_SECRET=.*|JWT_SECRET=\"$secret\"|" .env
    fi
  fi

  npm run build

  pm2 delete "$APP_NAME" >/dev/null 2>&1 || true
  pm2 start dist/server.cjs --name "$APP_NAME"
  pm2 save
}

install_website() {
  clear
  print_header "Installing the Website"

  run_step 1 "Installing Dependencies" step_install_deps || { pause_return; return; }
  run_step 2 "Cloning the GitHub Repo"  step_clone_repo   || { pause_return; return; }
  run_step 3 "Building the Website"     step_build_site   || { pause_return; return; }

  echo
  echo -e "${GREEN}${BOLD}Installation completed.${RESET}"
  echo -e "${CYAN}Site running at:${RESET} http://localhost:3000"
  echo -e "${CYAN}Installed to:${RESET}    $INSTALL_DIR"
  echo -e "${CYAN}Config file:${RESET}     $INSTALL_DIR/.env  ${YELLOW}(edit admin email/password + Discord/Firebase keys, then 'pm2 restart $APP_NAME')${RESET}"
  pause_return
}

# ---------------------------------------------------------------------------
# Step functions: Update the Website
# ---------------------------------------------------------------------------
step_fetch_updates() {
  set -e
  cd "$INSTALL_DIR"
  git fetch origin
  local branch
  branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch#origin/}"
  if [ -z "$branch" ]; then branch="main"; fi
  git reset --hard "origin/$branch"
}

step_update_deps() {
  set -e
  cd "$INSTALL_DIR"
  npm install
}

step_rebuild_site() {
  set -e
  cd "$INSTALL_DIR"
  npm run build
  if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
    pm2 restart "$APP_NAME"
  else
    pm2 start dist/server.cjs --name "$APP_NAME"
  fi
  pm2 save
}

update_website() {
  clear
  print_header "Updating the Website"

  if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo -e "${RED}MonoHost isn't installed at $INSTALL_DIR yet.${RESET}"
    echo -e "Run ${YELLOW}[1] Install the Website${RESET} first."
    pause_return
    return
  fi

  run_step 1 "Fetching Updates from GitHub"   step_fetch_updates || { pause_return; return; }
  run_step 2 "Installing Updated Dependencies" step_update_deps  || { pause_return; return; }
  run_step 3 "Rebuilding the Website"           step_rebuild_site || { pause_return; return; }

  echo
  echo -e "${GREEN}${BOLD}Update completed.${RESET}"
  pause_return
}

# ---------------------------------------------------------------------------
# Step functions: Install Cloudflared
# ---------------------------------------------------------------------------
step_install_cloudflared_pkg() {
  set -e
  local SUDO; SUDO="$(as_sudo)"
  export DEBIAN_FRONTEND=noninteractive

  $SUDO mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | $SUDO tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
    | $SUDO tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install -y cloudflared
}

step_install_cloudflared_service() {
  set -e
  local SUDO; SUDO="$(as_sudo)"
  $SUDO cloudflared service install "$TUNNEL_TOKEN"
}

install_cloudflared() {
  clear
  print_header "Installing Cloudflared"

  run_step 1 "Installing Cloudflared" step_install_cloudflared_pkg || { pause_return; return; }

  echo
  echo -e "${CYAN}You can paste either the full command from Cloudflare Zero Trust"
  echo -e "(e.g. ${YELLOW}cloudflared service install eyJhIjoi...${CYAN}) or just the bare token.${RESET}"
  read -rp "$(echo -e "${YELLOW}${BOLD}Paste your token here: ${RESET}")" TUNNEL_INPUT

  if [ -z "$TUNNEL_INPUT" ]; then
    echo -e "${RED}No token provided. Aborting.${RESET}"
    pause_return
    return
  fi

  # Accept either "cloudflared service install <token>" or a bare token
  if echo "$TUNNEL_INPUT" | grep -qi "cloudflared"; then
    TUNNEL_TOKEN="$(echo "$TUNNEL_INPUT" | awk '{print $NF}')"
  else
    TUNNEL_TOKEN="$(echo "$TUNNEL_INPUT" | tr -d '[:space:]')"
  fi
  export TUNNEL_TOKEN

  run_step 2 "Registering Cloudflare Tunnel Service" step_install_cloudflared_service || { pause_return; return; }

  echo
  echo -e "${GREEN}${BOLD}Cloudflared installed and running as a service.${RESET}"
  pause_return
}

# ---------------------------------------------------------------------------
# Main menu loop
# ---------------------------------------------------------------------------
while true; do
  show_menu
  read -rp "$(echo -e "${GREEN}${BOLD}Select an option ➤ ${RESET}")" CHOICE
  case "$CHOICE" in
    1) install_website ;;
    2) update_website ;;
    3) install_cloudflared ;;
    0) echo -e "${CYAN}Goodbye!${RESET}"; exit 0 ;;
    *) echo -e "${RED}Invalid option.${RESET}"; sleep 1 ;;
  esac
done
