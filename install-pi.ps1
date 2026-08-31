<#
.SYNOPSIS
    Installs bun, the pi coding agent, and the standard package set.

.DESCRIPTION
    Everything runs through bun: bun installs pi, and pi is told to use bun as its
    package manager instead of npm. Without that setting pi shells out to `npm`,
    which is not present on a bun-only machine, and every `pi install npm:...`
    fails.

    Safe to re-run. Each step checks the current state first, and package installs
    are idempotent - pi updates what is already there.

.PARAMETER GitUser
    Gitea account name, used only for the internal git package. Pass this if that
    install fails with 403: Gitea answers 403 rather than 401 when Windows has a
    credential cached for a different account, so git never prompts and the clone
    cannot recover on its own. Putting the name in the URL selects the right one.

.PARAMETER SkipBun
    Skip the bun install (it is already installed and on PATH).

.EXAMPLE
    .\install-pi.ps1

.EXAMPLE
    .\install-pi.ps1 -GitUser TefenlilioE
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string] $GitUser,
    [switch] $SkipBun
)

$ErrorActionPreference = 'Stop'

$BunPackageId = 'Oven-sh.Bun'
$PiPackage = '@earendil-works/pi-coding-agent'
$BifrostRepo = 'git3.dev.buzzi.com/TefenlilioE/plugin-pi-bifrost.git'

# Extensions every workstation gets. Order is irrelevant; keep it readable.
$Packages = @(
    'npm:pi-subagents'
    'npm:pi-web-access'
    'npm:pi-mcp-adapter'
    'npm:pi-lens'
    'npm:@narumitw/pi-goal'
    'npm:pi-caveman'
    'npm:@dietrichgebert/ponytail'
    'npm:pi-observability'
)

# Windows PowerShell 5.1 turns any line a native command writes to stderr into a
# terminating error while ErrorActionPreference is Stop - and bun, winget and git
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

function Install-Bun {
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        Write-Note "bun already installed: $((Get-Command bun).Source)"
        return
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available. Install App Installer from the Microsoft Store, then re-run.'
    }

    $result = Invoke-Native winget @(
        'install', '--id', $BunPackageId, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    $result.Output | ForEach-Object { Write-Note $_ }
    # winget reports 0x8A15002B ("no applicable upgrade") as a failure on re-runs,
    # so the PATH check below decides whether this actually worked.
    if ($result.ExitCode -ne 0) { Write-Note "winget exit code $($result.ExitCode)" }

    Sync-Path
    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        throw 'bun is still not on PATH after installing. Open a new terminal and re-run.'
    }
    Write-Note "bun installed: $((Get-Command bun).Source)"
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

# pi's package manager defaults to the literal command `npm`, so on a bun-only
# machine every package install fails until this is set. pi has first-class bun
# support behind it - it switches to bun's argument style once configured.
function Set-PiPackageManager {
    $agentDir = $env:PI_CODING_AGENT_DIR
    if (-not $agentDir) { $agentDir = Join-Path $env:USERPROFILE '.pi\agent' }
    if (-not (Test-Path $agentDir)) { New-Item -ItemType Directory -Path $agentDir -Force | Out-Null }

    $settingsPath = Join-Path $agentDir 'settings.json'
    $settings = [ordered]@{}
    if (Test-Path $settingsPath) {
        $raw = Get-Content -Raw -Path $settingsPath
        if ($raw.Trim()) {
            # Preserve every other setting: this file also holds the user's theme,
            # installed packages and other choices.
            $parsed = $raw | ConvertFrom-Json
            foreach ($property in $parsed.PSObject.Properties) { $settings[$property.Name] = $property.Value }
        }
        Copy-Item $settingsPath "$settingsPath.bak" -Force
    }

    $settings['npmCommand'] = @('bun')
    $json = $settings | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Note "npmCommand set to bun in $settingsPath"
}

function Install-PiPackage {
    param([string] $Source)

    Write-Host ("    {0,-62}" -f $Source) -NoNewline
    $result = Invoke-Native pi @('install', $Source)
    if ($result.ExitCode -eq 0) {
        Write-Host 'ok' -ForegroundColor Green
        return $true
    }
    Write-Host 'FAILED' -ForegroundColor Red
    $result.Output | Select-Object -Last 4 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
    return $false
}

# ---------------------------------------------------------------------------

Write-Host 'pi workstation setup' -ForegroundColor White

Write-Step 'corporate TLS'
Set-SystemCaTrust

if ($SkipBun) {
    Write-Step 'bun (skipped)'
} else {
    Write-Step 'bun'
    Install-Bun
}

Write-Step 'pi coding agent'
Install-Pi

Write-Step 'pi package manager'
Set-PiPackageManager

$bifrostUrl = "https://$BifrostRepo"
if ($GitUser) { $bifrostUrl = "https://$GitUser@$BifrostRepo" }
$allPackages = $Packages + $bifrostUrl

Write-Step "packages ($($allPackages.Count))"
$failed = @()
foreach ($package in $allPackages) {
    if (-not (Install-PiPackage $package)) { $failed += $package }
}

Write-Step 'result'
if ($failed.Count -eq 0) {
    Write-Host "    all $($allPackages.Count) packages installed" -ForegroundColor Green
} else {
    Write-Host "    $($failed.Count) of $($allPackages.Count) packages failed:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
    if ($failed -contains $bifrostUrl -and -not $GitUser) {
        Write-Host ''
        Write-Host '    The internal package is served by Gitea, which answers 403 instead of 401' -ForegroundColor Yellow
        Write-Host '    when Windows has a credential cached for a different account - so git never' -ForegroundColor Yellow
        Write-Host '    prompts. Re-run with your own account name to select it:' -ForegroundColor Yellow
        Write-Host '      .\install-pi.ps1 -SkipBun -GitUser <your-gitea-user>' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Note 'Open a new terminal so PATH changes apply, then run: pi'
Write-Note 'Configure the Bifrost gateway once inside pi:  /login  ->  Bifrost gateway'
if ($failed.Count -gt 0) { exit 1 }
