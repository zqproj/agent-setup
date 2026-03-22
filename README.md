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
# Add Docker's official apt repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker
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

### Step 2 — Create The .env File
```bash
nano ~/infra/agent-setup/.env
```

Add these values:
```
GITHUB_TOKEN=github_pat_xxxxxxxxxxxx
GITHUB_REPO=https://github.com/zqproj/agent-playground.git
GITHUB_USER=zqproj
```

> ⚠️ `.env` is in `.gitignore` — it will never be committed to GitHub.
> Update GITHUB_REPO each time you start a new project.

### Step 3 — Create A Repo On GitHub
Create a new private repo on the zqproj GitHub account (e.g. `agent-playground`).

### Step 4 — Run Setup
```bash
chmod +x ~/infra/agent-setup/setup.sh
~/infra/agent-setup/setup.sh agent-playground
```

No prompts. Runs fully automatically.

---

## Starting A New Project

1. Create a new private repo on zqproj GitHub account
2. Update `.env` with the new repo URL:
```bash
nano ~/infra/agent-setup/.env
# update GITHUB_REPO=https://github.com/zqproj/new-project.git
```
3. Run setup with the new project name:
```bash
~/infra/agent-setup/setup.sh new-project
```

> If the project folder already exists the script will bomb — intentional.
> Delete it first: `rm -rf ~/projects/new-project`

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
cat ~/projects/agent-playground/agents/workspace/status.json

# List tickets
ls ~/projects/agent-playground/agents/workspace/tickets/

# View agent logs
docker compose logs orchestrator
docker compose logs backend_dev
```

---

## Project Structure

```
~/
├── infra/
│   └── agent-setup/              ← you are here
│       ├── setup.sh               ← run to bootstrap a project
│       ├── .env                   ← your secrets (never committed)
│       └── README.md              ← this file
│
└── projects/
    └── agent-playground/         ← bootstrapped by setup.sh
        ├── .env                   ← copied from agent-setup/.env
        ├── docker-compose.yml
        │
        ├── proj/                  ← everything project related
        │   ├── src/
        │   │   ├── backend/       ← FastAPI source code
        │   │   ├── frontend/      ← React source code
        │   │   ├── infrastructure/← server/deployment config
        │   │   └── tests/         ← test suites
        │   ├── assets/            ← static files, images, fonts
        │   ├── dist/              ← build output (gitignored)
        │   └── docs/              ← documentation
        │
        └── agents/                ← everything agent related
            ├── workspace/
            │   ├── tickets/       ← task assignments
            │   ├── reviews/       ← reviewer feedback
            │   ├── test_results/  ← QC results
            │   └── status.json    ← project state + token usage
            ├── shared/            ← shared agent utilities
            ├── orchestrator/      ← CLAUDE.md + Dockerfile
            ├── backend_dev/       ← CLAUDE.md + Dockerfile
            ├── frontend_dev/      ← CLAUDE.md + Dockerfile
            ├── infrastructure/    ← CLAUDE.md + Dockerfile
            ├── reviewer/          ← CLAUDE.md + Dockerfile
            └── qc_tester/         ← CLAUDE.md + Dockerfile
```

---

## Gitignore

These are automatically added to `.gitignore` by setup.sh:

| Entry | Reason |
|-------|--------|
| `.env` | Contains PAT token |
| `proj/.venv/` | Python virtual environment |
| `proj/dist/` | Build output — regenerated |
| `proj/.vscode/` | Editor settings |
| `agents/workspace/*.db` | Local databases |
| `agents/workspace/*.log` | Log files |

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
Then update `~/infra/agent-setup/.env` with the new token.

### Claude Code not authenticated
```bash
claude   # log in again
```

### Claude Code refuses to run (root/sudo error)
Agents must not run as root. The Dockerfile creates a non-root user automatically.
If you see this error, make sure you are using the latest setup.sh and rebuild:
```bash
docker compose build --no-cache
```

### .claude.json missing inside container
The setup script auto-restores it from backup. If it still fails:
```bash
# On the VM, restore manually
cp ~/.claude/backups/.claude.json.backup.* ~/.claude.json
```

### Project folder already exists
```bash
rm -rf ~/projects/project-name
~/infra/agent-setup/setup.sh project-name
```
