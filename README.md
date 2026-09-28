<div align="center">

```text
  __  __                   __        __   _
 |  \/  | ___  _ __   ___  \ \      / /__| |__
 | |\/| |/ _ \| '_ \ / _ \  \ \ /\ / / _ \ '_ \
 | |  | | (_) | | | | (_) |  \ V  V /  __/ |_) |
 |_|  |_|\___/|_| |_|\___/    \_/\_/ \___|_.__/
```

# MonoHost Executer Script

**One interactive script to install, run, restart, update and delete [MonoWeb](https://github.com/Srccodeusr/MonoWeb) — plus a Cloudflare Tunnel helper.**

![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Linux-informational?style=flat-square)
![Version](https://img.shields.io/badge/version-2.0.0-lightgrey?style=flat-square)

</div>

---

## What is this?

`monoweb.sh` is a single-file, colourful, numbered-menu tool that sets up everything MonoWeb needs and then manages it for you. No memorising commands: pick a number, answer a couple of prompts, done.

- **Install Panel** — checks your system, installs Node.js if needed, downloads MonoWeb, writes a secure `.env`, installs dependencies
- **Run Panel** — start MonoWeb in **Dev** or **Prod** mode (you're asked right after choosing it)
- **Restart Panel**, **Stop Panel**, **Update Panel**
- **Delete Panel** — removes the whole installation (with a backup first, if you want one)
- **Cloudflare Tunnel** — put MonoWeb on your own domain without opening ports
- **Status & Info** and **View Logs** built in

The panel runs in the background, so it keeps serving after you close the menu or your SSH session.

---

## Quick start

Choose whichever install method you prefer. Both give you the exact same script.

### Option 1 — One-liner (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/Srccodeusr/MonoHostExecuterScript/main/monoweb.sh | bash
```

That's it — the menu opens right in your terminal.

> `-f` fails on HTTP errors, `-s` keeps curl quiet, `-S` still shows errors, `-L` follows redirects.

**Want to read the script before running it?** (recommended for anything you pipe into a shell)

```bash
curl -fsSL https://raw.githubusercontent.com/Srccodeusr/MonoHostExecuterScript/main/monoweb.sh -o monoweb.sh
less monoweb.sh
bash monoweb.sh
```

### Option 2 — Manual (git clone)

```bash
git clone https://github.com/Srccodeusr/MonoHostExecuterScript.git
cd MonoHostExecuterScript
chmod +x monoweb.sh
./monoweb.sh
```

| | |
| --- | --- |
| **Web** | <https://github.com/Srccodeusr/MonoHostExecuterScript> |
| **Clone URL** | `https://github.com/Srccodeusr/MonoHostExecuterScript.git` |

### Your first run

1. Choose **`1) Install Panel`** and answer the prompts: admin email, admin password (press Enter to generate a strong one — it's shown once, so save it) and your public URL.
2. Choose **`2) Run Panel`**, then **`1`** for Dev or **`2`** for Prod.
3. Open **http://localhost:3000** and sign in with the admin account you just created.
4. *(Optional)* choose **`6) Cloudflare Tunnel`** to serve it on your domain.

> Run the script as the user that should own the panel. It only asks for `sudo` when it has to install system packages or Node.js system-wide.

---

## The menu

```text
╭────────────────────────────────────────────────────────────────────╮
│ Panel     ○ Stopped                                                │
│ Tunnel    ○ Stopped                                                │
│ Install   ✖ Not installed — start with 1                           │
├────────────────────────────────────────────────────────────────────┤
│ SETUP                                                              │
│ 1   Install Panel      clone, configure, install deps              │
│ RUN                                                                │
│ 2   Run Panel          choose Dev or Prod mode                     │
│ 3   Restart Panel      apply changes or recover                    │
│ 4   Stop Panel         shut the panel down                         │
│ MANAGE                                                             │
│ 5   Update Panel       pull the latest code                        │
│ 6   Cloudflare Tunnel  connect your domain                         │
│ 7   Status & Info      versions, health, config                    │
│ 8   View Logs          panel, build, tunnel                        │
│ 9   Delete Panel       remove all panel files                      │
├────────────────────────────────────────────────────────────────────┤
│ 0   Exit                                                           │
╰────────────────────────────────────────────────────────────────────╯
```

The header updates live: a green dot means running, and the version shown is the commit you're on.

| # | Option | What it does |
| :-: | --- | --- |
| **1** | Install Panel | Preflight checks → system tools → Node.js → download MonoWeb → configure `.env` → `npm install`. Safe to re-run; your data is kept. |
| **2** | Run Panel | Asks **1 = Dev / 2 = Prod**, then starts MonoWeb in the background and waits until it answers on port 3000. |
| **3** | Restart Panel | Stops and starts again in the same mode (or lets you pick one). Use it after editing `.env`. |
| **4** | Stop Panel | Stops the panel and everything it spawned. |
| **5** | Update Panel | Backs up your data, pulls the latest code, reinstalls dependencies and offers to restart. |
| **6** | Cloudflare Tunnel | Installs `cloudflared` and connects a domain (token or account login). |
| **7** | Status & Info | Version, build state, config, health check, Node.js and system info. |
| **8** | View Logs | Panel, install/update, build and tunnel logs — optionally follow them live. |
| **9** | Delete Panel | Removes MonoWeb and the script's own state after a typed confirmation. |
| **0** | Exit | Leaves the menu. A running panel **keeps running**. |

---

## Dev vs Prod

After choosing **Run Panel** you'll see:

```text
  Run in which mode?
    1   Dev    live compile · verbose
    2   Prod   optimized build · for live traffic
```

| | **1 — Dev** | **2 — Prod** |
| --- | --- | --- |
| Command | `npm run dev` | `npm run build`, then `npm start` |
| `NODE_ENV` | `development` | `production` |
| Best for | Testing changes, theme/layout edits | Real traffic, your public domain |
| Build step | None (compiles on the fly) | Automatic — only when the code or a `VITE_*` value in `.env` changed |
| Port | 3000 | 3000 |

MonoWeb's server listens on port **3000**; this is fixed in the project itself. **Restart Panel** remembers your last mode, and choosing **Run Panel** while it's already running lets you stop it and switch.

---

## What the installer does

1. **Preflight** — shows your OS, CPU, RAM and free disk, and warns if you're short on either (under ~1 GB RAM the production build can get killed).
2. **System tools** — installs `git`, `curl`, `tar` and `gzip` if missing, using `apt`, `dnf`, `yum` or `apk`.
3. **Node.js 20+** — if it's missing or too old, offers to install Node.js 22 LTS from the official `nodejs.org` build, **SHA-256 verified**. It goes to `/usr/local` when you have root/sudo, otherwise to `~/.local/node` (no root needed).
4. **Download** — clones `https://github.com/Srccodeusr/MonoWeb` into `~/monoweb`.
5. **Configuration** — creates `.env` from the project's `env.example`, generates a random `JWT_SECRET` and installation keys, and asks for your admin email, password and public URL. The file is created with `chmod 600`.
6. **Dependencies** — runs `npm install`.

Re-running **Install Panel** on an existing install keeps your checkout and database, and asks whether to keep your current `.env`.

---

## Configuration

Your settings live in `~/monoweb/.env`. The installer sets:

| Variable | Purpose |
| --- | --- |
| `JWT_SECRET` | Signs login tokens (generated randomly) |
| `AETHER_ADMIN_EMAIL` / `AETHER_ADMIN_PASSWORD` | First super-admin account |
| `AETHER_INSTALLATION_ID` / `AETHER_INSTALLATION_SECRET` | Identity keys for this installation (generated) |
| `APP_URL` | Your public URL, used for OAuth callbacks |
| `ALLOWED_ORIGINS` | CORS allow-list (your URL plus localhost) |
| `TRUST_PROXY` | `true` behind a domain/tunnel, `false` for plain localhost |
| `DISCORD_REDIRECT_URI` | Kept in sync with your public URL |

Optional extras you can add by hand: `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_BOT_TOKEN`, `VITE_FIREBASE_*` (Google sign-in) and `VPN_CHECK_API_KEY`. After editing `.env`, use **3) Restart Panel**.

> The admin email and password are used when MonoWeb creates its database on the first start. Changing them later in `.env` does not rewrite an existing admin account.

---

## Cloudflare Tunnel

Serve MonoWeb on your own domain over HTTPS without opening any ports. Open **6) Cloudflare Tunnel**:

| Option | Use it when |
| --- | --- |
| **1) Tunnel Token** | You created a tunnel in the Cloudflare dashboard. Paste the token (input is hidden). |
| **2) Log in & create** | You want the script to create a named tunnel and route DNS for you. Your domain must already be on Cloudflare. |
| **3) Start tunnel** | Reconnect using the saved settings. |
| **4) Stop tunnel** | Disconnect. |
| **5) Set public URL** | Update `APP_URL`, allowed origins and proxy trust for your domain. |

**Token method, step by step**

1. In Cloudflare go to **Zero Trust → Networks → Tunnels → Create a tunnel** and copy the token (the long string after `--token`).
2. In the tunnel's **Public Hostname** tab add your domain with **Service type `HTTP`** and **URL `localhost:3000`**.
3. Run the script → **6 → 1**, paste the token.
4. When it connects, the script offers to set your public URL and restart the panel — say yes.

`cloudflared` is downloaded automatically for your CPU (amd64, arm64, arm, 386). The tunnel runs in the background and your token is stored with `600` permissions.

---

## Updating & deleting

**Update MonoWeb** — choose **5) Update Panel**. It saves a backup, fetches the latest code, shows what changed, reinstalls dependencies and asks whether to restart. If you have local edits that block the update, it asks before discarding anything (your `.env` and `data/` are never touched).

**Update this script** — re-run the one-liner, or if you cloned it:

```bash
cd MonoHostExecuterScript && git pull
```

**Delete MonoWeb** — choose **9) Delete Panel**. You'll see exactly what will be removed, get the option of a backup of `data/` and `.env`, and must type `DELETE` to confirm. It removes:

- the whole `~/monoweb` folder (source, `node_modules`, build, `.env`, database)
- the script's logs, pid files and tunnel settings

The panel and tunnel are stopped first. Node.js, git and the `cloudflared` binary stay installed. Backups are kept in `~/monoweb-backups` (the newest 10 are retained).

---

## Where things live

| What | Path |
| --- | --- |
| MonoWeb install | `~/monoweb` |
| Configuration | `~/monoweb/.env` |
| Database | `~/monoweb/data/db.json` |
| Logs | `~/.monoweb/logs/` (`panel.log`, `install.log`, `build.log`, `tunnel.log`) |
| PID files and tunnel settings | `~/.monoweb/run/` |
| Backups | `~/monoweb-backups/` |
| `cloudflared` | `~/.local/bin/cloudflared` (or your system one) |
| Node.js (no-root install) | `~/.local/node` |

State is kept **outside** the project folder on purpose, so re-cloning the site never wipes your logs.

---

## Customising

Override any default with an environment variable. With the one-liner, put it in front of `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/Srccodeusr/MonoHostExecuterScript/main/monoweb.sh | MONOWEB_DIR=/opt/monoweb bash
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `MONOWEB_REPO` | `https://github.com/Srccodeusr/MonoWeb.git` | Git URL to clone |
| `MONOWEB_BRANCH` | repo default | Branch to clone |
| `MONOWEB_DIR` | `~/monoweb` | Install directory |
| `MONOWEB_HOME` | `~/.monoweb` | Logs, pid files, tunnel settings |
| `MONOWEB_BACKUP_DIR` | `~/monoweb-backups` | Where backups are saved |

Other options: `./monoweb.sh --help`, `./monoweb.sh --version`, and `NO_COLOR=1` for plain output. The interface adapts to narrow terminals and falls back to ASCII when UTF-8 isn't available.

---

## Requirements

| | |
| --- | --- |
| **OS** | Linux with `bash` 4+. Developed and tested on Ubuntu 24.04; system packages install via `apt`, `dnf`, `yum` or `apk`. |
| **Access** | Root or `sudo` only if `git`, `curl`, `tar`, `gzip` or Node.js must be installed. Otherwise none. |
| **Node.js** | 20 or newer — installed for you if missing. |
| **Resources** | About 1 GB RAM and 1.5 GB free disk recommended for the production build. |
| **Network** | Internet access (GitHub, npm, and Cloudflare for tunnels). |
| **Port** | `3000` must be free. |

---

## Troubleshooting

Start with **8) View Logs** — it shows the tail of every log, and can follow one live.

| Problem | Fix |
| --- | --- |
| **"Port 3000 is already used"** | Another process owns the port. Stop it, or stop an old MonoWeb with **4) Stop Panel**, then run again. |
| **Build fails or is "Killed"** | Almost always low memory. Add swap (or use a bigger VPS) and retry; details are in `build.log`. |
| **`npm install` failed** | Check `install.log` via **View Logs → Install / update**. Confirm the server can reach the npm registry. |
| **"Node.js is too old"** | Accept the offer to install Node.js 22 LTS, or install Node 20+ yourself and re-run. |
| **Clone failed / private repo** | Check the URL and network. For a private repo: `MONOWEB_REPO='https://<token>@github.com/Srccodeusr/MonoWeb.git'`. |
| **Can't sign in with the new admin details** | The database already existed, so the admin from `.env` wasn't applied. Sign in with the original account, or **Delete Panel** (keep the backup) and reinstall for a clean start. |
| **Tunnel won't connect** | Re-copy the full token with no spaces and make sure the domain is active in Cloudflare. The tunnel log shows Cloudflare's exact error. |
| **Garbled characters** | Use a UTF-8 terminal, or run with `NO_COLOR=1`. |
| **Running it non-interactively** | The script needs a real terminal. In automation, download it and run it from a shell session. |

---

## Security notes

- Piping a script into a shell runs remote code — use the "read it first" variant above if you want to review it.
- `.env`, the saved tunnel token and the state folder are created with owner-only permissions. Secrets are generated from `/dev/urandom`, and passwords are typed with hidden input and never written to a log.
- Backups contain your `.env` and database, so treat them like credentials.
- Never commit your `.env` or `data/db.json`.

---

## Changelog

**2.0.0** — Rewritten for [MonoWeb](https://github.com/Srccodeusr/MonoWeb): new numbered-menu UI, Install / Run (Dev or Prod) / Restart / Stop / Update / Delete, background process management, automatic `.env` setup, backups, Cloudflare Tunnel with saved settings, status and log viewers.

---

## Credits

**MonoHost Executer Script** — made by **prime.dev1**

- **MonoWeb** (the site this script installs) — [Srccodeusr/MonoWeb](https://github.com/Srccodeusr/MonoWeb)
- **Cloudflare Tunnel** — powered by [`cloudflared`](https://github.com/cloudflare/cloudflared)

## License

Released under the **MIT License** — see [LICENSE](LICENSE).
