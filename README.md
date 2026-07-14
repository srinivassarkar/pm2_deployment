# DevOps Toolkit

A lightweight, dependency-free DevOps toolkit designed to run in-memory and eliminate repetitive operational work across your servers.

## Vision

* **No Installation**: Never install package managers or script managers on your production machines.
* **Zero Footprint**: Execution happens in memory without leaving files or configurations behind.
* **Zero Configuration**: Discovers repositories, branches, and PM2 processes dynamically.
* **Standardized Layout**: Designed for any Ubuntu server following the `/opt/node/<repo>` layout.
* **Safe & Interactive**: Confirms all potentially destructive operations (like cleaning `node_modules` or rebuilding) and prompts for choices.

---

## How to Use It

Connect to your Ubuntu server via SSH:

```bash
ssh ubuntu@your-server-ip
```

Then run the script in memory (it requires root privileges, so run with `sudo`):

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/<user>/deploy-tools/main/deploy.sh)
```

Alternatively, if you have cloned the repository locally for development, you can execute:

```bash
sudo ./deploy.sh
```

---

## Roadmap

### v1.0.0 — Interactive Deployment (Current)
* Dynamically scans `/opt/node` for repositories.
* Prompts to select the target repository.
* Fetches remote updates and lets you choose a git branch.
* Removes existing `dist/` and `node_modules/` to ensure clean builds.
* Runs `npm ci` and `npm run build` under `sudo`.
* Auto-detects matching PM2 app names using `/opt/node/ecosystem.config.json` or local `package.json` configurations.
* Performs PM2 restarts and prints a deployment summary.

### v1.1.0 — Logs (Next)
* Interactive PM2 log viewer and tail command manager.
* Custom stream limits (e.g. 200 lines) per service.

### v1.2.0 — PM2 Operations
* Start, stop, reload, delete, monitor, and status checks.

### v1.3.0 — Rollback
* Quick rollback to previous commits, tagged releases, or specific hashes.

### v1.4.0 — Health Checks
* Verification of listening ports, HTTP endpoints, and process health.

### v1.5.0 — Server Doctor
* Diagnostic metrics: disk, memory, CPU load, Node/NPM versions, and uptime.

### v2.0.0 — Multi-Repository Deployment
* Sequential deployment of multiple related services in one wizard execution.

---

## Local Development & Testing

To test the script locally or inside a simulated directory, you can override the target directory by setting the `DEPLOY_ROOT` environment variable:

```bash
sudo DEPLOY_ROOT=/path/to/mock_opt_node ./deploy.sh
```
