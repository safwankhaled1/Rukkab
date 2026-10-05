param(
    [string]$DeviceId = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$mobileDirectory = Join-Path $projectRoot 'apps\mobile'
$configuration = Join-Path $mobileDirectory 'config.json'
if (!(Test-Path -LiteralPath $configuration)) {
    throw 'Create apps/mobile/config.json from config.example.json with the Supabase URL and public key.'
}

$localFlutter = Join-Path $projectRoot 'work\flutter-sdk\bin\flutter.bat'
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterExecutable = if (Test-Path -LiteralPath $localFlutter) { $localFlutter } elseif ($flutterCommand) { $flutterCommand.Source } else { throw 'Flutter SDK was not found.' }

if (!$env:ANDROID_HOME) {
    $androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path -LiteralPath $androidSdk) { $env:ANDROID_HOME = $androidSdk }
}
if (!$env:JAVA_HOME) {
    $androidStudioJava = 'C:\Program Files\Android\Android Studio\jbr'
    if (Test-Path -LiteralPath $androidStudioJava) { $env:JAVA_HOME = $androidStudioJava }
}
if (Test-Path -LiteralPath (Join-Path $projectRoot 'work\pub-cache')) {
    $env:PUB_CACHE = Join-Path $projectRoot 'work\pub-cache'
}

Push-Location $mobileDirectory
try {
    & $flutterExecutable run -d $DeviceId --dart-define-from-file=config.json
    if ($LASTEXITCODE -ne 0) { throw "Flutter exited with code $LASTEXITCODE." }
} finally {
    Pop-Location
}
