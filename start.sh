#!/bin/bash

# =============================================================================
# Agent Project Start Script
# Usage: ./start.sh <project-name> [agent]
# Example: ./start.sh proj-playground
#          ./start.sh proj-playground backend_dev
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

log()    { echo -e "${GREEN}[START]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# -----------------------------------------------------------------------------
# Validate arguments
# -----------------------------------------------------------------------------
if [ -z "$1" ]; then
    error "Usage: ./start.sh <project-name> [agent]
Example: ./start.sh proj-playground
         ./start.sh proj-playground backend_dev"
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

[ ! -f "$ENV_FILE" ] && error ".env not found at $ENV_FILE"

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
command -v envsubst >/dev/null 2>&1     || error "envsubst not found. Run: sudo apt install gettext-base"

# -----------------------------------------------------------------------------
# Check Claude credentials
# -----------------------------------------------------------------------------
header "Checking Claude Credentials"

if [ ! -d "$HOME/.claude" ]; then
    error "Claude credentials not found. Please log in with 'claude'."
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
# Resolve active sprint from highest-numbered brief
# -----------------------------------------------------------------------------
header "Resolving Active Sprint"

LATEST_BRIEF=$(ls "$PROJ_DIR/workspace/briefs/brief_"*.md 2>/dev/null | sort -V | tail -1)

[ -z "$LATEST_BRIEF" ] && error "No brief found in $PROJ_DIR/workspace/briefs/
Create one first:
  nano $PROJ_DIR/workspace/briefs/brief_001.md"

# Check brief is not empty / still a placeholder
if grep -q "Replace this file" "$LATEST_BRIEF" 2>/dev/null; then
    error "Brief is still a placeholder: $LATEST_BRIEF
Edit it with your project requirements before running start.sh."
fi

SPRINT_NUM=$(basename "$LATEST_BRIEF" | sed 's/brief_\([0-9]*\)\.md/\1/')
SPRINT_DIR="$PROJ_DIR/workspace/sprints/sprint_${SPRINT_NUM}"
ACTIVE_SPRINT="/home/sandbox/workspace/sprints/sprint_${SPRINT_NUM}"
ACTIVE_BRIEF="/home/sandbox/workspace/briefs/brief_${SPRINT_NUM}.md"

log "Active brief:  brief_${SPRINT_NUM}.md"
log "Active sprint: sprint_${SPRINT_NUM}"

# -----------------------------------------------------------------------------
# Check if active sprint is already complete
# -----------------------------------------------------------------------------
STATUS_FILE="$SPRINT_DIR/status.json"

if [ -f "$STATUS_FILE" ]; then
    SPRINT_STATUS=$(python3 -c "import json,sys; d=json.load(open('$STATUS_FILE')); print(d.get('status',''))" 2>/dev/null || echo "")
    if [ "$SPRINT_STATUS" = "complete" ]; then
        echo ""
        error "sprint_${SPRINT_NUM} is already complete.
To start new work, create a new brief:
  nano $PROJ_DIR/workspace/briefs/brief_$(printf '%03d' $((10#$SPRINT_NUM + 1))).md
Then run start.sh again."
    fi
fi

# -----------------------------------------------------------------------------
# Create sprint folder if new sprint
# -----------------------------------------------------------------------------
if [ ! -d "$SPRINT_DIR" ]; then
    log "New sprint detected — creating sprint_${SPRINT_NUM}/"
    mkdir -p "$SPRINT_DIR"/{tickets,reviews,test_results}
    touch "$SPRINT_DIR/clarifications.md"
    touch "$SPRINT_DIR/decisions.log"
    cat > "$SPRINT_DIR/status.json" <<EOF
{
  "project": "${PROJECT_NAME}",
  "sprint": ${SPRINT_NUM},
  "tickets": {},
  "token_usage": {
    "orchestrator": 0,
    "backend_dev": 0,
    "frontend_dev": 0,
    "infrastructure": 0,
    "reviewer": 0,
    "qc_tester": 0,
    "repo_manager": 0
  }
}
EOF
    log "sprint_${SPRINT_NUM}/ initialized."
fi

# -----------------------------------------------------------------------------
# Pull latest agent-team-base and refresh CLAUDE.md files if updated
# -----------------------------------------------------------------------------
header "Syncing agent-team-base"

if [ -d "$BASE_DIR/.git" ]; then
    git -C "$BASE_DIR" pull --ff-only 2>/dev/null && log "agent-team-base up to date." \
        || warn "Could not pull agent-team-base — using existing version."
else
    warn "agent-team-base not found at $BASE_DIR — skipping sync."
fi

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
# Regenerate docker-compose.yml with active sprint
# -----------------------------------------------------------------------------
header "Generating docker-compose.yml"

export CLAUDE_DIR="$HOME/.claude"
export CLAUDE_JSON="$HOME/.claude.json"
export GITHUB_TOKEN
export GITHUB_REPO
export GITHUB_USER
export ACTIVE_SPRINT
export ACTIVE_BRIEF

envsubst '${CLAUDE_DIR} ${CLAUDE_JSON} ${ACTIVE_SPRINT} ${ACTIVE_BRIEF}' \
    < "$BASE_DIR/agents/shared/docker-compose.template.yml" \
    > "$PROJ_DIR/docker-compose.yml"

log "docker-compose.yml regenerated for sprint_${SPRINT_NUM}."

# -----------------------------------------------------------------------------
# Rebuild images
# -----------------------------------------------------------------------------
header "Rebuilding Docker Images"

cd "$PROJ_DIR"
docker compose build
log "Images rebuilt."

# Ensure sandbox user can write to mounted directories
chmod -R 777 "$PROJ_DIR/proj" "$PROJ_DIR/workspace"

# -----------------------------------------------------------------------------
# Print sprint summary
# -----------------------------------------------------------------------------
header "Sprint ${SPRINT_NUM} Summary"

echo ""
echo -e "  Brief:   $LATEST_BRIEF"

CLARIFICATIONS="$SPRINT_DIR/clarifications.md"
if [ -s "$CLARIFICATIONS" ]; then
    COUNT=$(grep -c . "$CLARIFICATIONS" 2>/dev/null || echo 0)
    echo -e "  Clarifications: $COUNT line(s) in clarifications.md"
else
    echo -e "  Clarifications: none"
fi

SESSION="$SPRINT_DIR/session_latest.md"
if [ -f "$SESSION" ] && [ -s "$SESSION" ]; then
    MODIFIED=$(date -r "$SESSION" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
    echo -e "  Last session:   $MODIFIED"
else
    echo -e "  Last session:   none"
fi

STATUS="$SPRINT_DIR/status.json"
if [ -f "$STATUS" ]; then
    DONE=$(python3 -c "
import json, sys
d = json.load(open('$STATUS'))
tickets = d.get('tickets', {})
total = len(tickets)
done = sum(1 for t in tickets.values() if t.get('status') == 'DONE')
print(f'{done}/{total} tickets done')
" 2>/dev/null || echo "unknown")
    echo -e "  Tickets: $DONE"
fi

echo ""

# -----------------------------------------------------------------------------
# Start agent
# -----------------------------------------------------------------------------
header "Starting ${AGENT:-orchestrator}"

TARGET="${AGENT:-orchestrator}"
log "Launching $TARGET for sprint_${SPRINT_NUM}..."
docker compose run --rm "$TARGET"
