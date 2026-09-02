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
   Git's `bin` directory is added to your user PATH as well: winget only adds
   `Git\cmd`, so `bash` would otherwise resolve to nothing, or to WSL's launcher
   in System32, which cannot open `C:/` paths. With WSL enabled, System32 still
   wins (machine PATH precedes user PATH); use the full path to Git's `bash.exe`
   then.
3. `bun add -g --ignore-scripts @earendil-works/pi-coding-agent`, and puts bun's
   global bin directory on your user PATH if it is not there already.
4. Clones this repo into `~/.pi/agent` (or `$env:PI_CODING_AGENT_DIR`).
   - Already a clone → `git pull --rebase --autostash`.
   - Existing pi directory that is not a clone → adopted in place: the repo is
     checked out into it, your old `settings.json` is backed up to
     `settings.json.bak` and its keys (theme, default model, extra packages)
     are merged back in. Repo opinions win for `npmCommand`, `defaultTools` and
     the package list.
5. Runs `pi install` for every package listed in `settings.json`. pi would also
   install missing packages on its next startup — doing it here just makes
   failures visible immediately.

## What lives in the repo

| Path | |
| --- | --- |
| `settings.json` | the single source of truth: `npmCommand` is `bun` (pi defaults to the literal command `npm`, which does not exist on a bun-only machine), `defaultTools` swaps the model-facing `bash` tool for `powershell` (see below), and the `packages` list |
| `APPEND_SYSTEM.md` | appended to pi's system prompt in every session: Windows environment, prefer PowerShell, keep existing line endings |
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

## Windows-first tool set

`defaultTools` is `["read", "powershell", "edit", "write", "grep", "find", "ls"]`:
the full built-in set, with `bash` replaced by `powershell`. The `powershell` tool
runs `pwsh.exe` when installed, otherwise Windows PowerShell, always with
`-NoProfile -NonInteractive -ExecutionPolicy Bypass`, so the model never depends on
Git Bash being present. `APPEND_SYSTEM.md` tells it the same in words: Windows paths and
commands, no Bash/Linux/macOS assumptions, and keep whatever line endings a file
already has. The interactive `!` / `!!` commands still go through Git Bash, which
the installer brings in with git anyway. To get `bash` back for the model, add it
to the list (`["read", "bash", "powershell", ...]`) or override per project in
`.pi/settings.json`.

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
