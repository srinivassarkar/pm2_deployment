#!/usr/bin/env bash

# ==============================================================================
# DevOps Toolkit - deploy.sh (v1.0.0)
# Lightweight, dependency-free interactive deployment script for PM2-Node services.
# Designed to run in-memory via curl-to-bash:
#   bash <(curl -fsSL https://raw.githubusercontent.com/<user>/deploy-tools/main/deploy.sh)
# ==============================================================================

# Exit on error for critical steps, but manage interactive flows manually
set -u

# --- CONFIGURATION ---
DEFAULT_ROOT="/opt/node"
DEPLOY_ROOT="${DEPLOY_ROOT:-$DEFAULT_ROOT}"

# --- TTY CHECK FOR INTERACTIVE INPUTS ---
if [ -c /dev/tty ] && [ -t 0 ]; then
  TTY_IN="/dev/tty"
else
  TTY_IN="/dev/stdin"
fi

# --- ANSI COLORS & STYLING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- LOGGING FUNCTIONS ---
info() { echo -e "${BLUE}${BOLD}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"; }
error() { echo -e "${RED}${BOLD}[ERROR]${NC} $1" >&2; }
separator() { echo -e "${CYAN}------------------------------------------------------------${NC}"; }

# --- ENFORCE SUDO/ROOT PRIVILEGES ---
if [ "$EUID" -ne 0 ] && [ "${BYPASS_ROOT_CHECK:-0}" -ne 1 ]; then
  error "This script must be run with root privileges (using sudo)."
  echo -e "Please run: ${BOLD}sudo bash <(curl -fsSL ...)${NC} or ${BOLD}sudo ./deploy.sh${NC}"
  exit 1
fi

# --- RENDER BANNER ---
echo -e "${MAGENTA}${BOLD}"
cat << "EOF"
    ____             ____                     ______            __
   / __ \___  ____  / __ \____  _____  ______/_  __/___  ____  / /__(_) ___
  / / / / _ \/ __ \/ / / / __ \/ ___/ / ___/  / / / __ \/ __ \/ / //_/ /| | / /
 / /_/ /  __/ /_/ / /_/ / /_/ (__  ) (__  )  / / / /_/ / /_/ / / ,< / / | |/ /
/_____/\___/ .___/\____/\____/____/ /____/  /_/  \____/\____/_/_/|_/_/  |___/
          /_/
EOF
echo -e "${NC}"
info "DevOps Toolkit - v1.0.0 (Deployment)"
info "Target Deployment Root: ${BOLD}${DEPLOY_ROOT}${NC}"
separator

# --- PREREQUISITE CHECKS ---
check_command() {
  if ! command -v "$1" &> /dev/null; then
    error "Prerequisite command '$1' is not installed or not in PATH."
    exit 1
  fi
}
check_command "git"
check_command "npm"
check_command "pm2"

# --- DISCOVER REPOSITORIES ---
if [ ! -d "$DEPLOY_ROOT" ]; then
  error "Deployment root directory '$DEPLOY_ROOT' does not exist."
  exit 1
fi

REPOS=()
while IFS= read -r -d $'\0' dir; do
  # Check if directory contains a .git folder
  if [ -d "$dir/.git" ]; then
    REPOS+=("$dir")
  fi
done < <(find "$DEPLOY_ROOT" -mindepth 1 -maxdepth 2 -type d -print0 2>/dev/null | sort -z)

if [ ${#REPOS[@]} -eq 0 ]; then
  error "No Git repositories found under '$DEPLOY_ROOT'."
  exit 1
fi

# --- INTERACTIVE REPOSITORY SELECTION ---
echo -e "${CYAN}${BOLD}Discovered repositories:${NC}"
for i in "${!REPOS[@]}"; do
  repo_name=$(basename "${REPOS[$i]}")
  echo -e "  [${BOLD}$((i+1))${NC}] ${repo_name} (${REPOS[$i]})"
done
echo ""

while true; do
  echo -ne "${YELLOW}${BOLD}Select a repository [1-${#REPOS[@]}]: ${NC}"
  read -r repo_choice < "$TTY_IN"
  if [[ "$repo_choice" =~ ^[0-9]+$ ]] && [ "$repo_choice" -ge 1 ] && [ "$repo_choice" -le "${#REPOS[@]}" ]; then
    SELECTED_REPO="${REPOS[$((repo_choice-1))]}"
    SELECTED_REPO_NAME=$(basename "$SELECTED_REPO")
    break
  else
    warn "Invalid choice. Please enter a number between 1 and ${#REPOS[@]}."
  fi
done

success "Selected Repository: ${BOLD}${SELECTED_REPO_NAME}${NC}"
separator

# --- GIT BRANCH SELECTION ---
cd "$SELECTED_REPO" || { error "Failed to enter directory $SELECTED_REPO"; exit 1; }

info "Fetching latest branches from remote..."
git fetch --all --prune --quiet

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
info "Current Branch: ${BOLD}${CURRENT_BRANCH}${NC}"

# Get local and remote branches (excluding HEAD pointer references)
mapfile -t BRANCHES < <(git branch -a --format='%(refname:short)' | grep -v 'HEAD' | sed 's/origin\///' | sort -u)

echo -e "\n${CYAN}${BOLD}Available branches:${NC}"
for i in "${!BRANCHES[@]}"; do
  # Highlight the current branch
  if [ "${BRANCHES[$i]}" == "$CURRENT_BRANCH" ]; then
    echo -e "  [${BOLD}$((i+1))${NC}] ${GREEN}${BRANCHES[$i]} (current)${NC}"
  else
    echo -e "  [${BOLD}$((i+1))${NC}] ${BRANCHES[$i]}"
  fi
done
echo ""

while true; do
  echo -ne "${YELLOW}${BOLD}Select target branch [1-${#BRANCHES[@]} or type custom name]: ${NC}"
  read -r branch_choice < "$TTY_IN"
  
  if [[ "$branch_choice" =~ ^[0-9]+$ ]] && [ "$branch_choice" -ge 1 ] && [ "$branch_choice" -le "${#BRANCHES[@]}" ]; then
    TARGET_BRANCH="${BRANCHES[$((branch_choice-1))]}"
    break
  elif [ -n "$branch_choice" ]; then
    # Custom branch typed by user
    TARGET_BRANCH="$branch_choice"
    break
  else
    warn "Input cannot be empty."
  fi
done

success "Target Branch: ${BOLD}${TARGET_BRANCH}${NC}"
separator

# --- CONFIRM DEPLOYMENT ---
echo -e "${MAGENTA}${BOLD}Deployment Summary:${NC}"
echo -e "  • Repo Directory: ${BOLD}${SELECTED_REPO}${NC}"
echo -e "  • Target Branch:  ${BOLD}${TARGET_BRANCH}${NC}"
echo -e "  • Operations:     git checkout/pull, clean node_modules/dist, npm ci, npm run build, PM2 restart"
echo ""

echo -ne "${YELLOW}${BOLD}Proceed with deployment? (y/N): ${NC}"
read -r confirm_choice < "$TTY_IN"
if [[ ! "$confirm_choice" =~ ^[yY](es)?$ ]]; then
  info "Deployment cancelled."
  exit 0
fi

START_TIME=$(date +%s)
separator

# --- GIT CHECKOUT & PULL ---
info "Switching to branch ${BOLD}${TARGET_BRANCH}${NC}..."
if ! git checkout "$TARGET_BRANCH"; then
  # If local checkout fails, try checking out tracking branch from remote
  if ! git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH" 2>/dev/null; then
    error "Failed to checkout branch $TARGET_BRANCH."
    exit 1
  fi
fi

info "Pulling latest changes..."
if ! git pull origin "$TARGET_BRANCH"; then
  error "Failed to pull latest changes from origin."
  exit 1
fi
success "Git repository updated successfully."

# --- CLEANING DEPENDENCIES ---
info "Removing old build artifacts and dependencies..."
if [ -d "dist" ]; then
  info "Removing 'dist' directory..."
  rm -rf dist
fi
if [ -d "node_modules" ]; then
  info "Removing 'node_modules' directory..."
  rm -rf node_modules
fi
success "Cleanup completed."

# --- INSTALL & BUILD ---
info "Installing dependencies (npm ci)..."
if ! npm ci; then
  error "npm ci failed."
  exit 1
fi
success "Dependencies installed."

info "Building project (npm run build)..."
if ! npm run build; then
  error "npm run build failed."
  exit 1
fi
success "Project built successfully."

# --- PM2 RESTART ---
info "Detecting PM2 process for restart..."
PM2_APP_NAME=""

# 1. Search in global ecosystem.config.json if it exists in DEPLOY_ROOT
ECOSYSTEM_FILE="$DEPLOY_ROOT/ecosystem.config.json"
if [ -f "$ECOSYSTEM_FILE" ]; then
  # Match an app where script path or directory contains the repo name
  # Look for "name" fields near the repo name in the JSON structure
  detected_name=$(grep -B 3 -A 3 "$SELECTED_REPO_NAME" "$ECOSYSTEM_FILE" | grep -m 1 '"name"' | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  if [ -n "$detected_name" ]; then
    PM2_APP_NAME="$detected_name"
    info "Found matching PM2 app in global ecosystem: ${BOLD}${PM2_APP_NAME}${NC}"
  fi
fi

# 2. If not found, look at local package.json name field
if [ -z "$PM2_APP_NAME" ] && [ -f "package.json" ]; then
  detected_name=$(grep -m 1 '"name"' package.json | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  if [ -n "$detected_name" ]; then
    # Verify if this app is currently in PM2 list
    if pm2 show "$detected_name" &>/dev/null; then
      PM2_APP_NAME="$detected_name"
      info "Found active PM2 app matching package.json: ${BOLD}${PM2_APP_NAME}${NC}"
    fi
  fi
fi

# 3. Fallback to repo name if it is in PM2 list
if [ -z "$PM2_APP_NAME" ]; then
  if pm2 show "$SELECTED_REPO_NAME" &>/dev/null; then
    PM2_APP_NAME="$SELECTED_REPO_NAME"
    info "Found active PM2 app matching repo name: ${BOLD}${PM2_APP_NAME}${NC}"
  fi
fi

# Interactive PM2 verification or selection
if [ -n "$PM2_APP_NAME" ]; then
  echo -ne "${YELLOW}${BOLD}Detected PM2 app name is '${PM2_APP_NAME}'. Restart this app? (Y/n/custom): ${NC}"
  read -r pm2_confirm < "$TTY_IN"
  if [[ "$pm2_confirm" =~ ^[nN](o)?$ ]]; then
    PM2_APP_NAME=""
  elif [[ -n "$pm2_confirm" && ! "$pm2_confirm" =~ ^[yY](es)?$ ]]; then
    # Custom app name input
    PM2_APP_NAME="$pm2_confirm"
  fi
fi

if [ -z "$PM2_APP_NAME" ]; then
  warn "Could not auto-detect a running PM2 process. Current active PM2 processes:"
  pm2 list
  echo ""
  echo -ne "${YELLOW}${BOLD}Enter PM2 process name to restart (or press Enter to skip): ${NC}"
  read -r PM2_APP_NAME < "$TTY_IN"
fi

if [ -n "$PM2_APP_NAME" ]; then
  info "Restarting PM2 process '${PM2_APP_NAME}'..."
  if pm2 restart "$PM2_APP_NAME"; then
    success "PM2 process '${PM2_APP_NAME}' restarted."
  else
    error "Failed to restart PM2 process '${PM2_APP_NAME}'."
    exit 1
  fi
else
  warn "PM2 restart skipped."
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
separator

# --- DEPLOYMENT SUMMARY ---
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}                    DEPLOYMENT SUCCESSFUL                   ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "  • ${BOLD}Repository:${NC}  ${SELECTED_REPO_NAME}"
echo -e "  • ${BOLD}Branch:${NC}      ${TARGET_BRANCH}"
echo -e "  • ${BOLD}PM2 Process:${NC} ${PM2_APP_NAME:-Skipped}"
echo -e "  • ${BOLD}Duration:${NC}    ${ELAPSED} seconds"
echo -e "  • ${BOLD}Time:${NC}        $(date)"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
