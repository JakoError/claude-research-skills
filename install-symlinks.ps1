# install-symlinks.ps1
# Symlink each skill from this repo's skills/ into the parent skills directory
# (e.g. ~/.claude/skills/ or ~/.agents/skills/).
#
# Run from any directory:
#   pwsh -File install-symlinks.ps1                # default: parent of this repo
#   pwsh -File install-symlinks.ps1 -Target ~/.claude/skills
#
# Windows: requires Developer Mode enabled OR an elevated PowerShell.

[CmdletBinding()]
param(
    [string]$Target
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Join-Path $repoRoot 'skills'

if (-not (Test-Path $sourceRoot)) {
    throw "skills/ not found inside repo: $sourceRoot"
}

if (-not $Target) {
    $Target = Split-Path -Parent $repoRoot
}
$Target = (Resolve-Path $Target).Path

Write-Host "Source: $sourceRoot"
Write-Host "Target: $Target"
Write-Host ""

Get-ChildItem -Path $sourceRoot -Directory | ForEach-Object {
    $linkPath   = Join-Path $Target $_.Name
    $targetPath = $_.FullName

    if (Test-Path $linkPath) {
        $item = Get-Item $linkPath -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host "skip (already linked): $($_.Name)"
            return
        } else {
            Write-Warning "exists and is NOT a symlink, skipping: $linkPath"
            return
        }
    }

    try {
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath | Out-Null
        Write-Host "linked: $($_.Name)  ->  $targetPath"
    } catch {
        Write-Error "failed: $($_.Name) — $($_.Exception.Message)"
        Write-Host "  Hint: enable Windows Developer Mode or run PowerShell as Administrator."
    }
}
