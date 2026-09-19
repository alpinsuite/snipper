# Fails on a user-visible string literal that has not gone through l10n.
#
# snipper ships English only for v0.1, but the plumbing is in from commit one:
# retrofitting AppLocalizations across every widget file later is exactly the
# audit this check exists to prevent.
#
# Exempt a product name or a symbol with a trailing comment:
#
#     const Text('Snipper')  // i18n-exempt: a product name
#
#   powershell -File tools/check_hardcoded_strings.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path 'lib/ui')) { Write-Host 'No UI yet.' -ForegroundColor Green; exit 0 }

$violations = @()

# Text('...'), tooltip: '...', label: '...', title: '...', hint: '...'
$patterns = @(
  "Text\(\s*'([^']{2,})'",
  "tooltip:\s*'([^']{2,})'",
  "label:\s*'([^']{2,})'",
  "title:\s*'([^']{2,})'",
  "hint:\s*'([^']{2,})'"
)

Get-ChildItem 'lib' -Recurse -Filter *.dart |
  Where-Object { $_.FullName -notmatch '\\l10n\\' } |
  ForEach-Object {
    $file = $_
    $lineNumber = 0
    foreach ($line in (Get-Content $file.FullName)) {
      $lineNumber++
      if ($line -match 'i18n-exempt') { continue }
      foreach ($pattern in $patterns) {
        if ($line -match $pattern) {
          $value = $Matches[1]
          # A style id, a font family or an asset path is document identity or a
          # resource name, not UI copy.
          if ($value -match '^[a-z0-9_./-]+$') { continue }
          $violations += "$($file.FullName):$lineNumber  '$value'"
          break
        }
      }
    }
  }

if ($violations.Count -gt 0) {
  Write-Host 'Hardcoded user-visible strings:' -ForegroundColor Red
  $violations | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  Write-Host "Move them to lib/l10n/app_en.arb, or mark the line 'i18n-exempt: <why>'." -ForegroundColor Yellow
  exit 1
}
Write-Host 'No hardcoded strings.' -ForegroundColor Green
