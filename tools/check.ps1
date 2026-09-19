# The checks, in the order they fail fastest.
#
# Run from the repository root:  powershell -File tools/check.ps1
#
# This script exists as much as anything for two environment facts:
#
#  1. `flutter test` hangs indefinitely under a Git Bash shell on this machine
#     and never under PowerShell. Everything goes through here.
#  2. The bash checks must run under *Git* Bash. A `bash` resolved from
#     PowerShell can be WSL's, which reads this CRLF working tree differently
#     and reports failures that are not there. The PowerShell ports are used
#     here for that reason; the .sh copies are what CI runs on Ubuntu.
#
# What it deliberately does not do is take a screenshot. Capture is the one
# thing that cannot be proved headlessly — see docs/DECISIONS.md.

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$failed = @()

function Step {
  param([string]$Name, [scriptblock]$Body)
  Write-Host "== $Name ==" -ForegroundColor Cyan
  & $Body
  if ($LASTEXITCODE -ne 0) { $script:failed += $Name }
}

Step 'dart format' { dart format --set-exit-if-changed . }
Step 'flutter analyze' { flutter analyze --fatal-infos }

Write-Host '== localizations are current ==' -ForegroundColor Cyan
flutter gen-l10n
if ($LASTEXITCODE -ne 0) { $failed += 'flutter gen-l10n' }

Step 'layer purity' { powershell -File tools/check_layer_purity.ps1 }
Step 'hardcoded strings' { powershell -File tools/check_hardcoded_strings.ps1 }
Step 'flutter test' { flutter test }

# The SBOM is a release gate (SPEC.md 3.7), so it is a check, not a build
# step: generate it, then assert it accounts for every package in the
# lockfile. Runs last because it is the only step that reaches the network.
Step 'sbom' {
  powershell -File tools/sbom.ps1
  if ($LASTEXITCODE -eq 0) { powershell -File tools/sbom.ps1 -Check }
}

if ($failed.Count -gt 0) {
  Write-Host ''
  Write-Host 'Failed:' -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  exit 1
}
Write-Host ''
Write-Host 'Green.' -ForegroundColor Green
