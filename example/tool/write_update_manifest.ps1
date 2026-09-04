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

function Assert-HttpsUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    [Uri]$parsed = $null
    if (-not [Uri]::TryCreate($Value.Trim(), [UriKind]::Absolute, [ref]$parsed) -or
        $parsed.Scheme -ne 'https' -or
        -not $parsed.Host) {
        throw "$Name must be an absolute HTTPS URL."
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Release APK is missing: $Path"
    }
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

Assert-HttpsUrl -Name 'ApkUrl' -Value $ApkUrl
if ($Arm64ApkUrl.Trim()) { Assert-HttpsUrl -Name 'Arm64ApkUrl' -Value $Arm64ApkUrl }
if ($ArmV7ApkUrl.Trim()) { Assert-HttpsUrl -Name 'ArmV7ApkUrl' -Value $ArmV7ApkUrl }
if ($X64ApkUrl.Trim()) { Assert-HttpsUrl -Name 'X64ApkUrl' -Value $X64ApkUrl }

$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$versionLine = Select-String -Path $pubspecPath -Pattern '^\s*version:\s*(.+)$' | Select-Object -First 1

if (-not $versionLine) {
    throw "Cannot find version in pubspec.yaml"
}

$versionValue = $versionLine.Matches[0].Groups[1].Value.Trim()
$parts = $versionValue.Split('+')
$versionName = $parts[0]
$buildNumber = if ($parts.Length -gt 1) { [int]$parts[1] } else { 1 }

$apkOutputDirectory = Join-Path $projectRoot 'build/app/outputs/flutter-apk'
if (-not $Sha256.Trim()) {
    $Sha256 = Get-FileSha256 -Path (Join-Path $apkOutputDirectory 'app-release.apk')
}
if ($Arm64ApkUrl.Trim() -and -not $Arm64Sha256.Trim()) {
    $Arm64Sha256 = Get-FileSha256 -Path (Join-Path $apkOutputDirectory 'app-arm64-v8a-release.apk')
}
if ($ArmV7ApkUrl.Trim() -and -not $ArmV7Sha256.Trim()) {
    $ArmV7Sha256 = Get-FileSha256 -Path (Join-Path $apkOutputDirectory 'app-armeabi-v7a-release.apk')
}
if ($X64ApkUrl.Trim() -and -not $X64Sha256.Trim()) {
    $X64Sha256 = Get-FileSha256 -Path (Join-Path $apkOutputDirectory 'app-x86_64-release.apk')
}

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
