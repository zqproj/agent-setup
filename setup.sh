#!/bin/bash

# =============================================================================
# Agent Project Setup Script
# Usage: ./setup.sh <project-name>
# Example: ./setup.sh my-project
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

log()    { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# -----------------------------------------------------------------------------
# Validate argument
# -----------------------------------------------------------------------------
if [ -z "$1" ]; then
    error "Usage: ./setup.sh <project-name>
Example: ./setup.sh my-project"
fi

PROJECT_NAME="$1"
PROJ_DIR="$HOME/projects/${PROJECT_NAME}"
SETUP_DIR="$HOME/infra/agent-setup"
BASE_DIR="$HOME/infra/agent-team-base"
ENV_FILE="${SETUP_DIR}/.env"

# -----------------------------------------------------------------------------
# Bomb if project folder already exists
# -----------------------------------------------------------------------------
if [ -d "$PROJ_DIR" ]; then
    error "Project folder already exists: $PROJ_DIR
Delete it first if you want to start fresh:
  rm -rf $PROJ_DIR"
fi

# -----------------------------------------------------------------------------
# Load .env
# -----------------------------------------------------------------------------
header "Loading .env"

if [ ! -f "$ENV_FILE" ]; then
    error ".env not found at $ENV_FILE
Create it with:
  GITHUB_TOKEN=your_pat_token
  GITHUB_REPO=https://github.com/zqproj/${PROJECT_NAME}.git
  GITHUB_USER=zqproj"
fi

source "$ENV_FILE"

[ -z "$GITHUB_TOKEN" ] && error "GITHUB_TOKEN is not set in $ENV_FILE"
[ -z "$GITHUB_REPO"  ] && error "GITHUB_REPO is not set in $ENV_FILE"
[ -z "$GITHUB_USER"  ] && error "GITHUB_USER is not set in $ENV_FILE"

log "Project:     $PROJECT_NAME"
log "GitHub user: $GITHUB_USER"
log "GitHub repo: $GITHUB_REPO"

# -----------------------------------------------------------------------------
# Check Claude credentials
# -----------------------------------------------------------------------------
header "Checking Claude Code Login"

if [ ! -d "$HOME/.claude" ]; then
    error "Claude Code credentials not found at ~/.claude
Please run 'claude' on this host first and log in."
fi

if [ ! -f "$HOME/.claude.json" ]; then
    BACKUP=$(ls -t "$HOME/.claude/backups/.claude.json.backup."* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" "$HOME/.claude.json"
        log "Restored .claude.json from backup."
    else
        warn ".claude.json not found and no backup available. You may need to log in again."
    fi
fi

chmod 644 "$HOME/.claude.json" 2>/dev/null || warn "Could not chmod ~/.claude.json"
chmod -R 755 "$HOME/.claude"   2>/dev/null || warn "Could not chmod ~/.claude"
log "Claude credentials found at ~/.claude"

# -----------------------------------------------------------------------------
# Check dependencies
# -----------------------------------------------------------------------------
header "Checking Dependencies"

command -v docker >/dev/null 2>&1       || error "Docker not found."
docker compose version >/dev/null 2>&1 || error "Docker Compose not found."
command -v git >/dev/null 2>&1          || error "Git not found."
command -v envsubst >/dev/null 2>&1     || error "envsubst not found. Run: sudo apt install gettext-base"

log "Docker:         $(docker --version)"
log "Docker Compose: $(docker compose version)"
log "Git:            $(git --version)"

# -----------------------------------------------------------------------------
# Clone or update agent-team-base
# -----------------------------------------------------------------------------
header "Syncing agent-team-base"

mkdir -p "$HOME/infra"

if [ -d "$BASE_DIR/.git" ]; then
    git -C "$BASE_DIR" pull --ff-only
    log "agent-team-base updated at $BASE_DIR"
else
    git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/zqproj/agent-team-base.git" "$BASE_DIR"
    log "agent-team-base cloned to $BASE_DIR"
fi

# -----------------------------------------------------------------------------
# Check or create project repo on GitHub
# -----------------------------------------------------------------------------
header "Checking GitHub Repo"

REPO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/${GITHUB_USER}/${PROJECT_NAME}")

if [ "$REPO_STATUS" = "200" ]; then
    log "Repo found: ${GITHUB_USER}/${PROJECT_NAME}"
else
    echo ""
    warn "Repo not found: ${GITHUB_USER}/${PROJECT_NAME}"
    echo -e "  Do you want to create it now? This might be a typo — double check the name."
    echo -n "  Create '${PROJECT_NAME}'? [y/N] "
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        error "Aborted. Check the project name and try again."
    fi
    curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        https://api.github.com/user/repos \
        -d "{\"name\": \"${PROJECT_NAME}\", \"private\": false, \"auto_init\": true}" \
        | grep '"full_name"' | sed 's/.*: "\(.*\)".*/\1/' | xargs -I{} log "Repo created: {}"
    sleep 2  # give GitHub a moment before cloning
fi

# -----------------------------------------------------------------------------
# Clone project repo
# -----------------------------------------------------------------------------
header "Cloning Project Repo"

mkdir -p "$HOME/projects"
git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@$(echo $GITHUB_REPO | sed 's|https://||')" "$PROJ_DIR"
log "Project repo cloned to $PROJ_DIR"

cd "$PROJ_DIR"

# -----------------------------------------------------------------------------
# Create folder structure
# -----------------------------------------------------------------------------
header "Creating Folder Structure"

# Project code structure
mkdir -p proj/src/backend
mkdir -p proj/src/frontend/templates
mkdir -p proj/src/frontend/styles
mkdir -p proj/src/shared
mkdir -p proj/tests
mkdir -p proj/assets
mkdir -p proj/docs
mkdir -p proj/scripts
mkdir -p proj/config/dev
mkdir -p proj/config/prod
mkdir -p proj/dist
touch proj/src/__init__.py
touch proj/src/backend/__init__.py
touch proj/src/frontend/__init__.py

# Agent definitions
mkdir -p agents/{orchestrator,backend_dev,frontend_dev,infrastructure,reviewer,qc_tester,repo_manager}

# Shared runtime state — briefs (you write) and sprints (agents write)
mkdir -p workspace/briefs
mkdir -p workspace/sprints

log "Folder structure created."

# -----------------------------------------------------------------------------
# Copy agent artifacts from agent-team-base
# -----------------------------------------------------------------------------
header "Copying Agent Artifacts from agent-team-base"

AGENTS="orchestrator backend_dev frontend_dev infrastructure reviewer qc_tester repo_manager"

for agent in $AGENTS; do
    # Only CLAUDE.md is agent-specific — Dockerfile and entrypoint.sh
    # are shared and referenced directly from agents/shared/ at build time
    cp "$BASE_DIR/agents/${agent}/CLAUDE.md" "agents/${agent}/CLAUDE.md"
    log "Copied CLAUDE.md for ${agent}"
done

# Copy shared directory (Dockerfile + entrypoint.sh live here)
cp -r "$BASE_DIR/agents/shared" agents/shared

log "All agent artifacts copied."

# -----------------------------------------------------------------------------
# Generate docker-compose.yml from template
# -----------------------------------------------------------------------------
header "Generating docker-compose.yml"

# Export vars needed by the template
export CLAUDE_DIR="$HOME/.claude"
export CLAUDE_JSON="$HOME/.claude.json"
export GITHUB_TOKEN
export GITHUB_REPO
export GITHUB_USER

# Sprint 001 is always the starting sprint
export ACTIVE_SPRINT="/home/sandbox/workspace/sprints/sprint_001"
export ACTIVE_BRIEF="/home/sandbox/workspace/briefs/brief_001.md"

# envsubst substitutes host-resolved and sprint vars; docker-compose handles the rest at runtime
envsubst '${CLAUDE_DIR} ${CLAUDE_JSON} ${ACTIVE_SPRINT} ${ACTIVE_BRIEF}' \
    < "$BASE_DIR/agents/shared/docker-compose.template.yml" \
    > docker-compose.yml

log "docker-compose.yml generated."

# -----------------------------------------------------------------------------
# Copy .env into project for docker compose runtime
# -----------------------------------------------------------------------------
cp "$ENV_FILE" .env
log ".env copied."

# -----------------------------------------------------------------------------
# Seed brief_001.md placeholder
# -----------------------------------------------------------------------------
header "Creating Initial Brief"

cat > workspace/briefs/brief_001.md <<EOF
# Project Brief — Sprint 1

Replace this file with your project requirements before running start.sh.

## What to include
- What you want to build
- The tech stack (if you have a preference)
- Any constraints or special requirements
- Definition of done for this sprint
EOF

log "workspace/briefs/brief_001.md created — edit this before running start.sh"

# -----------------------------------------------------------------------------
# Initialize sprint_001/status.json
# -----------------------------------------------------------------------------
header "Initializing Sprint 001"

mkdir -p workspace/sprints/sprint_001/{tickets,reviews,test_results}

cat > workspace/sprints/sprint_001/status.json <<EOF
{
  "project": "${PROJECT_NAME}",
  "sprint": 1,
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

touch workspace/sprints/sprint_001/clarifications.md
touch workspace/sprints/sprint_001/decisions.log

log "workspace/sprints/sprint_001/ initialized."

# -----------------------------------------------------------------------------
# Update .gitignore
# -----------------------------------------------------------------------------
header "Updating .gitignore"

for entry in \
    ".env" \
    "proj/.venv/" \
    "proj/dist/" \
    "proj/__pycache__/" \
    "proj/src/**/__pycache__/"; do
    if ! grep -qF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
    fi
done

log ".gitignore updated."

# -----------------------------------------------------------------------------
# Configure git
# -----------------------------------------------------------------------------
header "Configuring Git"

git config user.name "${GITHUB_USER}"
git config user.email "${GITHUB_USER}@users.noreply.github.com"
git remote set-url origin "https://${GITHUB_USER}:${GITHUB_TOKEN}@$(echo $GITHUB_REPO | sed 's|https://||')"
git checkout -b dev 2>/dev/null || git checkout dev

log "Git configured on dev branch."

# -----------------------------------------------------------------------------
# Initial commit and push
# -----------------------------------------------------------------------------
header "Pushing Initial Structure"

git add .
git commit -m "chore: bootstrap ${PROJECT_NAME} agent project structure" || warn "Nothing to commit."
git push origin dev || warn "Push failed — check GITHUB_TOKEN and repo URL."

log "Initial structure pushed to dev."

# -----------------------------------------------------------------------------
# Build Docker images
# -----------------------------------------------------------------------------
header "Building Docker Images"
echo "This may take a few minutes..."

docker compose build

# Ensure sandbox user inside containers can write to mounted directories
chmod -R 777 "$PROJ_DIR/proj" "$PROJ_DIR/workspace"

log "Docker images built."

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
header "Setup Complete"

echo ""
echo -e "${GREEN}Ready!${NC}"
echo ""
echo "Project: $PROJ_DIR"
echo ""
echo "Structure:"
echo "  proj/src/backend/                  <- backend / API code"
echo "  proj/src/frontend/templates/       <- HTML templates"
echo "  proj/tests/                        <- test suite"
echo "  proj/scripts/                      <- run/deploy scripts"
echo "  proj/docs/                         <- documentation"
echo "  proj/config/                       <- environment configs"
echo "  agents/                            <- agent definitions"
echo "  workspace/briefs/brief_001.md      <- edit this before running start.sh"
echo "  workspace/sprints/sprint_001/      <- agent output for sprint 1"
echo ""
echo "Next steps:"
echo "  1. Edit your project brief:"
echo "     nano $PROJ_DIR/workspace/briefs/brief_001.md"
echo "  2. Run start.sh:"
echo "     ./start.sh $PROJECT_NAME"
echo ""
