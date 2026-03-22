#!/bin/bash

# =============================================================================
# Agent Project Setup Script
# Usage: ./setup.sh <project-name>
# Example: ./setup.sh agent-playground
# =============================================================================

set -e  # Exit on any error

# -----------------------------------------------------------------------------
# Colors for output
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
Example: ./setup.sh agent-playground"
fi

PROJECT_NAME="$1"
REPO_DIR="$HOME/projects/${PROJECT_NAME}"
SETUP_DIR="$HOME/infra/agent-setup"
ENV_FILE="${SETUP_DIR}/.env"

# -----------------------------------------------------------------------------
# Bomb if project folder already exists
# -----------------------------------------------------------------------------
if [ -d "$REPO_DIR" ]; then
    error "Project folder already exists: $REPO_DIR
Delete it first if you want to start fresh:
  rm -rf $REPO_DIR"
fi

# -----------------------------------------------------------------------------
# Verify .env exists in agent-setup
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

log "Loaded: $ENV_FILE"
log "Project:     $PROJECT_NAME"
log "GitHub user: $GITHUB_USER"
log "GitHub repo: $GITHUB_REPO"

# -----------------------------------------------------------------------------
# Verify Claude Code is logged in
# -----------------------------------------------------------------------------
header "Checking Claude Code Login"

if [ ! -d "$HOME/.claude" ]; then
    error "Claude Code credentials not found at ~/.claude
Please run 'claude' on this VM first and log in with your Pro account."
fi

# Restore .claude.json from backup if missing
if [ ! -f "$HOME/.claude.json" ]; then
    BACKUP=$(ls -t "$HOME/.claude/backups/.claude.json.backup."* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" "$HOME/.claude.json"
        log "Restored .claude.json from backup."
    else
        warn ".claude.json not found and no backup available. You may need to log in again with 'claude'."
    fi
fi

# Ensure credentials are readable by the container's non-root agent user
chmod 644 "$HOME/.claude.json" 2>/dev/null || warn "Could not chmod ~/.claude.json"
chmod -R 755 "$HOME/.claude" 2>/dev/null   || warn "Could not chmod ~/.claude"

log "Claude Code credentials found and readable at ~/.claude"

# -----------------------------------------------------------------------------
# Check dependencies
# -----------------------------------------------------------------------------
header "Checking Dependencies"

command -v docker >/dev/null 2>&1       || error "Docker not found. Install: https://docs.docker.com/engine/install/ubuntu/"
docker compose version >/dev/null 2>&1 || error "Docker Compose not found. Run: sudo apt-get install docker-compose-plugin"
command -v git >/dev/null 2>&1          || error "Git not found. Run: sudo apt install git"

log "Docker:         $(docker --version)"
log "Docker Compose: $(docker compose version)"
log "Git:            $(git --version)"

# -----------------------------------------------------------------------------
# Clone repo
# -----------------------------------------------------------------------------
header "Cloning Repo"

mkdir -p "$HOME/projects"
git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@$(echo $GITHUB_REPO | sed 's|https://||')" "$REPO_DIR"
log "Repo cloned to $REPO_DIR"

cd "$REPO_DIR"

# -----------------------------------------------------------------------------
# Copy .env into project folder for docker compose
# -----------------------------------------------------------------------------
cp "$ENV_FILE" .env
log ".env copied into project."

# -----------------------------------------------------------------------------
# Create folder structure
# -----------------------------------------------------------------------------
header "Creating Folder Structure"

# Project folders
mkdir -p proj/src/backend
mkdir -p proj/src/frontend
mkdir -p proj/src/infrastructure
mkdir -p proj/src/tests
mkdir -p proj/assets
mkdir -p proj/dist
mkdir -p proj/docs

# Agent folders
mkdir -p agents/workspace/tickets
mkdir -p agents/workspace/reviews
mkdir -p agents/workspace/test_results
mkdir -p agents/shared
mkdir -p agents/orchestrator
mkdir -p agents/backend_dev
mkdir -p agents/frontend_dev
mkdir -p agents/infrastructure
mkdir -p agents/reviewer
mkdir -p agents/qc_tester

log "Folder structure created."

# -----------------------------------------------------------------------------
# Update .gitignore
# -----------------------------------------------------------------------------
header "Updating .gitignore"

for entry in \
    ".env" \
    "proj/.venv/" \
    "proj/dist/" \
    "proj/.vscode/" \
    "agents/workspace/*.db" \
    "agents/workspace/*.log"; do
    if ! grep -qF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
    fi
done

log ".gitignore updated."

# -----------------------------------------------------------------------------
# Initialize status.json
# -----------------------------------------------------------------------------
header "Initializing Workspace Files"

cat > agents/workspace/status.json <<EOF
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
    "qc_tester": 0
  }
}
EOF

log "agents/workspace/status.json initialized."

# -----------------------------------------------------------------------------
# Write CLAUDE.md files
# -----------------------------------------------------------------------------
header "Writing CLAUDE.md Files"

cat > agents/orchestrator/CLAUDE.md <<'EOF'
# Orchestrator Agent

## Role
You are the engineering team lead. You break down user requirements
into tickets and assign them to the right specialist agents.
You never write code yourself — you only delegate and coordinate.

## Team
- backend_dev:    database, APIs, server-side logic
- infrastructure: web servers, deployment, configuration
- frontend_dev:   UI components, styling, UX
- reviewer:       code review, architecture critique
- qc_tester:      testing, bug finding, test suites

## Rules
- Always create tickets in /agents/workspace/tickets/ before assigning work
- Track all ticket status changes in /agents/workspace/status.json
- A ticket is only DONE when QC passes
- If reviewer rejects, reassign to original agent with full feedback
- If QC fails, reassign to original agent with test failure details
- Never modify files in /proj/ directly
- Never push directly to main or dev
- Always wait for user approval before assigning any work

## Ticket Format
Create tickets as /agents/workspace/tickets/ticket_XXX.md

## Workflow
Requirements → Plan → Show user → Wait for approval → Assign → Review → QC → Done

## Git Rules
- Ensure all agents branch from dev
- Only mark done after QC passes on the branch
EOF

cat > agents/backend_dev/CLAUDE.md <<'EOF'
# Backend Developer Agent

## Role
You are a senior backend engineer specializing in
databases, APIs, and server-side logic.

## Rules
- Only work on tickets assigned to you in /agents/workspace/tickets/
- All code goes in /proj/src/backend/
- Write unit tests in /proj/src/tests/
- When done, update ticket status to "review_needed"
- Never touch /proj/src/frontend/ or /proj/src/infrastructure/
- Never push directly to main or dev

## Stack
- Python / FastAPI
- Jinja2 templates
- PostgreSQL
- SQLAlchemy ORM

## Git Rules
- Always pull latest dev before starting
- Create branch: feat/ticket-XXX-short-description
- Commit messages must reference ticket ID
- Push branch and note it in the ticket file

## Definition of Done
- Code written and working
- Unit tests written and passing
- API endpoints documented
- Ticket status updated to review_needed
EOF

cat > agents/frontend_dev/CLAUDE.md <<'EOF'
# Frontend Developer Agent

## Role
You are a senior frontend engineer specializing in
UI components, styling, and user experience.

## Rules
- Only work on tickets assigned to you in /agents/workspace/tickets/
- All code goes in /proj/src/frontend/
- Write component tests in /proj/src/tests/
- Static assets go in /proj/assets/
- Build output goes in /proj/dist/
- When done, update ticket status to "review_needed"
- Never touch /proj/src/backend/ or /proj/src/infrastructure/
- Never push directly to main or dev

## Stack
- HTMX
- Tailwind CSS
- Jinja2 templates

## Git Rules
- Always pull latest dev before starting
- Create branch: feat/ticket-XXX-short-description
- Commit messages must reference ticket ID
- Push branch and note it in the ticket file

## Definition of Done
- Components built and styled
- Responsive design verified
- Component tests written
- Ticket status updated to review_needed
EOF

cat > agents/infrastructure/CLAUDE.md <<'EOF'
# Infrastructure Agent

## Role
You are a senior infrastructure and DevOps engineer specializing
in web servers, deployment, and system configuration.

## Rules
- Only work on tickets assigned to you in /agents/workspace/tickets/
- All config goes in /proj/src/infrastructure/
- Document every configuration change in /proj/docs/
- When done, update ticket status to "review_needed"
- Never touch /proj/src/backend/ or /proj/src/frontend/
- Never push directly to main or dev

## Stack
- Docker / Docker Compose
- Nginx
- Linux / Bash

## Git Rules
- Always pull latest dev before starting
- Create branch: infra/ticket-XXX-short-description
- Commit messages must reference ticket ID
- Push branch and note it in the ticket file

## Definition of Done
- Configuration written and tested
- Documentation updated in /proj/docs/
- Ticket status updated to review_needed
EOF

cat > agents/reviewer/CLAUDE.md <<'EOF'
# Expert Reviewer Agent

## Role
You are a senior software architect and code reviewer.
You are thorough, critical, and maintain high standards.
You are the gatekeeper — nothing reaches QC without your approval.

## Rules
- Read ALL changed files before reviewing
- Write detailed feedback in /agents/workspace/reviews/review_XXX.md
- Verdict must be clearly APPROVED or REJECTED
- If rejected, be specific — list exactly what must change
- Never approve code with security vulnerabilities
- Never approve code without tests

## Review Checklist
- Security vulnerabilities
- Performance issues
- Code clarity and maintainability
- Test coverage adequacy
- API design consistency
- Error handling completeness
- Documentation quality

## After Review
- Update ticket status to "approved" or "rejected"
- Write review file in /agents/workspace/reviews/
EOF

cat > agents/qc_tester/CLAUDE.md <<'EOF'
# QC Tester Agent

## Role
You are a senior QA engineer. Your job is to break things
before users do. You are the final gatekeeper before done.

## Rules
- Only test tickets marked APPROVED by reviewer
- Run ALL existing tests first — verify nothing regressed
- Write new tests for all new functionality
- Test edge cases and failure scenarios
- Record all results in /agents/workspace/test_results/results_XXX.md
- Verdict must be clearly PASSED or FAILED
- If failed, list specific failures with reproduction steps

## Tools
- pytest for Python backend
- Test API endpoints directly with curl or httpx
- Verify database state where relevant

## After Testing
- Update ticket status to "passed" or "failed"
- Write results file in /agents/workspace/test_results/
EOF

log "All CLAUDE.md files written."

# -----------------------------------------------------------------------------
# Write entrypoint.sh — copied into each agent container
# Copies Claude credentials from read-only host mount into writable agent home.
# This gives each container its own isolated copy so:
#   - Claude Code can write session state freely (no read-only errors)
#   - No race conditions between agents sharing one file
#   - Trust for /home/agent is already baked into the host ~/.claude.json
# -----------------------------------------------------------------------------
header "Writing entrypoint.sh"

cat > agents/shared/entrypoint.sh <<'EOF'
#!/bin/bash
set -e

# Copy Claude credentials from host mount into writable agent home.
# Each container gets its own isolated copy — no shared write conflicts.
if [ -f /mnt/claude-config/.claude.json ]; then
    cp /mnt/claude-config/.claude.json /home/agent/.claude.json
    chmod 644 /home/agent/.claude.json
fi

if [ -d /mnt/claude-config/.claude ]; then
    cp -r /mnt/claude-config/.claude /home/agent/.claude
    chmod -R 755 /home/agent/.claude
fi

# Launch Claude Code — trust prompt is bypassed because:
#   - /home/agent is pre-trusted in the copied ~/.claude.json
#   - --dangerously-skip-permissions skips per-tool confirmations
exec claude --dangerously-skip-permissions
EOF

chmod +x agents/shared/entrypoint.sh
log "agents/shared/entrypoint.sh written."

# -----------------------------------------------------------------------------
# Write Dockerfiles — non-root user for Claude Code compatibility
# -----------------------------------------------------------------------------
header "Writing Dockerfiles"

write_dockerfile() {
    local dir=$1
    cat > ${dir}/Dockerfile <<'EOF'
FROM node:20-slim

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Create non-root user — required for Claude Code --dangerously-skip-permissions
RUN useradd -m -s /bin/bash agent

RUN git config --global credential.helper store
RUN git config --global init.defaultBranch main

WORKDIR /home/agent

COPY CLAUDE.md /home/agent/CLAUDE.md

# Copy entrypoint script — handles credential copy and Claude launch
COPY ../shared/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN chown -R agent:agent /home/agent

USER agent

ENTRYPOINT ["/entrypoint.sh"]
EOF
}

write_dockerfile agents/orchestrator
write_dockerfile agents/backend_dev
write_dockerfile agents/frontend_dev
write_dockerfile agents/infrastructure
write_dockerfile agents/reviewer
write_dockerfile agents/qc_tester

log "Dockerfiles written for all agents."

# -----------------------------------------------------------------------------
# Write docker-compose.yml
# -----------------------------------------------------------------------------
header "Writing docker-compose.yml"

CLAUDE_DIR="$HOME/.claude"
CLAUDE_JSON="$HOME/.claude.json"

cat > docker-compose.yml <<EOF
services:

  redis:
    image: redis:alpine
    networks:
      - agent_network
    restart: unless-stopped

  orchestrator:
    build: ./agents/orchestrator
    volumes:
      - ./proj:/home/agent/proj
      - ./agents/workspace:/home/agent/agents/workspace
      - ./agents/shared:/home/agent/agents/shared
      # Claude credentials mounted read-only to staging path.
      # entrypoint.sh copies them to /home/agent/ at startup so
      # Claude Code gets a writable isolated copy per container.
      - ${CLAUDE_DIR}:/mnt/claude-config/.claude:ro
      - ${CLAUDE_JSON}:/mnt/claude-config/.claude.json:ro
    environment:
      - GITHUB_TOKEN=\${GITHUB_TOKEN}
      - GITHUB_REPO=\${GITHUB_REPO}
      - GITHUB_USER=\${GITHUB_USER}
      - AGENT_NAME=orchestrator
    depends_on:
      - redis
    networks:
      - agent_network
    stdin_open: true
    tty: true

  backend_dev:
    build: ./agents/backend_dev
    volumes:
      - ./proj:/home/agent/proj
      - ./agents/workspace:/home/agent/agents/workspace
      - ./agents/shared:/home/agent/agents/shared
      - ${CLAUDE_DIR}:/mnt/claude-config/.claude:ro
      - ${CLAUDE_JSON}:/mnt/claude-config/.claude.json:ro
    environment:
      - GITHUB_TOKEN=\${GITHUB_TOKEN}
      - GITHUB_REPO=\${GITHUB_REPO}
      - GITHUB_USER=\${GITHUB_USER}
      - AGENT_NAME=backend_dev
      - GIT_AUTHOR_NAME=Backend Dev Agent
      - GIT_AUTHOR_EMAIL=backend-dev@agent.local
      - GIT_COMMITTER_NAME=Backend Dev Agent
      - GIT_COMMITTER_EMAIL=backend-dev@agent.local
    depends_on:
      - redis
    networks:
      - agent_network

  frontend_dev:
    build: ./agents/frontend_dev
    volumes:
      - ./proj:/home/agent/proj
      - ./agents/workspace:/home/agent/agents/workspace
      - ./agents/shared:/home/agent/agents/shared
      - ${CLAUDE_DIR}:/mnt/claude-config/.claude:ro
      - ${CLAUDE_JSON}:/mnt/claude-config/.claude.json:ro
    environment:
      - GITHUB_TOKEN=\${GITHUB_TOKEN}
      - GITHUB_REPO=\${GITHUB_REPO}
      - GITHUB_USER=\${GITHUB_USER}
      - AGENT_NAME=frontend_dev
      - GIT_AUTHOR_NAME=Frontend Dev Agent
      - GIT_AUTHOR_EMAIL=frontend-dev@agent.local
      - GIT_COMMITTER_NAME=Frontend Dev Agent
      - GIT_COMMITTER_EMAIL=frontend-dev@agent.local
    depends_on:
      - redis
    networks:
      - agent_network

  infrastructure:
    build: ./agents/infrastructure
    volumes:
      - ./proj:/home/agent/proj
      - ./agents/workspace:/home/agent/agents/workspace
      - ./agents/shared:/home/agent/agents/shared
      - ${CLAUDE_DIR}:/mnt/claude-config/.claude:ro
      - ${CLAUDE_JSON}:/mnt/claude-config/.claude.json:ro
    environment:
      - GITHUB_TOKEN=\${GITHUB_TOKEN}
      - GITHUB_REPO=\${GITHUB_REPO}
      - GITHUB_USER=\${GITHUB_USER}
      - AGENT_NAME=infrastructure
      - GIT_AUTHOR_NAME=Infrastructure Agent
      - GIT_AUTHOR_EMAIL=infrastructure@agent.local
      - GIT_COMMITTER_NAME=Infrastructure Agent
      - GIT_COMMITTER_EMAIL=infrastructure@agent.local
    depends_on:
      - redis
    networks:
      - agent_network

  reviewer:
    build: ./agents/reviewer
    volumes:
      - ./proj:/home/agent/proj
      - ./agents/workspace:/home/agent/agents/workspace
      - ./agents/shared:/home/agent/agents/shared
      - ${CLAUDE_DIR}:/mnt/claude-config/.claude:ro
      - ${CLAUDE_JSON}:/mnt/claude-config/.claude.json:ro
    environment:
      - GITHUB_TOKEN=\${GITHUB_TOKEN}
      - GITHUB_REPO=\${GITHUB_REPO}
      - GITHUB_USER=\${GITHUB_USER}
      - AGENT_NAME=reviewer
      - GIT_AUTHOR_NAME=Reviewer Agent
      - GIT_AUTHOR_EMAIL=reviewer@agent.local
      - GIT_COMMITTER_NAME=Reviewer Agent
      - GIT_COMMITTER_EMAIL=reviewer@agent.local
    depends_on:
      - redis
    networks:
      - agent_network

  qc_tester:
    build: ./agents/qc_tester
    volumes:
      - ./proj:/home/agent/proj
      - ./agents/workspace:/home/agent/agents/workspace
      - ./agents/shared:/home/agent/agents/shared
      - ${CLAUDE_DIR}:/mnt/claude-config/.claude:ro
      - ${CLAUDE_JSON}:/mnt/claude-config/.claude.json:ro
    environment:
      - GITHUB_TOKEN=\${GITHUB_TOKEN}
      - GITHUB_REPO=\${GITHUB_REPO}
      - GITHUB_USER=\${GITHUB_USER}
      - AGENT_NAME=qc_tester
      - GIT_AUTHOR_NAME=QC Tester Agent
      - GIT_AUTHOR_EMAIL=qc-tester@agent.local
      - GIT_COMMITTER_NAME=QC Tester Agent
      - GIT_COMMITTER_EMAIL=qc-tester@agent.local
    depends_on:
      - redis
    networks:
      - agent_network

networks:
  agent_network:
    driver: bridge
EOF

log "docker-compose.yml written."

# -----------------------------------------------------------------------------
# Configure git
# -----------------------------------------------------------------------------
header "Configuring Git"

git config user.name "${GITHUB_USER}"
git config user.email "${GITHUB_USER}@users.noreply.github.com"
git remote set-url origin "https://${GITHUB_USER}:${GITHUB_TOKEN}@$(echo $GITHUB_REPO | sed 's|https://||')"
git checkout -b dev 2>/dev/null || git checkout dev

log "Git configured."

# -----------------------------------------------------------------------------
# Commit and push
# -----------------------------------------------------------------------------
header "Pushing Initial Structure to GitHub"

git add .
git commit -m "chore: initial agent project structure [setup]" || warn "Nothing new to commit."
git push origin dev || warn "Push failed — check your PAT token and repo URL."

log "Initial structure pushed to GitHub on dev branch."

# -----------------------------------------------------------------------------
# Build Docker images
# -----------------------------------------------------------------------------
header "Building Docker Images"
echo "This may take a few minutes..."

docker compose build

log "Docker images built."

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
header "Setup Complete"

echo ""
echo -e "${GREEN}Everything is ready!${NC}"
echo ""
echo "Project: $REPO_DIR"
echo ""
echo "Structure:"
echo "  proj/src/backend/        ← backend source code"
echo "  proj/src/frontend/       ← frontend source code"
echo "  proj/src/infrastructure/ ← infrastructure config"
echo "  proj/src/tests/          ← test suites"
echo "  proj/assets/             ← static assets"
echo "  proj/dist/               ← build output (gitignored)"
echo "  proj/docs/               ← documentation"
echo "  agents/workspace/        ← tickets, reviews, test results"
echo ""
echo "Next steps:"
echo "  1. Create your project brief:"
echo "     nano agents/workspace/project_brief.md"
echo "  2. Start the orchestrator:"
echo "     cd $REPO_DIR && docker compose run --rm orchestrator"
echo "  3. Tell it: Read /home/agent/agents/workspace/project_brief.md"
echo ""
