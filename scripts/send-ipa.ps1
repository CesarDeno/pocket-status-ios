[CmdletBinding()]
param(
    [string]$Target,
    [switch]$Sign
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repoRoot ".env"

if (-not $Target -and (Test-Path $envFile)) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^POCKET_SERVER_TAILDROP_TARGET=(.+)$') {
            $Target = $Matches[1].Trim()
        }
    }
}

if (-not $Target) {
    throw "Set POCKET_SERVER_TAILDROP_TARGET in .env or pass -Target <tailscale-device-name>."
}

$wslRepo = (wsl -d Ubuntu -- wslpath -a ($repoRoot -replace '\\', '/')).Trim()
$signFlag = if ($Sign) { "--sign " } else { "" }

Write-Host "Building PocketStatus.ipa in WSL..." -ForegroundColor Cyan
wsl -d Ubuntu --cd "$wslRepo" -- bash -c "source ~/.local/share/swiftly/env.sh && xtool dev build -c release ${signFlag}--ipa"
if ($LASTEXITCODE -ne 0) {
    throw "xtool build failed with exit code $LASTEXITCODE"
}

$ipaPath = Join-Path $repoRoot "xtool\PocketStatus.ipa"
if (-not (Test-Path $ipaPath)) {
    throw "IPA not found at $ipaPath"
}

Write-Host "Sending PocketStatus.ipa to '$Target' via Taildrop..." -ForegroundColor Cyan
tailscale file cp "$ipaPath" "${Target}:"
if ($LASTEXITCODE -ne 0) {
    throw "Taildrop failed (exit code $LASTEXITCODE). Make sure Tailscale is connected on '$Target'."
}
Write-Host "Sent! Open Tailscale / Files on your iPhone and import into SideStore." -ForegroundColor Green
