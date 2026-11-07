<#
.SYNOPSIS
  Installs this repo's Claude Code setup into ~/.claude. Safe to re-run.

.DESCRIPTION
  - Links every skill in ./skills into ~/.claude/skills (directory junctions on
    Windows, so no admin rights are needed; edits and git pulls show up instantly).
    Skills that are not in this repo are left alone.
  - Copies ./agents/*.md and CLAUDE.md into ~/.claude.
  - Merges plugins.json (enabledPlugins + extraKnownMarketplaces) into
    ~/.claude/settings.json without touching your other settings (env, model, permissions...).
  - Installs the listed plugins with the claude CLI when it is available.
  Anything it replaces is backed up to ~/.claude/backups/setup-<timestamp>/.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup.ps1
  powershell -ExecutionPolicy Bypass -File .\setup.ps1 -SkipPlugins
#>
[CmdletBinding()]
param(
    [switch]$SkipPlugins
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Repo      = $PSScriptRoot
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$BackupDir = Join-Path $ClaudeDir ("backups/setup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ((Test-Path variable:IsWindows) -and $IsWindows)
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$script:Changes = 0

function Write-Step([string]$Message) { Write-Host "  $Message" }

function Test-Property($Object, [string]$Name) {
    $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-FullPath([string]$Path) {
    [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Backup-Path([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Copy-Item -LiteralPath $Path -Destination $BackupDir -Recurse -Force
}

function Get-LinkTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not $item.LinkType) { return $null }
    $target = [string]($item.Target | Select-Object -First 1)
    if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path $Path) $target }
    return (Get-FullPath $target)
}

function Set-DirectoryLink([string]$Link, [string]$Target) {
    $existing = Get-LinkTarget $Link
    if ($existing -and $existing -eq (Get-FullPath $Target)) { return $false }

    if ($existing) {
        [System.IO.Directory]::Delete($Link)          # removes only the link, never the target
    } elseif (Test-Path -LiteralPath $Link) {
        Backup-Path $Link
        Remove-Item -LiteralPath $Link -Recurse -Force
    }
    $type = if ($OnWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $type -Path $Link -Target $Target | Out-Null
    return $true
}

function Copy-IfChanged([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        $same = (Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Destination).Hash
        if ($same) { return $false }
        Backup-Path $Destination
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    return $true
}

function Invoke-ClaudeCli([string[]]$CliArgs) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & claude @CliArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ Code = $code; Output = $output.Trim() }
}

Write-Host "Claude Code setup: $Repo -> $ClaudeDir"
foreach ($dir in @($ClaudeDir, (Join-Path $ClaudeDir 'skills'), (Join-Path $ClaudeDir 'agents'))) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# 1. Skills (linked, so `git pull` updates them immediately)
Write-Host "Skills"
foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $Repo 'skills') -Directory) {
    $link = Join-Path (Join-Path $ClaudeDir 'skills') $skill.Name
    if (Set-DirectoryLink -Link $link -Target $skill.FullName) {
        Write-Step "linked   $($skill.Name)"; $script:Changes++
    } else {
        Write-Step "ok       $($skill.Name)"
    }
}

# 2. Agents and global CLAUDE.md (copied; re-run after pulling)
Write-Host "Agents and CLAUDE.md"
foreach ($agent in Get-ChildItem -LiteralPath (Join-Path $Repo 'agents') -Filter '*.md' -File) {
    if (Copy-IfChanged $agent.FullName (Join-Path (Join-Path $ClaudeDir 'agents') $agent.Name)) {
        Write-Step "updated  agents/$($agent.Name)"; $script:Changes++
    }
}
if (Copy-IfChanged (Join-Path $Repo 'CLAUDE.md') (Join-Path $ClaudeDir 'CLAUDE.md')) {
    Write-Step "updated  CLAUDE.md"; $script:Changes++
}

# 3. Plugins declared in settings.json (merged, never overwritten)
Write-Host "Plugins"
$pluginsFile  = Join-Path $Repo 'plugins.json'
$settingsFile = Join-Path $ClaudeDir 'settings.json'
$wanted = Get-Content -LiteralPath $pluginsFile -Raw | ConvertFrom-Json

$settings = $null
if (Test-Path -LiteralPath $settingsFile) {
    $raw = Get-Content -LiteralPath $settingsFile -Raw
    if ($raw -and $raw.Trim()) {
        try { $settings = $raw | ConvertFrom-Json }
        catch { throw "Could not parse $settingsFile. Fix the JSON, then re-run. ($($_.Exception.Message))" }
    }
}
if ($null -eq $settings) { $settings = [pscustomobject]@{} }

$before = $settings | ConvertTo-Json -Depth 32 -Compress
foreach ($section in @('extraKnownMarketplaces', 'enabledPlugins')) {
    if (-not ((Test-Property $wanted $section))) { continue }
    if (-not ((Test-Property $settings $section)) -or $null -eq $settings.$section) {
        $settings | Add-Member -NotePropertyName $section -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    foreach ($entry in $wanted.$section.PSObject.Properties) {
        $settings.$section | Add-Member -NotePropertyName $entry.Name -NotePropertyValue $entry.Value -Force
    }
}
if (($settings | ConvertTo-Json -Depth 32 -Compress) -ne $before) {
    Backup-Path $settingsFile
    [System.IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json -Depth 32), $Utf8NoBom)
    Write-Step "merged   plugins.json -> settings.json"; $script:Changes++
} else {
    Write-Step "ok       settings.json already lists every plugin"
}

if ($SkipPlugins) {
    Write-Step "skipped  plugin install (-SkipPlugins); Claude Code installs enabled plugins at next start"
} elseif (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Step "skipped  plugin install (claude CLI not on PATH); Claude Code installs enabled plugins at next start"
} else {
    if ((Test-Property $wanted 'extraKnownMarketplaces')) {
        foreach ($mkt in $wanted.extraKnownMarketplaces.PSObject.Properties) {
            $src = $mkt.Value.source
            $location = if ($src.source -eq 'github') { $src.repo } elseif ((Test-Property $src 'url')) { $src.url } else { $null }
            if ($location) { Invoke-ClaudeCli @('plugin', 'marketplace', 'add', $location) | Out-Null }
        }
    }
    foreach ($plugin in $wanted.enabledPlugins.PSObject.Properties) {
        if ($plugin.Value -ne $true) { continue }
        $result = Invoke-ClaudeCli @('plugin', 'install', $plugin.Name)
        if ($result.Code -eq 0) { Write-Step "ok       $($plugin.Name)" }
        else { Write-Warning "Could not install $($plugin.Name): $($result.Output)" }
    }
}

Write-Host ""
if ($script:Changes -eq 0) { Write-Host "Already up to date." }
else { Write-Host "Done: $($script:Changes) change(s). Restart Claude Code to load them." }
if (Test-Path -LiteralPath $BackupDir) { Write-Host "Backups: $BackupDir" }
