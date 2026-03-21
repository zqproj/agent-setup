#!/bin/bash

# =============================================================================
# Agent Project Setup Script
# Run this once on your Ubuntu sandbox VM from your home directory
# Usage: chmod +x setup.sh && ./setup.sh
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
# Verify Claude Code is logged in
# -----------------------------------------------------------------------------
header "Checking Claude Code Login"

if [ ! -d "$HOME/.claude" ]; then
    error "Claude Code credentials not found at ~/.claude
Please run 'claude' on this VM first and log in with your Pro account."
fi

log "Claude Code credentials found at ~/.claude"

# -----------------------------------------------------------------------------
# Collect credentials
# -----------------------------------------------------------------------------
header "Credentials"

read -p "Enter your GitHub PAT token: " GITHUB_TOKEN
if [ -z "$GITHUB_TOKEN" ]; then error "GitHub PAT token cannot be empty."; fi

read -p "Enter your GitHub repo URL (e.g. https://github.com/zqproj/agent-playground.git): " GITHUB_REPO
if [ -z "$GITHUB_REPO" ]; then error "GitHub repo URL cannot be empty."; fi

read -p "Enter your GitHub bot username (e.g. zqproj): " GITHUB_USER
if [ -z "$GITHUB_USER" ]; then error "GitHub username cannot be empty."; fi

# -----------------------------------------------------------------------------
# Check dependencies
# -----------------------------------------------------------------------------
header "Checking Dependencies"

command -v docker >/dev/null 2>&1         || error "Docker not found. Install Docker first: https://docs.docker.com/engine/install/ubuntu/"
command -v docker-compose >/dev/null 2>&1 || error "Docker Compose not found. Install it first."
command -v git >/dev/null 2>&1            || error "Git not found. Run: sudo apt install git"

log "Docker:         $(docker --version)"
log "Docker Compose: $(docker-compose --version)"
log "Git:            $(git --version)"

# -----------------------------------------------------------------------------
# Clone the agent-playground repo
# -----------------------------------------------------------------------------
header "Cloning Agent Playground Repo"

REPO_DIR="$HOME/agent-playground"

if [ -d "$REPO_DIR" ]; then
    warn "Directory $REPO_DIR already exists — skipping clone."
else
    git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@$(echo $GITHUB_REPO | sed 's|https://||')" "$REPO_DIR"
    log "Repo cloned to $REPO_DIR"
fi

cd "$REPO_DIR"

# -----------------------------------------------------------------------------
# Create folder structure
# -----------------------------------------------------------------------------
header "Creating Folder Structure"

mkdir -p workspace/tickets
mkdir -p workspace/reviews
mkdir -p workspace/test_results
mkdir -p codebase/backend
mkdir -p codebase/frontend
mkdir -p codebase/infrastructure
mkdir -p codebase/tests
mkdir -p shared
mkdir -p orchestrator
mkdir -p backend_dev
mkdir -p frontend_dev
mkdir -p infrastructure
mkdir -p reviewer
mkdir -p qc_tester

log "Folder structure created."

# -----------------------------------------------------------------------------
# Create .env file (no Anthropic key — using ~/.claude mount instead)
# -----------------------------------------------------------------------------
header "Creating .env File"

cat > .env <<EOF
GITHUB_TOKEN=${GITHUB_TOKEN}
GITHUB_REPO=${GITHUB_REPO}
GITHUB_USER=${GITHUB_USER}
EOF

log ".env file created."

# -----------------------------------------------------------------------------
# Update .gitignore
# -----------------------------------------------------------------------------
header "Updating .gitignore"

for entry in ".env" "workspace/*.db" "workspace/*.log"; do
    if ! grep -qF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
    fi
done

log ".gitignore updated."

# -----------------------------------------------------------------------------
# Initialize status.json
# -----------------------------------------------------------------------------
header "Initializing Workspace Files"

cat > workspace/status.json <<EOF
{
  "project": "agent-playground",
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

log "workspace/status.json initialized."

# -----------------------------------------------------------------------------
# Write CLAUDE.md files
# -----------------------------------------------------------------------------
header "Writing CLAUDE.md Files"

cat > orchestrator/CLAUDE.md <<'EOF'
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
- Always create tickets in /workspace/tickets/ before assigning work
- Track all ticket status changes in /workspace/status.json
- A ticket is only DONE when QC passes
- If reviewer rejects, reassign to original agent with full feedback
- If QC fails, reassign to original agent with test failure details
- Never modify files in /codebase/ directly
- Never push directly to main or dev

## Ticket Format
Create tickets as /workspace/tickets/ticket_XXX.md

## Workflow
Requirements → Tickets → Assign → Review → QC → Done

## Git Rules
- Ensure all agents branch from dev
- Only mark done after QC passes on the branch
EOF

cat > backend_dev/CLAUDE.md <<'EOF'
# Backend Developer Agent

## Role
You are a senior backend engineer specializing in
databases, APIs, and server-side logic.

## Rules
- Only work on tickets assigned to you in /workspace/tickets/
- All code goes in /codebase/backend/
- Write unit tests alongside all code
- When done, update ticket status to "review_needed"
- Never touch /codebase/frontend/ or /codebase/infrastructure/
- Never push directly to main or dev

## Stack
- Python / FastAPI
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

cat > frontend_dev/CLAUDE.md <<'EOF'
# Frontend Developer Agent

## Role
You are a senior frontend engineer specializing in
UI components, styling, and user experience.

## Rules
- Only work on tickets assigned to you in /workspace/tickets/
- All code goes in /codebase/frontend/
- Write component tests alongside all code
- When done, update ticket status to "review_needed"
- Never touch /codebase/backend/ or /codebase/infrastructure/
- Never push directly to main or dev

## Stack
- React
- TypeScript
- Tailwind CSS

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

cat > infrastructure/CLAUDE.md <<'EOF'
# Infrastructure Agent

## Role
You are a senior infrastructure and DevOps engineer specializing
in web servers, deployment, and system configuration.

## Rules
- Only work on tickets assigned to you in /workspace/tickets/
- All config goes in /codebase/infrastructure/
- Document every configuration change
- When done, update ticket status to "review_needed"
- Never touch /codebase/backend/ or /codebase/frontend/
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
- Documentation updated
- Ticket status updated to review_needed
EOF

cat > reviewer/CLAUDE.md <<'EOF'
# Expert Reviewer Agent

## Role
You are a senior software architect and code reviewer.
You are thorough, critical, and maintain high standards.
You are the gatekeeper — nothing reaches QC without your approval.

## Rules
- Read ALL changed files before reviewing
- Write detailed feedback in /workspace/reviews/review_XXX.md
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
- Write review file in /workspace/reviews/
EOF

cat > qc_tester/CLAUDE.md <<'EOF'
# QC Tester Agent

## Role
You are a senior QA engineer. Your job is to break things
before users do. You are the final gatekeeper before done.

## Rules
- Only test tickets marked APPROVED by reviewer
- Run ALL existing tests first — verify nothing regressed
- Write new tests for all new functionality
- Test edge cases and failure scenarios
- Record all results in /workspace/test_results/results_XXX.md
- Verdict must be clearly PASSED or FAILED
- If failed, list specific failures with reproduction steps

## Tools
- pytest for Python backend
- Jest for frontend components
- Test API endpoints directly with curl or httpx
- Verify database state where relevant

## After Testing
- Update ticket status to "passed" or "failed"
- Write results file in /workspace/test_results/
EOF

log "All CLAUDE.md files written."

# -----------------------------------------------------------------------------
# Write Dockerfiles (identical base for all agents)
# -----------------------------------------------------------------------------
header "Writing Dockerfiles"

write_dockerfile() {
    local dir=$1
    cat > ${dir}/Dockerfile <<'EOF'
FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Configure git defaults
RUN git config --global credential.helper store
RUN git config --global init.defaultBranch main

WORKDIR /agent

# Copy this agent's CLAUDE.md
COPY CLAUDE.md /agent/CLAUDE.md

CMD ["claude", "--dangerously-skip-permissions"]
EOF
}

write_dockerfile orchestrator
write_dockerfile backend_dev
write_dockerfile frontend_dev
write_dockerfile infrastructure
write_dockerfile reviewer
write_dockerfile qc_tester

log "Dockerfiles written for all agents."

# -----------------------------------------------------------------------------
# Write docker-compose.yml
# ~/.claude mounted read-only so all agents share your Pro login
# -----------------------------------------------------------------------------
header "Writing docker-compose.yml"

CLAUDE_DIR="$HOME/.claude"

cat > docker-compose.yml <<EOF
version: '3.8'

services:

  redis:
    image: redis:alpine
    networks:
      - agent_network
    restart: unless-stopped

  orchestrator:
    build: ./orchestrator
    volumes:
      - ./codebase:/codebase
      - ./workspace:/workspace
      - ./shared:/shared
      - ${CLAUDE_DIR}:/root/.claude:ro
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
    build: ./backend_dev
    volumes:
      - ./codebase:/codebase
      - ./workspace:/workspace
      - ./shared:/shared
      - ${CLAUDE_DIR}:/root/.claude:ro
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
    build: ./frontend_dev
    volumes:
      - ./codebase:/codebase
      - ./workspace:/workspace
      - ./shared:/shared
      - ${CLAUDE_DIR}:/root/.claude:ro
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
    build: ./infrastructure
    volumes:
      - ./codebase:/codebase
      - ./workspace:/workspace
      - ./shared:/shared
      - ${CLAUDE_DIR}:/root/.claude:ro
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
    build: ./reviewer
    volumes:
      - ./codebase:/codebase
      - ./workspace:/workspace
      - ./shared:/shared
      - ${CLAUDE_DIR}:/root/.claude:ro
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
    build: ./qc_tester
    volumes:
      - ./codebase:/codebase
      - ./workspace:/workspace
      - ./shared:/shared
      - ${CLAUDE_DIR}:/root/.claude:ro
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
# Configure git for the project
# -----------------------------------------------------------------------------
header "Configuring Git"

git config user.name "${GITHUB_USER}"
git config user.email "${GITHUB_USER}@users.noreply.github.com"

# Embed PAT in remote URL so push/pull work without password prompts
git remote set-url origin "https://${GITHUB_USER}:${GITHUB_TOKEN}@$(echo $GITHUB_REPO | sed 's|https://||')"

# Create dev branch if it doesn't exist
git checkout -b dev 2>/dev/null || git checkout dev

log "Git configured."

# -----------------------------------------------------------------------------
# Commit and push initial structure to GitHub
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

docker-compose build

log "Docker images built."

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
header "Setup Complete"

echo ""
echo -e "${GREEN}Everything is ready!${NC}"
echo ""
echo "Project location: $REPO_DIR"
echo ""
echo "Folder summary:"
echo "  ./codebase/       ← agents write code here"
echo "  ./workspace/      ← tickets, reviews, test results"
echo "  ./orchestrator/   ← orchestrator agent"
echo "  ./backend_dev/    ← backend developer agent"
echo "  ./frontend_dev/   ← frontend developer agent"
echo "  ./infrastructure/ ← infrastructure agent"
echo "  ./reviewer/       ← expert reviewer agent"
echo "  ./qc_tester/      ← QC tester agent"
echo ""
echo "Useful commands:"
echo "  Start orchestrator only:  docker-compose run --rm orchestrator"
echo "  Start all agents:         docker-compose up"
echo "  Check token usage:        cat workspace/status.json"
echo "  List tickets:             ls workspace/tickets/"
echo "  Stop everything:          docker-compose down"
echo ""
