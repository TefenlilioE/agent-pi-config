# pi workstation setup

One script that takes a fresh Windows workstation to a working pi install with the
standard extension set. Everything runs on bun; npm is never needed.

```powershell
# from an ordinary (non-admin) PowerShell — no git needed, it installs itself
irm https://raw.githubusercontent.com/TefenlilioE/agent-pi-config/main/install.ps1 | iex
```

The bootstrap (`install.ps1`) installs **git** via winget if it is missing, then
downloads and runs `install-pi.ps1`. Nothing here needs admin rights.

If you need parameters (`-GitUser`, `-SkipBun`), run the main script directly —
an iex pipe cannot pass them:

```powershell
git clone https://github.com/TefenlilioE/agent-pi-config.git
cd agent-pi-config
powershell -ExecutionPolicy Bypass -File .\install-pi.ps1
```

`-ExecutionPolicy Bypass` is only needed where the machine policy blocks local
scripts; `.\install-pi.ps1` on its own works otherwise.

Re-running is safe: bun, pi and every package install are idempotent, and existing
settings are preserved (a `.bak` copy is written before the settings file changes).

## What it does

0. *(bootstrap only)* `winget install Git.Git` if git is not on PATH — git is
   needed later to clone the internal Bifrost package from Gitea.
1. Sets `NODE_USE_SYSTEM_CA=1` as a user environment variable. The corporate
   TLS-inspecting proxy's CA is in the Windows certificate store, which Node and
   bun ignore by default in favour of their own bundle — without this, https
   fetches fail certificate verification. It is applied to the running process
   too, so the installs below already benefit.
2. `winget install Oven-sh.Bun`, then refreshes PATH in the running process —
   winget writes the new PATH to the registry, not to your session.
3. `bun add -g --ignore-scripts @earendil-works/pi-coding-agent`, and puts bun's
   global bin directory on your user PATH if it is not there already.
4. Sets `npmCommand` to `bun` in `~/.pi/agent/settings.json`. **This is the step
   that makes the rest work**: pi's package manager defaults to the literal
   command `npm`, which does not exist on a bun-only machine, so every
   `pi install npm:...` fails until this is set. pi has first-class bun support
   behind that setting.
5. Installs the packages:

   | Package | |
   | --- | --- |
   | `npm:pi-subagents` | |
   | `npm:pi-web-access` | |
   | `npm:pi-mcp-adapter` | |
   | `npm:pi-lens` | |
   | `npm:@narumitw/pi-goal` | |
   | `npm:pi-caveman` | |
   | `npm:@dietrichgebert/ponytail` | |
   | `npm:pi-observability` | |
   | `plugin-pi-bifrost` | internal, from Gitea — the Bifrost gateway provider |

A failing package does not stop the others; the script lists what failed and exits
non-zero.

## After it runs

Open a new terminal (for the PATH change), start `pi`, and configure the gateway
once: `/login` → **Bifrost gateway** → URL `https://bifrost.dev.ai.dy.droot.org`,
then the virtual key. Alternatively set `BIFROST_BASE_URL` and `BIFROST_VIRTUAL_KEY`
in the environment and skip the login.

## If the internal package fails with 403

Gitea answers **403** rather than 401 when Windows has a credential cached for a
different account, so git never prompts and cannot recover on its own. Name your
account in the URL to select the right credential:

```powershell
.\install-pi.ps1 -SkipBun -GitUser <your-gitea-user>
```

## Adding or removing packages

Edit the `$Packages` list at the top of `install-pi.ps1`. Employees pick up changes
by re-running the script; `pi update` refreshes what is already installed.

If this list keeps growing, the better shape is a single **pi pack** — one internal
repo whose `package.json` declares `pi.extensions`, `pi.skills`, `pi.prompts` and
`pi.themes`, installed with one command and updated with `pi update`. Keep that pack
free of dependencies: pi runs the configured package manager inside the clone, and
dependencies (dev ones included) are then pulled onto every workstation.

## Verified

The full script was run end to end against an isolated pi state directory
(`PI_CODING_AGENT_DIR`) on Windows 11 with pi 0.84.4 and bun 1.4.0: all nine
packages installed, pi started with no extension errors, and a second run was a
clean no-op.
