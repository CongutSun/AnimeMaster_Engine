param(
    [Parameter(Mandatory = $true)]
    [string]$ApkUrl,

    [string]$Arm64ApkUrl = "",
    [string]$ArmV7ApkUrl = "",
    [string]$X64ApkUrl = "",

    [string]$Sha256 = "",
    [string]$Arm64Sha256 = "",
    [string]$ArmV7Sha256 = "",
    [string]$X64Sha256 = "",

    [string]$OutputPath = "build/app/outputs/flutter-apk/app_update.json",

    [string[]]$Notes = @("Routine update")
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$versionLine = Select-String -Path $pubspecPath -Pattern '^\s*version:\s*(.+)$' | Select-Object -First 1

if (-not $versionLine) {
    throw "Cannot find version in pubspec.yaml"
}

$versionValue = $versionLine.Matches[0].Groups[1].Value.Trim()
$parts = $versionValue.Split('+')
$versionName = $parts[0]
$buildNumber = if ($parts.Length -gt 1) { [int]$parts[1] } else { 1 }

$manifest = [ordered]@{
    version     = $versionName
    build       = $buildNumber
    apkUrl      = $ApkUrl
    notes       = $Notes
    publishedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    forceUpdate = $false
}

$apkUrls = [ordered]@{}
if ($Arm64ApkUrl.Trim()) { $apkUrls["android-arm64"] = $Arm64ApkUrl.Trim() }
if ($ArmV7ApkUrl.Trim()) { $apkUrls["android-arm"] = $ArmV7ApkUrl.Trim() }
if ($X64ApkUrl.Trim()) { $apkUrls["android-x64"] = $X64ApkUrl.Trim() }
if ($ApkUrl.Trim()) { $apkUrls["universal"] = $ApkUrl.Trim() }
if ($apkUrls.Count -gt 0) { $manifest.apkUrls = $apkUrls }

$sha256Map = [ordered]@{}
if ($Arm64Sha256.Trim()) { $sha256Map["android-arm64"] = $Arm64Sha256.Trim() }
if ($ArmV7Sha256.Trim()) { $sha256Map["android-arm"] = $ArmV7Sha256.Trim() }
if ($X64Sha256.Trim()) { $sha256Map["android-x64"] = $X64Sha256.Trim() }
if ($Sha256.Trim()) { $sha256Map["universal"] = $Sha256.Trim() }
if ($sha256Map.Count -gt 0) { $manifest.sha256 = $sha256Map }

$outputFile = Join-Path $projectRoot $OutputPath
$outputDir = Split-Path -Parent $outputFile
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $outputFile -Encoding UTF8
Write-Host "Update manifest written to $outputFile"
