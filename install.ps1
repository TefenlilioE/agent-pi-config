# Bootstrap for the pi workstation setup. Designed to be piped through iex:
#
#   irm https://raw.githubusercontent.com/TefenlilioE/agent-pi-config/main/install.ps1 | iex
#
# Installs git via winget if it is missing, then downloads install-pi.ps1 from
# this repo and runs it. No param block: iex pipes cannot pass parameters, so
# anyone needing -SkipBun should download install-pi.ps1 and run it directly.

$ErrorActionPreference = 'Stop'

$RawBase = 'https://raw.githubusercontent.com/TefenlilioE/agent-pi-config/main'

# Windows PowerShell 5.1 turns any line a native command writes to stderr into a
# terminating error while ErrorActionPreference is Stop - and winget reports
# progress there. Run it through here and judge it by exit code.
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

# winget writes the new PATH to the registry, not to this process.
function Sync-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ';'
}

function Install-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "==> git already installed: $((Get-Command git).Source)" -ForegroundColor Cyan
        return
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'git is missing and winget is not available. Install App Installer from the Microsoft Store, then re-run.'
    }

    Write-Host '==> installing git via winget' -ForegroundColor Cyan
    $result = Invoke-Native winget @(
        'install', '--id', 'Git.Git', '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    $result.Output | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    # winget reports 0x8A15002B ("no applicable upgrade") as a failure on re-runs,
    # so the PATH check below decides whether this actually worked.
    if ($result.ExitCode -ne 0) { Write-Host "    winget exit code $($result.ExitCode)" -ForegroundColor DarkGray }

    Sync-Path
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is still not on PATH after installing. Open a new terminal and re-run.'
    }
    Write-Host "    git installed: $((Get-Command git).Source)" -ForegroundColor DarkGray
}

Install-Git

Write-Host '==> downloading install-pi.ps1' -ForegroundColor Cyan
$scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "install-pi-$([guid]::NewGuid().ToString('N')).ps1"
Invoke-RestMethod "$RawBase/install-pi.ps1" -OutFile $scriptPath

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "install-pi.ps1 exited with code $LASTEXITCODE." -ForegroundColor Yellow
        Write-Host 'To re-run with options (e.g. -SkipBun), download it directly:' -ForegroundColor Yellow
        Write-Host "  irm $RawBase/install-pi.ps1 -OutFile install-pi.ps1" -ForegroundColor Yellow
        Write-Host '  powershell -ExecutionPolicy Bypass -File .\install-pi.ps1 -SkipBun' -ForegroundColor Yellow
    }
} finally {
    Remove-Item $scriptPath -ErrorAction SilentlyContinue
}
