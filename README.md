# Agent Setup

Infrastructure scripts for the AI engineering agent team.
Lives in `~/infra/agent-setup/` on the sandbox VM — separate from all projects.

---

## What This Does

Bootstraps a complete multi-agent AI engineering team using Claude Code.
Each agent runs in its own Docker container with a specific role:

| Agent | Role |
|-------|------|
| orchestrator | Team lead — breaks requirements into tickets, coordinates agents |
| backend_dev | Database, APIs, server-side logic (Python/FastAPI/PostgreSQL) |
| frontend_dev | UI components, styling, UX (React/TypeScript/Tailwind) |
| infrastructure | Web servers, deployment, configuration (Docker/Nginx) |
| reviewer | Senior code reviewer — gatekeeper before QC |
| qc_tester | QA engineer — final gatekeeper before done |

All agents share your Claude Pro login via `~/.claude` mounted read-only.
All agents communicate via shared workspace files and a Redis message broker.

---

## Prerequisites

### 1. Claude Code Logged In
```bash
npm install -g @anthropic-ai/claude-code
claude   # log in with your Pro account
```

### 2. Docker + Docker Compose
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
sudo apt-get install -y docker-compose-plugin
```

### 3. Git
```bash
sudo apt-get install -y git
```

### 4. GitHub Bot Account (zqproj)
- Separate GitHub account — never your main account
- Fine-grained PAT with repository read/write permissions only
- No account-level permissions granted

---

## First Time Setup

### Step 1 — Clone This Repo
```bash
mkdir ~/infra
cd ~/infra
git clone https://zqproj:YOUR_PAT@github.com/zqproj/agent-setup.git
```

### Step 2 — Create Projects Folder
```bash
mkdir ~/projects
```

### Step 3 — Create The Project Repo On GitHub
Create a new private repo on the zqproj GitHub account (e.g. `agent-playground`).

### Step 4 — Create The Project .env
```bash
mkdir ~/projects/agent-playground
nano ~/projects/agent-playground/.env
```

Add these values:
```
GITHUB_TOKEN=github_pat_xxxxxxxxxxxx
GITHUB_REPO=https://github.com/zqproj/agent-playground.git
GITHUB_USER=zqproj
```

> ⚠️ `.env` is in `.gitignore` — it will never be committed to GitHub.

### Step 5 — Run Setup
```bash
chmod +x ~/infra/agent-setup/setup.sh
~/infra/agent-setup/setup.sh
```

No prompts. The script reads from the project `.env` and runs fully automatically.

---

## Starting A New Project

1. Create a new private repo on zqproj GitHub account
2. Copy and edit the `.env`:
```bash
mkdir ~/projects/new-project
cp ~/projects/agent-playground/.env ~/projects/new-project/.env
nano ~/projects/new-project/.env   # update GITHUB_REPO
```
3. Run setup again — it picks up the new project automatically

---

## Running The Agents

```bash
cd ~/projects/agent-playground

# Start just the orchestrator (recommended first)
docker compose run --rm orchestrator

# Start everything
docker compose up

# Stop everything
docker compose down
```

---

## Daily Workflow

```
You → Orchestrator → creates tickets → assigns to agents
                   ← reviewer approves/rejects
                   ← qc_tester passes/fails
                   ← marks ticket DONE
```

### Useful Commands
```bash
# Check ticket status
cat ~/projects/agent-playground/workspace/status.json

# List tickets
ls ~/projects/agent-playground/workspace/tickets/

# View agent logs
docker compose logs orchestrator
docker compose logs backend_dev
```

---

## Project Structure

```
~/
├── infra/
│   └── agent-setup/          ← you are here
│       ├── setup.sh           ← run to bootstrap a project
│       └── README.md          ← this file
│
└── projects/
    └── agent-playground/     ← bootstrapped by setup.sh
        ├── .env               ← your secrets (never committed)
        ├── docker-compose.yml
        ├── codebase/          ← agents write code here
        │   ├── backend/
        │   ├── frontend/
        │   ├── infrastructure/
        │   └── tests/
        ├── workspace/         ← agent communication
        │   ├── tickets/
        │   ├── reviews/
        │   ├── test_results/
        │   └── status.json
        ├── shared/
        ├── orchestrator/      ← CLAUDE.md + Dockerfile
        ├── backend_dev/       ← CLAUDE.md + Dockerfile
        ├── frontend_dev/      ← CLAUDE.md + Dockerfile
        ├── infrastructure/    ← CLAUDE.md + Dockerfile
        ├── reviewer/          ← CLAUDE.md + Dockerfile
        └── qc_tester/         ← CLAUDE.md + Dockerfile
```

---

## Security

| What | Protection |
|------|------------|
| Your main GitHub account | Agents only use zqproj bot account |
| zqproj credentials | PAT has no account-level permissions |
| Main branch | Branch protection — only you can merge |
| Claude Pro credentials | `~/.claude` mounted read-only in containers |
| PAT token | In `.env` which is gitignored |
| Agent scope | CLAUDE.md restricts each agent to its own folder |

---

## Troubleshooting

### Docker permission denied
```bash
sudo usermod -aG docker $USER && newgrp docker
```

### Git push fails
PAT token may have expired. Regenerate at:
GitHub → Settings → Developer Settings → Fine-grained tokens
Then update `.env` with the new token.

### Claude Code not authenticated
```bash
claude   # log in again
```

### setup.sh fails on .env not found
Make sure you created `~/projects/agent-playground/.env` before running setup.
