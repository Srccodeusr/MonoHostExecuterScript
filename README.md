# MonoHost installer

One script that installs and manages **MonoHost** (the MonoWeb panel) and its **node daemon** on a Linux server, in the same spirit as the Airlink installer: a menu when you run it by hand, flags when you script it.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Srccodeusr/MonoHostExecuterScript/main/installer.sh | sudo bash
```

Upload `installer.sh` to the root of the `main` branch of [Srccodeusr/MonoHostExecuterScript](https://github.com/Srccodeusr/MonoHostExecuterScript) so the URL above resolves (or set `MONOHOST_INSTALLER_URL` if you host it elsewhere).
Afterwards the script is installed as `monohost`, so just run `sudo monohost`.

## Menu

| Option | What it does |
| --- | --- |
| **Install MonoHost** | Installs Node.js, downloads the repo, writes `.env` (random secrets, your admin login, `APP_URL`), installs deps, builds, creates a `monohost` service user + systemd service and starts it |
| **Run MonoHost** | Switch between **production** (built, `node dist/server.cjs`) and **development** (`npm run dev`), as a service or in the foreground of your terminal |
| **Add Node** | Paste the one-liner from *Admin → Nodes*. Installs Node.js + Docker, downloads the daemon, builds it, writes `.env` (mode 600), creates `monohost-daemon.service`, opens ufw for the panel IP if `--allow` is present, starts it and checks it is listening |
| **Run Nodes** | Start / stop / restart the daemon |
| **Update** | MonoHost, node daemon, everything, or the installer itself. Backs up `data/` + `.env` first, snapshots the code, and **rolls back automatically** if the build or start fails |
| **Connect Cloudflared Tunnel** | Installs `cloudflared`, connects a tunnel from the token (or the whole `cloudflared service install ...` command), optionally points `APP_URL`/`ALLOWED_ORIGINS`/`TRUST_PROXY` at your hostname. Also a temporary `trycloudflare.com` quick tunnel |
| **Check Logs** | Panel, daemon, cloudflared, installer log. Live or last N lines |
| **Restart** | Panel, daemon, tunnel or everything |
| **Status & health check** | Service states, `/api/health`, versions, RAM/swap/disk, warnings (example admin password, localhost `APP_URL`, low RAM) |
| **Backups** | Backup now, restore, daily systemd timer (keeps the newest 10) |
| **Edit config** | Opens `.env` of the panel or daemon in your editor, then offers a restart |
| **Uninstall** | Removes the service and files. Panel: final backup of `data/` + `.env` first. Daemon: customer `data/` is moved to the backup dir unless you pass `--purge`. Never removes Node, Docker or cloudflared |

## Scripted use

```sh
sudo monohost install --yes --app-url https://host.example.com --admin-email me@example.com --mode prod
sudo monohost add-node --yes --panel https://host.example.com --key <secret> --port 3002 --allow <panel-ip>
sudo monohost add-node --yes --node-cmd '<paste the whole one-liner from the panel>'
sudo monohost run dev            # or: run prod, run dev --foreground
sudo monohost update all
sudo monohost tunnel --token <token> --hostname host.example.com
sudo monohost logs panel -f
sudo monohost restart all
sudo monohost uninstall daemon --yes
```

Run `monohost --help` for every command and flag. `--demo` previews the UI without changing anything.

## Add Node: the one-liner

The panel currently shows `cd daemon && npm install && npm run build && npm run configure -- --panel ... --key ... --port ... && npm start`. The installer understands that exact string (it only reads `--panel`, `--key`, `--port`, `--allow`), so nothing has to change in the panel. If you want the panel to show an installer command instead, change `configureCommand` in `server/hosting/daemonClient.ts`:

```ts
export function configureCommand(panelUrl: string, secret: string, port: number, panelIp?: string): string {
  const url = process.env.MONOHOST_INSTALLER_URL || 'https://raw.githubusercontent.com/Srccodeusr/MonoHostExecuterScript/main/installer.sh';
  return `curl -fsSL ${url} | sudo bash -s -- add-node --yes --panel ${panelUrl} --key ${secret} --port ${port}${panelIp ? ` --allow ${panelIp}` : ''}`;
}
```

and reword the steps text in `src/pages/admin/AdminNodes.tsx` (it still says to copy the `daemon/` folder).

## Layout and defaults

| Thing | Default |
| --- | --- |
| Panel | `/opt/MonoWeb`, service `monohost`, port 3000, runs as user `monohost` |
| Daemon | `/opt/monohost-daemon`, service `monohost-daemon`, port 3002, runs as root (needs the Docker socket) |
| Settings | `/etc/monohost/installer.conf` |
| Backups | `/var/backups/monohost` (contain secrets, mode 600) |
| Log | `/var/log/monohost-installer.log` |

`--no-docker` installs the bubblewrap process runtime instead of Docker and runs the daemon as the unprivileged `monohost` user. `--service pm2` uses pm2 instead of systemd (pm2 runs as root).

Environment overrides: `MONOHOST_REPO` (`Srccodeusr/MonoWeb`), `MONOHOST_REF` (`main`), `MONOHOST_TOKEN` (needed if the repo is private), `MONOHOST_TARBALL_URL`, `MONOHOST_DIR`, `MONOHOST_DAEMON_DIR`, `MONOHOST_INSTALLER_URL`, `MONOHOST_NODE_MAJOR` (22), `MONOHOST_BACKUP_DIR`.

## Notes

- Supports apt, dnf/yum, pacman and zypper. Linux only (no macOS).
- The source is fetched as a tarball from the GitHub API, never cloned, so no git is needed.
- Secrets in `.env` are generated once. On update/repair an existing `.env` and `data/` are never overwritten. `data/.app_secret` encrypts node and Stripe secrets, so keep your backups.
- Building the panel needs about 1.5 GB of RAM; on smaller VPSes add swap first (the status check warns about it).
- Open to the panel's IP only: the daemon port. Customer servers use ports 20000-40000.
