param(
    [Parameter(Mandatory = $true)]
    [string]$ApkUrl,

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

$outputFile = Join-Path $projectRoot $OutputPath
$outputDir = Split-Path -Parent $outputFile
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $outputFile -Encoding UTF8
Write-Host "Update manifest written to $outputFile"
