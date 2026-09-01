# agent-pi-config — opinionated pi setup

This repo **is** the pi configuration: it gets cloned to `~/.pi/agent`, the
directory pi loads everything from. `settings.json`, extensions, skills, prompt
templates and themes all live here in git — updating a workstation is a
`git pull`.

```powershell
# from an ordinary (non-admin) PowerShell — installs git, bun and pi itself
irm https://raw.githubusercontent.com/TefenlilioE/agent-pi-config/main/install.ps1 | iex
```

Re-running the one-liner is safe: every step checks the current state first, and
a re-run just updates the config via `git pull`. Nothing needs admin rights.

## What the install script does

1. Sets `NODE_USE_SYSTEM_CA=1` as a user environment variable. The corporate
   TLS-inspecting proxy's CA is in the Windows certificate store, which Node and
   bun ignore by default in favour of their own bundle — without this, https
   fetches fail certificate verification.
2. `winget install Git.Git` and `winget install Oven-sh.Bun` (each skipped when
   already on PATH), refreshing PATH in the running process — winget writes the
   new PATH to the registry, not to your session.
3. `bun add -g --ignore-scripts @earendil-works/pi-coding-agent`, and puts bun's
   global bin directory on your user PATH if it is not there already.
4. Clones this repo into `~/.pi/agent` (or `$env:PI_CODING_AGENT_DIR`).
   - Already a clone → `git pull --rebase --autostash`.
   - Existing pi directory that is not a clone → adopted in place: the repo is
     checked out into it, your old `settings.json` is backed up to
     `settings.json.bak` and its keys (theme, default model, extra packages)
     are merged back in. Repo opinions win for `npmCommand` and the package list.
5. Runs `pi install` for every package listed in `settings.json`. pi would also
   install missing packages on its next startup — doing it here just makes
   failures visible immediately.

## What lives in the repo

| Path | |
| --- | --- |
| `settings.json` | the single source of truth: `npmCommand` is `bun` (pi defaults to the literal command `npm`, which does not exist on a bun-only machine) and the `packages` list below |
| `extensions/` | team-local extensions (`.ts`/`.js`), auto-loaded by pi |
| `skills/` | team-local skills, auto-loaded (top-level `.md` files and `SKILL.md` folders) |
| `prompts/` | prompt templates, auto-loaded |
| `themes/` | themes (`.json`), auto-loaded |
| `install.ps1` | the bootstrap one-liner target |

Packages installed from `settings.json`:

| Package | |
| --- | --- |
| `npm:pi-subagents` | |
| `npm:pi-web-access` | |
| `npm:pi-mcp-adapter` | |
| `npm:pi-lens` | |
| `npm:@narumitw/pi-goal` | |
| `npm:pi-caveman` | |
| `npm:pi-observability` | |
| `npm:@dietrichgebert/ponytail` | |
| [`plugin-pi-bifrost`](https://github.com/TefenlilioE/plugin-pi-bifrost) | the Bifrost gateway provider |

## After it runs

Open a new terminal (for the PATH change), start `pi`, and configure the gateway
once: `/login` → **Bifrost gateway** → URL `https://bifrost.dev.ai.dy.droot.org`,
then the virtual key. Alternatively set `BIFROST_BASE_URL` and `BIFROST_VIRTUAL_KEY`
in the environment and skip the login.

## Changing the setup

Edit `settings.json` (packages) or drop files into `extensions/`, `skills/`,
`prompts/`, `themes/`, commit, push. Workstations pick it up by re-running the
one-liner or `git -C ~/.pi/agent pull`; pi installs newly listed packages on its
next startup.

## Known trade-off: settings.json drift

pi writes personal choices (theme, default model, `pi install`ed extras) into
the same `settings.json` this repo tracks, so `~/.pi/agent` will show local
modifications — that is expected. The install script pulls with
`--rebase --autostash`; if a pull ever conflicts, resolve it in `~/.pi/agent`
like any git conflict. Runtime state (`npm/`, `git/`, `sessions/`, `auth.json`,
…) is gitignored.
