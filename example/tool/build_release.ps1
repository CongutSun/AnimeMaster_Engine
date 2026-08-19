param(
    [switch]$SplitPerAbi,
    [switch]$BuildAppBundle,
    [switch]$NoObfuscate
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$versionLine = Select-String -Path (Join-Path $projectRoot 'pubspec.yaml') `
    -Pattern '^\s*version:\s*(.+)$' |
    Select-Object -First 1
if (-not $versionLine) {
    throw 'Cannot find version in example/pubspec.yaml'
}
$versionParts = $versionLine.Matches[0].Groups[1].Value.Trim().Split('+')
if ($versionParts.Length -lt 2) {
    throw 'Release version must include an explicit build number, e.g. 2.3.6+2044.'
}
$expectedVersionCode = [int]$versionParts[1]

function Invoke-Flutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
    & flutter @FlutterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($FlutterArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Invoke-Flutter pub get

$commonReleaseArgs = @('--release')
if (-not $NoObfuscate) {
    $symbolDir = Join-Path $projectRoot 'build\symbols\android'
    if (-not (Test-Path $symbolDir)) {
        New-Item -ItemType Directory -Path $symbolDir -Force | Out-Null
    }
    $commonReleaseArgs += @(
        '--obfuscate',
        "--split-debug-info=$symbolDir"
    )
}

if ($SplitPerAbi) {
    Write-Warning (
        '-SplitPerAbi is retained for compatibility but is no longer passed ' +
        'to Flutter. Gradle splits already produce the three ABI APKs plus ' +
        'the universal APK with one consistent versionCode.'
    )
}
Invoke-Flutter build apk @commonReleaseArgs

& (Join-Path $PSScriptRoot 'verify_release.ps1') `
    -ExpectedVersionCode $expectedVersionCode
if ($LASTEXITCODE -ne 0) {
    throw "Release verification failed with exit code $LASTEXITCODE"
}

if ($BuildAppBundle) {
    Invoke-Flutter build appbundle @commonReleaseArgs
}

$apkOutputDir = Join-Path $projectRoot 'build\\app\\outputs\\flutter-apk'
if (Test-Path $apkOutputDir) {
    Get-ChildItem $apkOutputDir -Filter 'app*-release.apk' | ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        $sizeMb = [Math]::Round($_.Length / 1MB, 2)
        Write-Host "$($_.Name)  Size=${sizeMb}MB  SHA256=$($hash.Hash)"
    }
}

$bundleOutputDir = Join-Path $projectRoot 'build\\app\\outputs\\bundle\\release'
if ($BuildAppBundle -and (Test-Path $bundleOutputDir)) {
    Get-ChildItem $bundleOutputDir -Filter '*.aab' | ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        $sizeMb = [Math]::Round($_.Length / 1MB, 2)
        Write-Host "$($_.Name)  Size=${sizeMb}MB  SHA256=$($hash.Hash)"
    }
}
