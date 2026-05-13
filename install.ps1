#Requires -Version 5.1
# Installs the Claude Code status line for Windows.
# Copies statusline-command.ps1 to ~/.claude/ and sets statusLine in settings.json.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptName   = "statusline-command.ps1"
$claudeDir    = Join-Path $env:USERPROFILE ".claude"
$settingsFile = Join-Path $claudeDir "settings.json"

# ── 1. Prerequisites ─────────────────────────────────────────────────────────

$srcScript = Join-Path $PSScriptRoot $scriptName
if (-not (Test-Path $srcScript)) {
    Write-Error "Source script not found: $srcScript`nRun this installer from the repository root."
    exit 1
}

if (-not (Test-Path $claudeDir -PathType Container)) {
    Write-Error "Claude Code config directory not found: $claudeDir`nMake sure Claude Code is installed."
    exit 1
}

# Warn if pwsh is not available (installer still continues)
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Warning "pwsh (PowerShell 7+) not found in PATH."
    Write-Warning "The statusLine command will be written with 'pwsh'. Edit settings.json manually to use 'powershell' if needed."
}

# ── 2. Copy script ────────────────────────────────────────────────────────────

$dest = Join-Path $claudeDir $scriptName
Copy-Item -Force $srcScript $dest
Write-Host "Copied: $dest"

# ── 3. Update settings.json (non-destructive merge) ──────────────────────────

$settings = if (Test-Path $settingsFile) {
    Get-Content $settingsFile -Raw | ConvertFrom-Json
} else {
    [PSCustomObject]@{}
}

$command = "pwsh -NoProfile -NonInteractive -File `"$dest`""
$statusLine = [PSCustomObject]@{ type = "command"; command = $command }
$settings | Add-Member -Force -NotePropertyName "statusLine" -NotePropertyValue $statusLine

$settings | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $settingsFile
Write-Host "Updated: $settingsFile"

# ── 4. Done ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "statusLine.command set to:"
Write-Host "  $command"
Write-Host ""
Write-Host "Restart Claude Code to activate the status line."
Write-Host "On first launch Claude Code may prompt you to trust the status line command."
