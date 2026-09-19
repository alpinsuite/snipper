# Enforces the one-way dependency arrow.
#
#   lib/ui -> lib/controller -> lib/tools -> lib/model, lib/ops, lib/io,
#                                            lib/capture, lib/overlay, lib/core
#
# The rules that matter, and why:
#
#  * lib/model and lib/ops import no widgets. That is what keeps the geometry,
#    the annotation maths and the frame packing assertable without pumping a
#    widget — and those are the parts no screenshot can check, because a
#    selection one pixel out looks exactly like one that is right.
#  * lib/capture and lib/overlay import no widgets either. They talk to the
#    platform; a dependency on the widget tree there is a capture path that can
#    only be exercised by running the application.
#  * Only lib/ui imports the widget kit. slate_ui below the interface layer is
#    a controller that has started making layout decisions.
#  * Nothing below lib/ui imports lib/ui, and lib/model imports nothing from
#    any layer above it.
#
#   powershell -File tools/check_layer_purity.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$violations = @()

function Add-Violation($file, $message) {
  $script:violations += "$file`: $message"
}

function Get-Sources($dir) {
  if (-not (Test-Path $dir)) { return @() }
  Get-ChildItem $dir -Recurse -Filter *.dart -ErrorAction SilentlyContinue
}

# --- the headless layers import no widgets -----------------------------------
# dart:ui is fine and necessary: Rect, Offset, Image and Canvas all live there,
# and none of them needs a binding. It is widgets/, material/, painting/ and
# rendering/ that drag in the tree.
$widgetImports = "import\s+'package:flutter/(widgets|material|painting|rendering|cupertino)\.dart'"
foreach ($layer in 'model', 'ops', 'capture', 'overlay') {
  foreach ($file in Get-Sources "lib/$layer") {
    $text = Get-Content $file.FullName -Raw
    if ($text -match $widgetImports) {
      Add-Violation $file.FullName "imports Flutter widgets; lib/$layer must stay headless"
    }
    if ($text -match "import\s+'package:slate_ui/") {
      Add-Violation $file.FullName "imports slate_ui; only lib/ui draws"
    }
  }
}

# --- only the interface layer draws ------------------------------------------
foreach ($layer in 'model', 'ops', 'capture', 'overlay', 'controller', 'io', 'core', 'tools') {
  foreach ($file in Get-Sources "lib/$layer") {
    $text = Get-Content $file.FullName -Raw
    if ($layer -ne 'ui' -and $text -match "import\s+'\.\./ui/") {
      Add-Violation $file.FullName "imports lib/ui; the arrow only points inward"
    }
  }
}

# --- the model is the innermost layer ----------------------------------------
foreach ($file in Get-Sources 'lib/model') {
  $text = Get-Content $file.FullName -Raw
  foreach ($above in 'controller', 'capture', 'overlay', 'ops', 'io', 'tools') {
    if ($text -match "import\s+'\.\./$above/") {
      Add-Violation $file.FullName "imports lib/$above; the model depends on nothing"
    }
  }
}

if ($violations.Count -gt 0) {
  Write-Host 'Layer violations:' -ForegroundColor Red
  $violations | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  exit 1
}
Write-Host 'Layers are clean.' -ForegroundColor Green
