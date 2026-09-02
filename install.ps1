# Opinionated pi workstation setup. Designed to be piped through iex:
#
#   irm https://raw.githubusercontent.com/TefenlilioE/agent-pi-config/main/install.ps1 | iex
#
# Installs git, bun and the pi coding agent, then clones this repo into
# ~/.pi/agent so the whole configuration (settings.json, extensions/, skills/,
# prompts/, themes/) lives in git. Finally it installs the packages that
# settings.json lists. Safe to re-run: every step checks the current state
# first, and a re-run updates the config via git pull.
#
# No param block on purpose: an iex pipe cannot pass parameters.

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/TefenlilioE/agent-pi-config.git'
$PiPackage = '@earendil-works/pi-coding-agent'

# Windows PowerShell 5.1 turns any line a native command writes to stderr into a
# terminating error while ErrorActionPreference is Stop - and winget, git and bun
# all report progress there. Run them through here and judge them by exit code.
function Invoke-Native {
    param(
        [Parameter(Mandatory)] [string] $File,
        [string[]] $Arguments = @()
    )

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $File @Arguments 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}

function Write-Step {
    param([string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Note {
    param([string] $Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

# winget writes the new PATH to the registry, not to this process.
function Sync-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Add-ToUserPath {
    param([string] $Directory)

    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($current) { $entries = $current -split ';' | Where-Object { $_ } }
    $already = $entries | Where-Object { $_.TrimEnd('\') -ieq $Directory.TrimEnd('\') }
    if ($already) { return $false }

    [Environment]::SetEnvironmentVariable('Path', (($entries + $Directory) -join ';'), 'User')
    $env:Path = "$env:Path;$Directory"
    return $true
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Command
    )

    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        Write-Note "$Command already installed: $((Get-Command $Command).Source)"
        return
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$Command is missing and winget is not available. Install App Installer from the Microsoft Store, then re-run."
    }

    $result = Invoke-Native winget @(
        'install', '--id', $Id, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    $result.Output | ForEach-Object { Write-Note $_ }
    # winget reports 0x8A15002B ("no applicable upgrade") as a failure on re-runs,
    # so the PATH check below decides whether this actually worked.
    if ($result.ExitCode -ne 0) { Write-Note "winget exit code $($result.ExitCode)" }

    Sync-Path
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "$Command is still not on PATH after installing. Open a new terminal and re-run."
    }
    Write-Note "$Command installed: $((Get-Command $Command).Source)"
}

# winget's Git install only puts Git\cmd (git.exe) on PATH. Git Bash lives in
# Git\bin and pi finds it there for its own `!` commands, but the model's shell
# tool cannot: a bare `bash` in PowerShell resolves to nothing - or, with WSL
# enabled, to System32\bash.exe, which cannot open C:/ paths. Put Git\bin on the
# user PATH so `bash script.sh` means Git Bash.
function Add-GitBashToPath {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return }
    # ...\Git\cmd\git.exe -> ...\Git
    $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
    $binDir = Join-Path $gitRoot 'bin'
    if (-not (Test-Path (Join-Path $binDir 'bash.exe'))) {
        Write-Note "no bash.exe under $binDir, leaving PATH alone"
        return
    }
    if (Add-ToUserPath $binDir) {
        Write-Note "added $binDir to your PATH (Git Bash as 'bash')"
    } else {
        Write-Note "$binDir already on PATH"
    }
    # The machine PATH is searched before the user PATH, so WSL's launcher still
    # shadows Git Bash when the WSL feature is enabled. Nothing to do about that
    # without admin rights; the model is told to use the full path in that case.
    $wslBash = Join-Path $env:SystemRoot 'System32\bash.exe'
    if (Test-Path $wslBash) {
        Write-Host "    note: $wslBash exists (WSL). It comes first on PATH, so a bare 'bash' runs WSL, not Git Bash." -ForegroundColor Yellow
    }
}

# The corporate TLS-inspecting proxy's CA lives in the Windows certificate store,
# which Node and bun ignore by default - they ship their own bundle, so anything
# they fetch over https fails to verify. This switches them to the system store.
# Persisted for the user, and applied to this process so the installs below work.
function Set-SystemCaTrust {
    $name = 'NODE_USE_SYSTEM_CA'
    $current = [Environment]::GetEnvironmentVariable($name, 'User')
    if ($current -eq '1') {
        Write-Note "$name already set for your user"
    } else {
        [Environment]::SetEnvironmentVariable($name, '1', 'User')
        Write-Note "$name=1 set for your user (takes effect in new terminals)"
    }
    $env:NODE_USE_SYSTEM_CA = '1'
}

function Install-Pi {
    # --ignore-scripts: nothing in this dependency tree needs postinstall, and it
    # keeps the install from running arbitrary code on a managed workstation.
    $result = Invoke-Native bun @('add', '-g', '--ignore-scripts', $PiPackage)
    $result.Output | ForEach-Object { Write-Note $_ }
    if ($result.ExitCode -ne 0) { throw "bun add -g $PiPackage failed with exit code $($result.ExitCode)" }

    $binResult = Invoke-Native bun @('pm', 'bin', '-g')
    $binDir = $binResult.Output | Where-Object { $_ } | Select-Object -First 1
    if ($binResult.ExitCode -ne 0 -or -not $binDir) { $binDir = Join-Path $env:USERPROFILE '.bun\bin' }
    if (Add-ToUserPath $binDir) { Write-Note "added $binDir to your PATH" }

    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        throw "pi is not on PATH. Expected it in $binDir."
    }
    Write-Note "pi installed: $((Invoke-Native pi @('--version')).Output -join ' ')"
}

# Reads settings.json as an object; $null when the file is missing, empty or not
# valid JSON (e.g. left with conflict markers by an earlier failed pull).
function Read-SettingsFile {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path $Path)) { return $null }
    $raw = Get-Content -Raw -Path $Path
    if (-not $raw.Trim()) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

# The repo's settings.json wins for npmCommand, defaultTools and its package list,
# but the user's other choices (theme, default model, extra packages) survive.
function Merge-Settings {
    param(
        [Parameter(Mandatory)] [string] $SettingsPath,
        [Parameter(Mandatory)] $UserSettings
    )
    $merged = [ordered]@{}
    $repoSettings = Get-Content -Raw -Path $SettingsPath | ConvertFrom-Json
    foreach ($property in $repoSettings.PSObject.Properties) { $merged[$property.Name] = $property.Value }
    foreach ($property in $UserSettings.PSObject.Properties) {
        if ($property.Name -in @('npmCommand', 'defaultTools')) { continue }
        if ($property.Name -eq 'packages') {
            $repoPackages = @($merged['packages'])
            $extra = @($property.Value) | Where-Object { $repoPackages -notcontains $_ }
            $merged['packages'] = $repoPackages + $extra
            continue
        }
        $merged[$property.Name] = $property.Value
    }
    $json = $merged | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ~/.pi/agent IS the clone of this repo. Three states to handle:
#   - already a git clone: update it. pi rewrites settings.json in its own
#     formatting, so a plain `pull --autostash` conflicts whenever the repo
#     changes that file. Instead: remember the user's settings, reset the file
#     to HEAD, pull, and merge the user's keys back in (same rules as adopting).
#   - missing or empty: plain clone
#   - existing non-git agent dir: adopt it - clone the repo into the directory
#     via init+fetch+checkout, preserving the user's old settings.json keys
function Sync-ConfigRepo {
    param([Parameter(Mandatory)] [string] $AgentDir)

    $settingsPath = Join-Path $AgentDir 'settings.json'

    if (Test-Path (Join-Path $AgentDir '.git')) {
        Write-Note "updating existing clone in $AgentDir"

        # The user's current settings: the working copy, or - if an earlier pull
        # left it with conflict markers - the autostash git kept for us.
        $userSettings = Read-SettingsFile $settingsPath
        $stashList = (Invoke-Native git @('-C', $AgentDir, 'stash', 'list')).Output | Where-Object { $_ }
        if (-not $userSettings -and $stashList) {
            $stashed = Invoke-Native git @('-C', $AgentDir, 'show', 'stash@{0}:settings.json')
            if ($stashed.ExitCode -eq 0) {
                try { $userSettings = ($stashed.Output -join "`n") | ConvertFrom-Json } catch { }
                if ($userSettings) { Write-Note "recovered your settings from the stash of an earlier failed pull" }
            }
        }
        if ($userSettings) {
            Copy-Item $settingsPath "$settingsPath.bak" -Force -ErrorAction SilentlyContinue
        } else {
            Write-Note "could not read your current settings.json - the repo version will be used as is"
        }

        # Drop that leftover stash if it only carried settings.json (which we now hold).
        if ($stashList) {
            $touched = @((Invoke-Native git @('-C', $AgentDir, 'stash', 'show', '--name-only', 'stash@{0}')).Output | Where-Object { $_ })
            if ($userSettings -and $touched.Count -eq 1 -and $touched[0] -eq 'settings.json') {
                Invoke-Native git @('-C', $AgentDir, 'stash', 'drop', 'stash@{0}') | Out-Null
                Write-Note "dropped the leftover stash (it only held settings.json)"
            } else {
                Write-Note "leaving git stash untouched: $($stashList -join '; ')"
            }
        }

        # Reset settings.json to HEAD so the pull has nothing to conflict on.
        $reset = Invoke-Native git @('-C', $AgentDir, 'checkout', 'HEAD', '--', 'settings.json')
        if ($reset.ExitCode -ne 0) { $reset.Output | ForEach-Object { Write-Note $_ } }

        $result = Invoke-Native git @('-C', $AgentDir, 'pull', '--rebase', '--autostash')
        $result.Output | ForEach-Object { Write-Note $_ }
        if ($result.ExitCode -ne 0) {
            Write-Note "git pull failed - resolve it manually in $AgentDir, then re-run. Continuing with the current checkout."
        }

        if ($userSettings) {
            Merge-Settings -SettingsPath $settingsPath -UserSettings $userSettings
            Write-Note "merged your settings (theme, model, extra packages) into the updated settings.json"
        }
        return
    }

    $isEmpty = -not (Test-Path $AgentDir) -or -not (Get-ChildItem -Force $AgentDir -ErrorAction SilentlyContinue)
    if ($isEmpty) {
        Write-Note "cloning into $AgentDir"
        $result = Invoke-Native git @('clone', $RepoUrl, $AgentDir)
        $result.Output | ForEach-Object { Write-Note $_ }
        if ($result.ExitCode -ne 0) { throw "git clone failed with exit code $($result.ExitCode)" }
        return
    }

    # Adopt: pi has run here before. Keep the user's settings (merged below) and
    # every runtime file; only tracked files are overwritten by the checkout.
    Write-Note "adopting existing pi directory $AgentDir"
    $oldSettings = Read-SettingsFile $settingsPath
    if (Test-Path $settingsPath) {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        Write-Note "existing settings.json backed up to settings.json.bak"
    }

    foreach ($step in @(
        @('init'),
        @('remote', 'add', 'origin', $RepoUrl),
        @('fetch', '--depth', '1', 'origin', 'main'),
        @('checkout', '-f', '-B', 'main', 'origin/main')
    )) {
        $result = Invoke-Native git (@('-C', $AgentDir) + $step)
        if ($result.ExitCode -ne 0) {
            $result.Output | ForEach-Object { Write-Note $_ }
            throw "git $($step -join ' ') failed with exit code $($result.ExitCode)"
        }
    }

    if ($oldSettings) {
        Merge-Settings -SettingsPath $settingsPath -UserSettings $oldSettings
        Write-Note "merged your existing settings into the repo's settings.json"
    }
}

# pi also installs missing packages on startup, but doing it here means the
# first `pi` launch is instant and any failure is visible now, per package.
function Install-ConfiguredPackages {
    param([Parameter(Mandatory)] [string] $AgentDir)

    $settingsPath = Join-Path $AgentDir 'settings.json'
    $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
    $sources = @($settings.packages) | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.source } } | Where-Object { $_ }

    $failed = @()
    foreach ($source in $sources) {
        Write-Host ("    {0,-62}" -f $source) -NoNewline
        $result = Invoke-Native pi @('install', $source)
        if ($result.ExitCode -eq 0) {
            Write-Host 'ok' -ForegroundColor Green
        } else {
            Write-Host 'FAILED' -ForegroundColor Red
            $result.Output | Select-Object -Last 4 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
            $failed += $source
        }
    }
    return ,$failed
}

# ---------------------------------------------------------------------------

Write-Host 'pi workstation setup' -ForegroundColor White

Write-Step 'corporate TLS'
Set-SystemCaTrust

Write-Step 'git'
Install-WingetPackage -Id 'Git.Git' -Command 'git'
Add-GitBashToPath

Write-Step 'bun'
Install-WingetPackage -Id 'Oven-sh.Bun' -Command 'bun'

Write-Step 'pi coding agent'
Install-Pi

$agentDir = $env:PI_CODING_AGENT_DIR
if (-not $agentDir) { $agentDir = Join-Path $env:USERPROFILE '.pi\agent' }

Write-Step 'configuration repo'
Sync-ConfigRepo -AgentDir $agentDir

Write-Step 'packages'
$failed = Install-ConfiguredPackages -AgentDir $agentDir

Write-Step 'result'
if (-not $failed) {
    Write-Host '    all packages installed' -ForegroundColor Green
} else {
    Write-Host "    $($failed.Count) package(s) failed:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
    Write-Host '    pi retries missing packages on startup; or fix the cause and re-run this script.' -ForegroundColor Yellow
}

Write-Host ''
Write-Note 'Open a new terminal so PATH changes apply, then run: pi'
Write-Note 'Configure the Bifrost gateway once inside pi:  /login  ->  Bifrost gateway'
if ($failed) { exit 1 }
