#!/bin/bash

# =============================================================================
# Agent Project Restart Script
# Usage: ./restart.sh <project-name> [agent]
# Example: ./restart.sh proj-playground
#          ./restart.sh proj-playground orchestrator
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[RESTART]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# -----------------------------------------------------------------------------
# Validate argument
# -----------------------------------------------------------------------------
if [ -z "$1" ]; then
    error "Usage: ./restart.sh <project-name> [agent]
Example: ./restart.sh proj-playground
         ./restart.sh proj-playground orchestrator"
fi

PROJECT_NAME="$1"
AGENT="${2:-}"
PROJ_DIR="$HOME/projects/${PROJECT_NAME}"
SETUP_DIR="$HOME/infra/agent-setup"
BASE_DIR="$HOME/infra/agent-team-base"
ENV_FILE="${SETUP_DIR}/.env"

# -----------------------------------------------------------------------------
# Bomb if project does not exist
# -----------------------------------------------------------------------------
if [ ! -d "$PROJ_DIR" ]; then
    error "Project not found: $PROJ_DIR
Run setup.sh first:
  ./setup.sh $PROJECT_NAME"
fi

# -----------------------------------------------------------------------------
# Load .env
# -----------------------------------------------------------------------------
header "Loading .env"

if [ ! -f "$ENV_FILE" ]; then
    error ".env not found at $ENV_FILE"
fi

source "$ENV_FILE"

[ -z "$GITHUB_TOKEN" ] && error "GITHUB_TOKEN is not set in $ENV_FILE"
[ -z "$GITHUB_REPO"  ] && error "GITHUB_REPO is not set in $ENV_FILE"
[ -z "$GITHUB_USER"  ] && error "GITHUB_USER is not set in $ENV_FILE"

log "Project: $PROJECT_NAME"

# -----------------------------------------------------------------------------
# Check dependencies
# -----------------------------------------------------------------------------
header "Checking Dependencies"

command -v docker >/dev/null 2>&1       || error "Docker not found."
docker compose version >/dev/null 2>&1 || error "Docker Compose not found."

# -----------------------------------------------------------------------------
# Check Claude credentials
# -----------------------------------------------------------------------------
header "Checking Claude Credentials"

if [ ! -d "$HOME/.claude" ]; then
    error "Claude credentials not found at ~/.claude. Please log in with 'claude'."
fi

if [ ! -f "$HOME/.claude.json" ]; then
    BACKUP=$(ls -t "$HOME/.claude/backups/.claude.json.backup."* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" "$HOME/.claude.json"
        log "Restored .claude.json from backup."
    else
        error ".claude.json not found and no backup available. Please log in with 'claude'."
    fi
fi

chmod 644 "$HOME/.claude.json" 2>/dev/null || warn "Could not chmod ~/.claude.json"
chmod -R 755 "$HOME/.claude"   2>/dev/null || warn "Could not chmod ~/.claude"
log "Claude credentials OK."

# -----------------------------------------------------------------------------
# Pull latest agent-team-base (picks up any CLAUDE.md updates)
# -----------------------------------------------------------------------------
header "Syncing agent-team-base"

if [ -d "$BASE_DIR/.git" ]; then
    git -C "$BASE_DIR" pull --ff-only && log "agent-team-base up to date." || warn "Could not pull agent-team-base — using existing version."
else
    warn "agent-team-base not found at $BASE_DIR — skipping sync."
fi

# -----------------------------------------------------------------------------
# Refresh CLAUDE.md files if agent-team-base was updated
# -----------------------------------------------------------------------------
header "Refreshing Agent CLAUDE.md Files"

AGENTS="orchestrator backend_dev frontend_dev infrastructure reviewer qc_tester repo_manager"

for agent in $AGENTS; do
    SRC="$BASE_DIR/agents/${agent}/CLAUDE.md"
    DEST="$PROJ_DIR/agents/${agent}/CLAUDE.md"
    if [ -f "$SRC" ] && [ -f "$DEST" ]; then
        if ! diff -q "$SRC" "$DEST" >/dev/null 2>&1; then
            cp "$SRC" "$DEST"
            log "Updated CLAUDE.md for ${agent}"
        fi
    fi
done

# -----------------------------------------------------------------------------
# Rebuild images
# -----------------------------------------------------------------------------
header "Rebuilding Docker Images"

cd "$PROJ_DIR"
docker compose build
log "Images rebuilt."

# -----------------------------------------------------------------------------
# Print workspace state
# -----------------------------------------------------------------------------
header "Current Workspace State"

STATUS_FILE="$PROJ_DIR/workspace/status.json"
if [ -f "$STATUS_FILE" ]; then
    echo ""
    cat "$STATUS_FILE"
    echo ""
else
    warn "workspace/status.json not found."
fi

# -----------------------------------------------------------------------------
# Start agent(s)
# -----------------------------------------------------------------------------
header "Starting Agent(s)"

cd "$PROJ_DIR"

if [ -n "$AGENT" ]; then
    log "Starting $AGENT..."
    docker compose run --rm "$AGENT"
else
    log "Starting orchestrator..."
    docker compose run --rm orchestrator
fi
