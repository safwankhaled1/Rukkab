param([string]$Flutter = "$PSScriptRoot/../work/flutter-sdk/bin/flutter.bat")
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path "$PSScriptRoot/..").Path
$env:PUB_CACHE = Join-Path $projectRoot 'work/pub-cache'
$env:CI = 'true'
Push-Location (Join-Path $projectRoot 'apps/mobile')
try {
    & $Flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    & $Flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
} finally { Pop-Location }
