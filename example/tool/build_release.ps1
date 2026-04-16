param(
    [switch]$SplitPerAbi,
    [switch]$BuildAppBundle,
    [switch]$NoObfuscate
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

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
    Invoke-Flutter build apk @commonReleaseArgs --split-per-abi
} else {
    Invoke-Flutter build apk @commonReleaseArgs
}

if ($BuildAppBundle) {
    Invoke-Flutter build appbundle @commonReleaseArgs
}

$apkOutputDir = Join-Path $projectRoot 'build\\app\\outputs\\flutter-apk'
if (Test-Path $apkOutputDir) {
    $apkFilter = if ($SplitPerAbi) { 'app-*-release.apk' } else { 'app-release.apk' }
    Get-ChildItem $apkOutputDir -Filter $apkFilter | ForEach-Object {
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
