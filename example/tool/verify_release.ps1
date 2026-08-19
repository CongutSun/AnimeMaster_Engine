param(
    [Parameter(Mandatory = $true)]
    [int]$ExpectedVersionCode,

    [string]$ApkDirectory = "build/app/outputs/flutter-apk",

    [string]$PreviousReleaseApk = "../release/app-arm64-v8a-release.apk"
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$apkDirectoryPath = Join-Path $projectRoot $ApkDirectory
$previousReleaseApkPath = Join-Path $projectRoot $PreviousReleaseApk

$androidSdk = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
} elseif ($env:ANDROID_HOME) {
    $env:ANDROID_HOME
} else {
    throw 'ANDROID_SDK_ROOT or ANDROID_HOME must point to the Android SDK.'
}

$buildToolsRoot = Join-Path $androidSdk 'build-tools'
$buildTools = Get-ChildItem -Path $buildToolsRoot -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $buildTools) {
    throw "No Android build-tools installation found in $buildToolsRoot"
}

$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$apkSigner = Join-Path $buildTools.FullName 'apksigner.bat'
if (-not (Test-Path -LiteralPath $aapt) -or -not (Test-Path -LiteralPath $apkSigner)) {
    throw "aapt.exe or apksigner.bat is missing from $($buildTools.FullName)"
}
if (-not (Test-Path -LiteralPath $previousReleaseApkPath)) {
    throw "Previous signed release APK is required: $previousReleaseApkPath"
}

function Get-ApkVersionCode {
    param([Parameter(Mandatory = $true)][string]$Path)

    $badging = & $aapt dump badging $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect APK version: $Path"
    }
    $packageLine = $badging | Select-Object -First 1
    $match = [regex]::Match($packageLine, "versionCode='(\d+)'")
    if (-not $match.Success) {
        throw "Unable to read versionCode from $Path"
    }
    return [int]$match.Groups[1].Value
}

function Get-ApkSignerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $certificate = & $apkSigner verify --print-certs $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed: $Path"
    }
    $match = [regex]::Match(
        ($certificate -join "`n"),
        'SHA-256 digest:\s*([0-9a-fA-F]+)'
    )
    if (-not $match.Success) {
        throw "Unable to read signer SHA-256 from $Path"
    }
    return $match.Groups[1].Value.ToLowerInvariant()
}

$previousVersionCode = Get-ApkVersionCode -Path $previousReleaseApkPath
if ($ExpectedVersionCode -le $previousVersionCode) {
    throw (
        "New versionCode $ExpectedVersionCode must be greater than " +
        "previous release versionCode $previousVersionCode."
    )
}
$previousSigner = Get-ApkSignerSha256 -Path $previousReleaseApkPath

$requiredApks = @(
    'app-arm64-v8a-release.apk',
    'app-armeabi-v7a-release.apk',
    'app-x86_64-release.apk',
    'app-release.apk'
)

foreach ($apkName in $requiredApks) {
    $apkPath = Join-Path $apkDirectoryPath $apkName
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "Required release artifact is missing: $apkPath"
    }

    $actualVersionCode = Get-ApkVersionCode -Path $apkPath
    if ($actualVersionCode -ne $ExpectedVersionCode) {
        throw (
            "$apkName has versionCode $actualVersionCode; " +
            "expected $ExpectedVersionCode."
        )
    }

    $actualSigner = Get-ApkSignerSha256 -Path $apkPath
    if ($actualSigner -ne $previousSigner) {
        throw (
            "$apkName is signed by $actualSigner, but the previous release " +
            "uses $previousSigner. It cannot cover-upgrade existing installs."
        )
    }

    $hash = Get-FileHash -LiteralPath $apkPath -Algorithm SHA256
    $sizeMb = [Math]::Round((Get-Item -LiteralPath $apkPath).Length / 1MB, 2)
    Write-Host (
        "$apkName VersionCode=$actualVersionCode Size=${sizeMb}MB " +
        "SHA256=$($hash.Hash)"
    )
}

Write-Host (
    "Release verification passed. PreviousVersionCode=$previousVersionCode " +
    "NewVersionCode=$ExpectedVersionCode SignerSHA256=$previousSigner"
)
