<#
.SYNOPSIS
  Pulls the latest setup from GitHub (fast-forward only) and re-applies it.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\update.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipPlugins
)

$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    git pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        throw "git pull --ff-only failed. This machine has local commits or edits; run 'git status' to see them."
    }
} finally {
    Pop-Location
}

& (Join-Path $PSScriptRoot 'setup.ps1') -SkipPlugins:$SkipPlugins
