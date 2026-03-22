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
| frontend_dev | UI components, styling, UX (HTMX/Tailwind/Jinja2) |
| infrastructure | Web servers, deployment, configuration (Docker/Nginx) |
| reviewer | Senior code reviewer — gatekeeper before QC |
| qc_tester | QA engineer — final gatekeeper before done |

All agents share your Claude Pro login via credentials copied at container startup.
Containers run as the same UID as the host user — no permission issues.
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

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

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

## How It Works

### Credential Sharing
Claude credentials (`~/.claude/` and `~/.claude.json`) are mounted **read-only** into each
container at a staging path (`/mnt/claude-config/`). At container startup, `entrypoint.sh`
copies them into `/home/agent/` where Claude Code expects them.

This means:
- Each container gets its own **isolated, writable copy** — no read-only write errors
- No race conditions — 6 agents can run simultaneously without clobbering each other
- Claude Code can write session metrics freely within the container (discarded on exit)
- Token usage tracking belongs in `agents/workspace/status.json` (persisted to disk)

### Entrypoint Staging
`entrypoint.sh` is written once to `agents/shared/` and then **copied into each agent's
directory** by `setup.sh` at construction time. This is required because Docker's build
context is scoped to each agent's own folder — `COPY ../shared/entrypoint.sh` would escape
the context and fail at build time. Each agent folder therefore contains its own copy:
`CLAUDE.md`, `Dockerfile`, and `entrypoint.sh`.

### Workspace Trust
Claude Code prompts to trust each new workspace directory. Since containers run with
`/home/agent` as their workspace, that path must be trusted in `~/.claude.json` on the
host before containers start.

This is done once during VM setup (not by `setup.sh`) by simply running Claude Code
in `/home/agent` and saying yes to the trust prompt. Claude Code writes the trust entry
into `~/.claude.json` itself — no programmatic modification needed.

`entrypoint.sh` then copies that pre-trusted `~/.claude.json` into `/home/agent/` at
container startup, so Claude Code sees `/home/agent` as trusted and skips the prompt.

### No Root
- Each Dockerfile creates a non-root `agent` user via `useradd`
- Docker Compose does **not** override the user — the Dockerfile's `USER agent` is used
- Claude Code requires non-root to use `--dangerously-skip-permissions`
- `chmod 644 ~/.claude.json` and `chmod -R 755 ~/.claude` run at setup time so the
  staging mount is readable before `entrypoint.sh` copies it

### Bypassing Trust and Permission Prompts
Two flags are used together in `entrypoint.sh` for fully unattended operation:

| Flag | What it bypasses |
|------|-----------------|
| Pre-trusted `/home/agent` in `~/.claude.json` | Workspace trust prompt at startup |
| `--dangerously-skip-permissions` | Per-tool confirmation prompts during execution |

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
Make sure the PAT token has Read/Write access to it.

### Step 4 — Run Setup
```bash
chmod +x ~/infra/agent-setup/setup.sh
~/infra/agent-setup/setup.sh agent-playground
```

No prompts. Runs fully automatically. The script will:
- Verify Claude Code credentials exist and fix permissions
- Clone the repo into `~/projects/agent-playground`
- Copy `.env` into the project
- Create all folder structure
- Write all CLAUDE.md files for each agent
- Write `agents/shared/entrypoint.sh` (credential copy + Claude launch)
- Write all Dockerfiles with non-root user and entrypoint
- Write docker-compose.yml with credential staging mounts
- Configure git
- Push initial structure to GitHub on `dev` branch
- Build all Docker images

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

### Starting A Session
1. Create a project brief:
```bash
nano ~/projects/agent-playground/agents/workspace/project_brief.md
```
2. Start the orchestrator:
```bash
cd ~/projects/agent-playground
docker compose run --rm orchestrator
```
3. Tell it:
```
Read /home/agent/agents/workspace/project_brief.md and follow the instructions there.
```

### Agent Flow
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
        │   │   ├── frontend/      ← HTMX/Tailwind templates
        │   │   ├── infrastructure/← server/deployment config
        │   │   └── tests/         ← test suites
        │   ├── assets/            ← static files, images, fonts
        │   ├── dist/              ← build output (gitignored)
        │   └── docs/              ← documentation
        │
        └── agents/                ← everything agent related
            ├── shared/
            │   └── entrypoint.sh  ← source copy — staged into each agent at setup time
            ├── workspace/
            │   ├── tickets/       ← task assignments
            │   ├── reviews/       ← reviewer feedback
            │   ├── test_results/  ← QC results
            │   ├── status.json    ← project state + token usage
            │   └── project_brief.md ← your requirements (you create this)
            ├── orchestrator/      ← CLAUDE.md + Dockerfile + entrypoint.sh
            ├── backend_dev/       ← CLAUDE.md + Dockerfile + entrypoint.sh
            ├── frontend_dev/      ← CLAUDE.md + Dockerfile + entrypoint.sh
            ├── infrastructure/    ← CLAUDE.md + Dockerfile + entrypoint.sh
            ├── reviewer/          ← CLAUDE.md + Dockerfile + entrypoint.sh
            └── qc_tester/         ← CLAUDE.md + Dockerfile + entrypoint.sh
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
| Claude Pro credentials | Mounted read-only to staging path, copied per container |
| PAT token | In `.env` which is gitignored |
| Agent scope | CLAUDE.md restricts each agent to its own folder |
| Container privileges | Runs as non-root `agent` user matching host UID |
| Concurrent writes | Each container gets isolated credential copy — no race conditions |

---

## Troubleshooting

### Trust prompt still appears in container
`/home/agent` must be trusted on the host VM before containers start.
This is a one-time VM setup step — if you skipped it:
```bash
sudo mkdir -p /home/agent
cd /home/agent
claude   # say yes to trust, then /exit
```
Then restart the container. No need to rebuild.

### Docker permission denied
```bash
sudo usermod -aG docker $USER && newgrp docker
```

### Git push fails
PAT token may have expired or lacks write access. Regenerate at:
GitHub → Settings → Developer Settings → Fine-grained tokens
Make sure to select the specific repo and grant Contents read/write.
Then update `~/infra/agent-setup/.env` with the new token.

### Claude Code not authenticated
```bash
claude   # log in again on the VM
```
Then re-run setup — permissions and trust will be fixed automatically.

### Claude Code refuses to run (root/sudo error)
Agents must not run as root. The Dockerfile creates a non-root `agent` user.
Make sure you are using the latest setup.sh and rebuild:
```bash
docker compose build --no-cache
```

### entrypoint.sh: credential copy fails
If `~/.claude.json` or `~/.claude/` don't exist on the host at container start,
the copy will silently skip. Verify on the VM:
```bash
ls -la ~/.claude.json ~/.claude/
```
If missing, log in again with `claude` on the VM then restart the container.

### Project folder already exists
```bash
rm -rf ~/projects/project-name
~/infra/agent-setup/setup.sh project-name
```

### Clean slate — remove everything and start over
```bash
# Remove project
rm -rf ~/projects/agent-playground

# Remove all Docker images and containers
docker system prune -a -f
```
