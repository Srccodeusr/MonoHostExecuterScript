#!/usr/bin/env bash
# ============================================================================
#  __  __                  _   _           _
# |  \/  | ___  _ __   ___| | | | ___  ___| |_
# | |\/| |/ _ \| '_ \ / _ \ |_| |/ _ \/ __| __|
# | |  | | (_) | | | | (_) |  _  | (_) \__ \ |_
# |_|  |_|\___/|_| |_|\___/|_| |_|\___/|___/\__|
#
#  MonoHost Executer Script
#  Made by prime.dev1
#
#  Installs dependencies, clones/updates the site from GitHub, builds it,
#  runs it in dev or production mode, and can punch it out to a domain
#  through a Cloudflare Tunnel — all from one numbered menu.
# ============================================================================

set -uo pipefail

# ----------------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------------
RESET='\033[0m'
BOLD='\033[1m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD_CYAN='\033[1;36m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_RED='\033[1;31m'
BOLD_MAGENTA='\033[1;35m'
GRAY='\033[0;90m'

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
REPO_URL="https://github.com/Srccodeusr/Aetherpanel-only-frontend-Made-by-Zensei-.git"
PROJECT_DIR="$HOME/monohost-site"
CLOUDFLARED_BIN="$HOME/.local/bin/cloudflared"
# Logs/PID files live OUTSIDE the project dir on purpose — clone_or_update_repo()
# can rm -rf and re-clone PROJECT_DIR, which would wipe anything stored inside it.
MONOHOST_HOME="$HOME/.monohost"
LOG_DIR="$MONOHOST_HOME/logs"
DEV_LOG="$LOG_DIR/dev.log"
PROD_LOG="$LOG_DIR/prod.log"
TUNNEL_LOG="$LOG_DIR/tunnel.log"
PID_DIR="$MONOHOST_HOME/pids"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
line() { printf "${GRAY}────────────────────────────────────────────────────────────${RESET}\n"; }

banner() {
  clear
  printf "${BOLD_CYAN}"
  cat <<'EOF'
  __  __                  _   _           _
 |  \/  | ___  _ __   ___| | | | ___  ___| |_
 | |\/| |/ _ \| '_ \ / _ \ |_| |/ _ \/ __| __|
 | |  | | (_) | | | | (_) |  _  | (_) \__ \ |_
 |_|  |_|\___/|_| |_|\___/|_| |_|\___/|___/\__|
EOF
  printf "${RESET}"
  printf "${BOLD}${MAGENTA}          MonoHost Executer Script${RESET}\n"
  printf "${GRAY}                Made by prime.dev1${RESET}\n"
  line
}

info()    { printf "${CYAN}➤ %s${RESET}\n" "$1"; }
success() { printf "${BOLD_GREEN}✔ %s${RESET}\n" "$1"; }
warn()    { printf "${BOLD_YELLOW}⚠ %s${RESET}\n" "$1"; }
error()   { printf "${BOLD_RED}✖ %s${RESET}\n" "$1"; }
step()    { printf "${BLUE}${BOLD}[STEP]${RESET} ${BOLD}%s${RESET}\n" "$1"; }

press_enter() {
  printf "\n${GRAY}Press Enter to return to the menu...${RESET}"
  read -r _
}

confirm() {
  local prompt="$1"
  local reply
  printf "${YELLOW}%s [y/N]: ${RESET}" "$prompt"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

ensure_dirs() {
  mkdir -p "$LOG_DIR" "$PID_DIR" "$HOME/.local/bin" 2>/dev/null || true
}

# Detect a usable package-install command; never hard-fail the whole script
# if apt isn't available or sudo isn't present (CodeSandbox containers vary).
pkg_install() {
  local pkgs=("$@")
  if command -v apt-get >/dev/null 2>&1; then
    if [[ $EUID -eq 0 ]]; then
      apt-get update -y >>"$LOG_DIR/apt.log" 2>&1
      apt-get install -y "${pkgs[@]}" >>"$LOG_DIR/apt.log" 2>&1
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y >>"$LOG_DIR/apt.log" 2>&1
      sudo apt-get install -y "${pkgs[@]}" >>"$LOG_DIR/apt.log" 2>&1
    else
      warn "No root/sudo access — skipping apt-get for: ${pkgs[*]}"
      return 1
    fi
  else
    warn "apt-get not found on this system — skipping: ${pkgs[*]}"
    return 1
  fi
}

# ----------------------------------------------------------------------------
# 1) System dependency check / install
# ----------------------------------------------------------------------------
check_system_deps() {
  step "Checking system dependencies"
  ensure_dirs

  local need_pkgs=()
  command -v git    >/dev/null 2>&1 || need_pkgs+=("git")
  command -v curl   >/dev/null 2>&1 || need_pkgs+=("curl")
  command -v unzip  >/dev/null 2>&1 || need_pkgs+=("unzip")

  if [[ ${#need_pkgs[@]} -gt 0 ]]; then
    info "Installing missing system packages: ${need_pkgs[*]}"
    pkg_install "${need_pkgs[@]}" || warn "Some packages may not have installed — continuing anyway."
  else
    success "git, curl, unzip already present."
  fi

  if ! command -v node >/dev/null 2>&1; then
    warn "Node.js was not found on this system."
    if confirm "Attempt to install Node.js 20.x via NodeSource now?"; then
      curl -fsSL https://deb.nodesource.com/setup_20.x -o "$LOG_DIR/nodesource_setup.sh" 2>>"$LOG_DIR/apt.log"
      if [[ $EUID -eq 0 ]]; then
        bash "$LOG_DIR/nodesource_setup.sh" >>"$LOG_DIR/apt.log" 2>&1
        pkg_install nodejs
      elif command -v sudo >/dev/null 2>&1; then
        sudo bash "$LOG_DIR/nodesource_setup.sh" >>"$LOG_DIR/apt.log" 2>&1
        pkg_install nodejs
      else
        error "Cannot install Node.js without root or sudo. Install it manually, then re-run this script."
        return 1
      fi
    else
      error "Node.js is required to build and run this project. Aborting this action."
      return 1
    fi
  fi

  if command -v node >/dev/null 2>&1; then
    success "Node.js found: $(node -v)"
  else
    error "Node.js still not available — cannot continue."
    return 1
  fi

  if command -v npm >/dev/null 2>&1; then
    success "npm found: $(npm -v)"
  else
    error "npm not found alongside Node.js — something is wrong with the Node install."
    return 1
  fi

  return 0
}

# ----------------------------------------------------------------------------
# 2) Clone / Update site from GitHub
# ----------------------------------------------------------------------------
clone_or_update_repo() {
  step "Syncing site code from GitHub"
  ensure_dirs

  if [[ -d "$PROJECT_DIR/.git" ]]; then
    info "Existing checkout found at $PROJECT_DIR — pulling latest changes..."
    if git -C "$PROJECT_DIR" pull --ff-only 2>>"$LOG_DIR/git.log"; then
      success "Repository updated to the latest commit."
    else
      warn "Fast-forward pull failed (local changes or diverged history)."
      if confirm "Discard local changes and hard-reset to the latest remote version?"; then
        git -C "$PROJECT_DIR" fetch origin >>"$LOG_DIR/git.log" 2>&1
        local default_branch
        default_branch=$(git -C "$PROJECT_DIR" remote show origin 2>>"$LOG_DIR/git.log" | awk '/HEAD branch/ {print $NF}')
        default_branch=${default_branch:-main}
        git -C "$PROJECT_DIR" reset --hard "origin/$default_branch" >>"$LOG_DIR/git.log" 2>&1
        success "Repository force-updated to origin/$default_branch."
      else
        warn "Keeping existing local copy as-is."
      fi
    fi
  else
    info "No existing checkout — cloning fresh from:"
    printf "  ${CYAN}%s${RESET}\n" "$REPO_URL"
    rm -rf "$PROJECT_DIR" 2>/dev/null || true
    if git clone "$REPO_URL" "$PROJECT_DIR" 2>>"$LOG_DIR/git.log"; then
      success "Clone complete → $PROJECT_DIR"
    else
      error "Git clone failed. Check $LOG_DIR/git.log for details."
      tail -n 15 "$LOG_DIR/git.log" 2>/dev/null
      return 1
    fi
  fi

  return 0
}

# ----------------------------------------------------------------------------
# 3) Install project dependencies
# ----------------------------------------------------------------------------
install_project_deps() {
  step "Installing project dependencies (npm install)"
  if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
    error "No package.json found in $PROJECT_DIR — did the clone succeed?"
    return 1
  fi

  ( cd "$PROJECT_DIR" && npm install ) 2>&1 | tee -a "$LOG_DIR/npm-install.log"
  local status=${PIPESTATUS[0]}

  if [[ $status -ne 0 ]]; then
    error "npm install failed. Check $LOG_DIR/npm-install.log for details."
    return 1
  fi

  success "Dependencies installed."
  return 0
}

# ----------------------------------------------------------------------------
# 4) Build project (production)
# ----------------------------------------------------------------------------
build_project() {
  step "Building production bundle (npm run build)"
  if ! grep -q '"build"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    error "No 'build' script found in package.json."
    return 1
  fi

  ( cd "$PROJECT_DIR" && npm run build ) 2>&1 | tee -a "$LOG_DIR/build.log"
  local status=${PIPESTATUS[0]}

  if [[ $status -ne 0 ]]; then
    error "Build failed. Check $LOG_DIR/build.log for details."
    return 1
  fi

  success "Build complete."
  return 0
}

# ----------------------------------------------------------------------------
# 5) Run in Dev Mode
# ----------------------------------------------------------------------------
run_dev_mode() {
  banner
  step "Starting DEV MODE"
  check_system_deps || { press_enter; return 1; }
  clone_or_update_repo || { press_enter; return 1; }
  install_project_deps || { press_enter; return 1; }

  info "Launching dev server (npm run dev)..."
  info "Logs are streaming below. Press Ctrl+C to stop and return to the menu."
  line
  ( cd "$PROJECT_DIR" && npm run dev ) 2>&1 | tee -a "$DEV_LOG"

  warn "Dev server stopped."
  press_enter
}

# ----------------------------------------------------------------------------
# 6) Run in Production Mode
# ----------------------------------------------------------------------------
run_production_mode() {
  banner
  step "Starting PRODUCTION MODE"
  check_system_deps || { press_enter; return 1; }
  clone_or_update_repo || { press_enter; return 1; }
  install_project_deps || { press_enter; return 1; }
  build_project || { press_enter; return 1; }

  if ! grep -q '"start"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    error "No 'start' script found in package.json — cannot launch production server."
    press_enter
    return 1
  fi

  info "Launching production server (npm start)..."
  info "Logs are streaming below. Press Ctrl+C to stop and return to the menu."
  line
  ( cd "$PROJECT_DIR" && npm start ) 2>&1 | tee -a "$PROD_LOG"

  warn "Production server stopped."
  press_enter
}

# ----------------------------------------------------------------------------
# 7) Update Website (pull latest release / commits + rebuild)
# ----------------------------------------------------------------------------
update_website() {
  banner
  step "Updating website to the latest GitHub release"

  clone_or_update_repo || { press_enter; return 1; }
  install_project_deps || { press_enter; return 1; }

  if confirm "Rebuild the production bundle now with the updated code?"; then
    build_project || { press_enter; return 1; }
    success "Website updated and rebuilt. Start Production Mode to serve the new version."
  else
    success "Website code updated. Run a build later from the menu when you're ready."
  fi

  press_enter
}

# ----------------------------------------------------------------------------
# 8) Cloudflare Tunnel installer / connector
# ----------------------------------------------------------------------------
install_cloudflared() {
  step "Checking for cloudflared"

  if command -v cloudflared >/dev/null 2>&1; then
    success "cloudflared already installed: $(cloudflared --version 2>&1 | head -n1)"
    CLOUDFLARED_BIN="$(command -v cloudflared)"
    return 0
  fi

  if [[ -x "$CLOUDFLARED_BIN" ]]; then
    success "cloudflared already installed locally: $CLOUDFLARED_BIN"
    return 0
  fi

  info "Downloading cloudflared (Linux amd64 static binary)..."
  ensure_dirs
  local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"

  if curl -fsSL "$url" -o "$CLOUDFLARED_BIN" 2>>"$LOG_DIR/cloudflared-install.log"; then
    chmod +x "$CLOUDFLARED_BIN"
    export PATH="$HOME/.local/bin:$PATH"
    success "cloudflared installed at $CLOUDFLARED_BIN"
    "$CLOUDFLARED_BIN" --version
    return 0
  else
    error "Failed to download cloudflared. Check $LOG_DIR/cloudflared-install.log"
    return 1
  fi
}

cloudflare_tunnel_menu() {
  banner
  step "Cloudflare Tunnel Setup"
  install_cloudflared || { press_enter; return 1; }

  echo
  printf "${BOLD}How do you want to connect your domain?${RESET}\n\n"
  printf "  ${BOLD_CYAN}1)${RESET} I already have a Tunnel Token (paste it in)\n"
  printf "  ${BOLD_CYAN}2)${RESET} Log in interactively with my Cloudflare account\n"
  printf "  ${BOLD_CYAN}0)${RESET} Back to main menu\n\n"
  printf "${YELLOW}Choose an option: ${RESET}"
  read -r tchoice

  case "$tchoice" in
    1)
      echo
      printf "${CYAN}Paste your Cloudflare Tunnel Token (from Zero Trust → Networks → Tunnels):${RESET}\n"
      read -r cf_token
      if [[ -z "$cf_token" ]]; then
        error "No token entered — aborting."
        press_enter
        return 1
      fi
      info "Starting Cloudflare Tunnel with the provided token..."
      info "This will run in the foreground. Press Ctrl+C to stop the tunnel and return to the menu."
      line
      "$CLOUDFLARED_BIN" tunnel run --token "$cf_token" 2>&1 | tee -a "$TUNNEL_LOG"
      warn "Tunnel stopped."
      ;;
    2)
      echo
      info "This will open a Cloudflare login link. Open it in your browser and authorize the tunnel."
      "$CLOUDFLARED_BIN" tunnel login 2>&1 | tee -a "$TUNNEL_LOG"
      echo
      printf "${CYAN}Enter a name for this tunnel (e.g. monohost-site): ${RESET}"
      read -r tunnel_name
      tunnel_name=${tunnel_name:-monohost-site}
      "$CLOUDFLARED_BIN" tunnel create "$tunnel_name" 2>&1 | tee -a "$TUNNEL_LOG"
      echo
      printf "${CYAN}Enter the hostname to route to this tunnel (e.g. app.yourdomain.com): ${RESET}"
      read -r tunnel_hostname
      if [[ -n "$tunnel_hostname" ]]; then
        "$CLOUDFLARED_BIN" tunnel route dns "$tunnel_name" "$tunnel_hostname" 2>&1 | tee -a "$TUNNEL_LOG"
      fi
      echo
      info "Starting the tunnel, pointing to http://localhost:3000 ..."
      info "Press Ctrl+C to stop the tunnel and return to the menu."
      line
      "$CLOUDFLARED_BIN" tunnel run --url http://localhost:3000 "$tunnel_name" 2>&1 | tee -a "$TUNNEL_LOG"
      warn "Tunnel stopped."
      ;;
    0)
      return 0
      ;;
    *)
      warn "Invalid option."
      ;;
  esac

  press_enter
}

# ----------------------------------------------------------------------------
# 9) View recent logs
# ----------------------------------------------------------------------------
view_logs() {
  banner
  step "Recent Logs"
  ensure_dirs
  local any=0
  for f in "$DEV_LOG" "$PROD_LOG" "$TUNNEL_LOG" "$LOG_DIR/build.log" "$LOG_DIR/npm-install.log" "$LOG_DIR/git.log"; do
    if [[ -f "$f" ]]; then
      any=1
      printf "${BOLD_CYAN}── %s ──${RESET}\n" "$(basename "$f")"
      tail -n 12 "$f"
      echo
    fi
  done
  if [[ $any -eq 0 ]]; then
    warn "No logs yet — run Dev Mode, Production Mode, or a Tunnel first."
  fi
  press_enter
}

# ----------------------------------------------------------------------------
# Main Menu
# ----------------------------------------------------------------------------
main_menu() {
  while true; do
    banner
    printf "${BOLD}Repository:${RESET} ${GRAY}%s${RESET}\n" "$REPO_URL"
    printf "${BOLD}Project dir:${RESET} ${GRAY}%s${RESET}\n\n" "$PROJECT_DIR"

    printf "  ${BOLD_GREEN}1)${RESET} Dev Mode        ${GRAY}— install + run with hot reload${RESET}\n"
    printf "  ${BOLD_GREEN}2)${RESET} Production Mode ${GRAY}— install + build + run optimized${RESET}\n"
    printf "  ${BOLD_YELLOW}3)${RESET} Update Website  ${GRAY}— pull latest release from GitHub${RESET}\n"
    printf "  ${BOLD_YELLOW}4)${RESET} Cloudflare Tunnel ${GRAY}— install cloudflared + connect a domain${RESET}\n"
    printf "  ${CYAN}5)${RESET} View Logs\n"
    printf "  ${CYAN}6)${RESET} Re-check System Dependencies\n"
    printf "  ${BOLD_RED}0)${RESET} Exit\n"
    echo
    line
    printf "${YELLOW}Select an option [0-6]: ${RESET}"
    read -r choice

    case "$choice" in
      1) run_dev_mode ;;
      2) run_production_mode ;;
      3) update_website ;;
      4) cloudflare_tunnel_menu ;;
      5) view_logs ;;
      6) banner; check_system_deps; press_enter ;;
      0)
        banner
        printf "${BOLD_MAGENTA}Goodbye from MonoHost Executer Script.${RESET}\n"
        printf "${GRAY}Made by prime.dev1${RESET}\n\n"
        exit 0
        ;;
      *)
        warn "Invalid selection: '$choice' — please choose a number from the menu."
        sleep 1.2
        ;;
    esac
  done
}

# ----------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------
ensure_dirs
main_menu
