# MonoHost Executer Script

**Made by prime.dev1**

A single-file, colorful, interactive bash tool that installs everything
needed to run the MonoHost website, keeps it updated from GitHub, and can
expose it to your own domain through a Cloudflare Tunnel — all from one
numbered menu. No memorizing commands, no manual setup steps.

```
  __  __                  _   _           _
 |  \/  | ___  _ __   ___| | | | ___  ___| |_
 | |\/| |/ _ \| '_ \ / _ \ |_| |/ _ \/ __| __|
 | |  | | (_) | | | | (_) |  _  | (_) \__ \ |_
 |_|  |_|\___/|_| |_|\___/|_| |_|\___/|___/\__|

          MonoHost Executer Script
                Made by prime.dev1
```

## What it does

Run the script and you get a menu:

```
1) Dev Mode          — install + run with hot reload
2) Production Mode   — install + build + run optimized
3) Update Website    — pull latest release from GitHub
4) Cloudflare Tunnel — install cloudflared + connect a domain
5) View Logs
6) Re-check System Dependencies
0) Exit
```

Pick a number, press Enter, and the script does the rest:

- **Dev Mode** — checks you have `git`, `curl`, `node`, and `npm` (installs
  what's missing), clones or updates the site code, runs `npm install`, then
  starts the dev server with hot reload.
- **Production Mode** — same checks, then `npm install`, `npm run build`,
  and `npm start` to run the optimized build.
- **Update Website** — pulls the latest commits/release from GitHub,
  reinstalls dependencies if needed, and optionally rebuilds — use this
  whenever a new release goes out.
- **Cloudflare Tunnel** — downloads `cloudflared` if it isn't already
  installed, then lets you either paste in a Tunnel Token you already have,
  or log in interactively with your Cloudflare account and route a
  hostname to the tunnel, right from the menu.
- **View Logs** — shows the tail end of every log file the script has
  written, so you don't have to go hunting for them.

Every step prints clear, colored status messages (✔ success, ⚠ warning,
✖ error) and every failure is caught — a bad step won't crash the whole
script, it'll just tell you what went wrong and drop you back at the menu.

## Requirements

- A Linux environment with `bash` (Ubuntu/Debian-based is best supported;
  the script uses `apt-get` to install missing system packages)
- Root access or a working `sudo`, if `git`, `curl`, `unzip`, or Node.js
  need to be installed for you. If none of those are missing, you don't
  need root at all.
- An internet connection, obviously — it clones from GitHub and (for the
  tunnel option) talks to Cloudflare.

If you're on a VPS, a container, CodeSandbox, or basically any Debian/Ubuntu
box, this will work out of the box.

## Quick Start

### Option A — clone this repo and run it

```bash
git clone https://github.com/Srccodeusr/MonoHostExecuterScript.git
cd MonoHostExecuterScript
chmod +x monohost.sh
./monohost.sh
```

### Option B — one-liner (no clone needed)

```bash
curl -fsSL https://raw.githubusercontent.com/Srccodeusr/MonoHostExecuterScript/main/monohost.sh -o monohost.sh && chmod +x monohost.sh && ./monohost.sh
```

> **Note:** that URL assumes the script lives at the root of the repo on
> the `main` branch. If your default branch is `master`, or the file is in
> a subfolder, swap the URL accordingly — you can always find the correct
> raw link by opening `monohost.sh` on GitHub and clicking **Raw**.

Then just follow the numbered menu.

## Using it on CodeSandbox

1. Open a CodeSandbox with terminal access (any Node.js template works).
2. Open the Terminal panel.
3. Paste the one-liner from **Option B** above and hit Enter.
4. Pick `1` for Dev Mode to preview instantly, or `2` for a production run.
5. If you want a real domain instead of the sandbox's preview URL, pick
   `4` for Cloudflare Tunnel once the site is running.

CodeSandbox's Node.js containers already ship with `git`, `curl`, `node`,
and `npm`, so the dependency-check step will fly through — you'll only see
the installer kick in if something's actually missing.

## Setting up the Cloudflare Tunnel (option 4)

You'll be asked how you want to connect:

- **1) I already have a Tunnel Token** — paste it in. Get one from the
  [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/) →
  **Networks → Tunnels → Create a tunnel**. Copy the token shown in the
  install command Cloudflare gives you (it's the long string after
  `--token`) and paste just that into the script.
- **2) Log in interactively** — the script opens a Cloudflare login link
  for you to authorize in your browser, creates a named tunnel, and asks
  for the hostname (e.g. `app.yourdomain.com`) to route to it. Your domain
  needs to already be added to your Cloudflare account for the DNS routing
  step to work.

Either way, the tunnel points at `http://localhost:3000`, which is where
the site's production server listens by default.

## Where things get stored

- **Site code**: `~/monohost-site`
- **Logs**: `~/.monohost/logs/` (kept separate from the site folder on
  purpose, so re-cloning or resetting the site never wipes your logs)
- **cloudflared binary**: `~/.local/bin/cloudflared` (if it wasn't already
  on your system `PATH`)

## Troubleshooting

- **"Git clone failed"** — check `~/.monohost/logs/git.log`. Usually means
  the repo URL is wrong, private, or you're offline.
- **"npm install failed" / "Build failed"** — check
  `~/.monohost/logs/npm-install.log` or `~/.monohost/logs/build.log` for
  the actual npm/node error underneath.
- **"Node.js still not available"** — the script tried to install Node via
  NodeSource and it didn't take. Install Node.js 18+ manually for your
  distro, then re-run the script.
- **Tunnel won't connect** — double check the domain is active in your
  Cloudflare account and, for the token flow, that you copied the whole
  token with no extra whitespace.

Option `5` in the menu (View Logs) is the fastest way to see what actually
happened on any failed step.

## Updating

Already have it cloned? Pull the latest version of this script itself with:

```bash
git pull
```

To update the **website** the script deploys (not the script itself), just
run the tool and pick option `3` from the menu.

## License

MIT — see [LICENSE](./LICENSE).

## Credits

**MonoHost Executer Script** — made by **prime.dev1**
