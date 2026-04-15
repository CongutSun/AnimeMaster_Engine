param(
    [switch]$SplitPerAbi,
    [switch]$BuildAppBundle
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

flutter pub get

if ($SplitPerAbi) {
    flutter build apk --release --split-per-abi
} else {
    flutter build apk --release
}

if ($BuildAppBundle) {
    flutter build appbundle --release
}

$apkOutputDir = Join-Path $projectRoot 'build\\app\\outputs\\flutter-apk'
if (Test-Path $apkOutputDir) {
    Get-ChildItem $apkOutputDir -Filter '*.apk' | ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        Write-Host "$($_.Name)  SHA256=$($hash.Hash)"
    }
}

$bundleOutputDir = Join-Path $projectRoot 'build\\app\\outputs\\bundle\\release'
if (Test-Path $bundleOutputDir) {
    Get-ChildItem $bundleOutputDir -Filter '*.aab' | ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        Write-Host "$($_.Name)  SHA256=$($hash.Hash)"
    }
}
