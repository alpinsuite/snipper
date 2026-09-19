# The Software Bill of Materials for Snipper.
#
# The PowerShell port of tools/sbom.sh, and the one check.ps1 runs. Same reason
# as the other ports in this directory: a `bash` resolved from PowerShell can
# be WSL's, which reads this CRLF working tree differently. The .sh copy is
# what CI runs on Ubuntu.
#
#   powershell -File tools/sbom.ps1           write build/sbom.cdx.json
#   powershell -File tools/sbom.ps1 -Check    verify it is complete and current
#
# The document is CycloneDX JSON resolved from pubspec.lock, never from
# pubspec.yaml: the manifest records the version ranges that were asked for,
# the lockfile records the versions that were actually built, and only the
# second one describes the binary somebody is holding.
#
# Needs Node, for npx.

param([switch]$Check)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$Out = if ($env:SBOM_OUT) { $env:SBOM_OUT } else { 'build/sbom.cdx.json' }
$Major = if ($env:CDXGEN_MAJOR) { $env:CDXGEN_MAJOR } else { '12' }

function Fail([string]$Message) {
  Write-Host "error: $Message" -ForegroundColor Red
  exit 1
}

if (-not (Test-Path 'pubspec.lock')) {
  Fail "pubspec.lock is missing - run 'flutter pub get' first."
}

# Every package name in the lockfile. Parsed directly because the shape is
# fixed, and the alternative is adding a YAML dependency to the one script
# whose job is to account for dependencies.
function Get-LockPackages {
  $names = @()
  $inPackages = $false
  foreach ($line in (Get-Content 'pubspec.lock')) {
    if ($line -match '^packages:\s*$') { $inPackages = $true; continue }
    if ($inPackages -and $line -match '^\S') { break }
    if ($inPackages -and $line -match '^  ([A-Za-z0-9_]+):\s*$') { $names += $Matches[1] }
  }
  return $names
}

if (-not $Check) {
  $dir = Split-Path -Parent $Out
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  if (Test-Path $Out) { Remove-Item $Out -Force }

  Write-Host "generating $Out from pubspec.lock"
  & npx --yes "@cyclonedx/cdxgen@$Major" --type dart --output $Out . | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail 'cdxgen failed.' }
  if (-not (Test-Path $Out)) { Fail 'cdxgen produced no SBOM.' }

  $sbom = Get-Content $Out -Raw | ConvertFrom-Json
  if (-not $sbom.components -or $sbom.components.Count -eq 0) {
    Fail 'the SBOM lists no components.'
  }
  Write-Host "  $($sbom.bomFormat) $($sbom.specVersion), $($sbom.components.Count) components"
  exit 0
}

# --- verify -----------------------------------------------------------------
# The three ways a stale SBOM lies about what shipped: it is not there, it is
# older than the lockfile, or the lockfile gained a package it never saw.
if (-not (Test-Path $Out)) { Fail "$Out is missing - run 'powershell -File tools/sbom.ps1'." }
if ((Get-Item $Out).LastWriteTime -lt (Get-Item 'pubspec.lock').LastWriteTime) {
  Fail "$Out is older than pubspec.lock - regenerate it."
}

$sbom = Get-Content $Out -Raw | ConvertFrom-Json
$have = @{}
foreach ($c in $sbom.components) { $have[$c.name] = $true }
$missing = @(Get-LockPackages | Where-Object { -not $have.ContainsKey($_) })

if ($missing.Count -gt 0) {
  Fail "$Out is missing $($missing.Count) package(s) from pubspec.lock: $($missing -join ', ')"
}
Write-Host "  $Out covers all $($have.Count) components in the lockfile"
