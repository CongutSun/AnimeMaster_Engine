param(
    [Parameter(Mandatory = $true)]
    [int]$ExpectedVersionCode,

    [string]$ApkDirectory = "build/app/outputs/flutter-apk",

    [string]$ReleaseManifest = "../release/app_update.json",

    [string]$ReleaseIdentity = "../release/release_identity.json"
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$apkDirectoryPath = Join-Path $projectRoot $ApkDirectory
$releaseManifestPath = Join-Path $projectRoot $ReleaseManifest
$releaseIdentityPath = Join-Path $projectRoot $ReleaseIdentity

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
if (-not (Test-Path -LiteralPath $releaseManifestPath)) {
    throw "Release manifest is required: $releaseManifestPath"
}
if (-not (Test-Path -LiteralPath $releaseIdentityPath)) {
    throw "Release identity is required: $releaseIdentityPath"
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

function Get-ApkPackageName {
    param([Parameter(Mandatory = $true)][string]$Path)

    $badging = & $aapt dump badging $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect APK package: $Path"
    }
    $packageLine = $badging | Select-Object -First 1
    $match = [regex]::Match($packageLine, "package:\s+name='([^']+)'"
    )
    if (-not $match.Success) {
        throw "Unable to read package name from $Path"
    }
    return $match.Groups[1].Value
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return ([System.BitConverter]::ToString($bytes)).Replace('-', '')
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

$publishedManifest = [System.IO.File]::ReadAllText(
    $releaseManifestPath,
    [System.Text.Encoding]::UTF8
) | ConvertFrom-Json
$identity = [System.IO.File]::ReadAllText(
    $releaseIdentityPath,
    [System.Text.Encoding]::UTF8
) | ConvertFrom-Json
$publishedVersionCode = [int]$publishedManifest.build
$trustedSigner = ([string]$identity.signerSha256).Trim().ToLowerInvariant()
$expectedPackageName = ([string]$identity.packageName).Trim()

if ($ExpectedVersionCode -lt $publishedVersionCode) {
    throw (
        "Build versionCode $ExpectedVersionCode cannot be lower than " +
        "published versionCode $publishedVersionCode."
    )
}
if ($trustedSigner -notmatch '^[0-9a-f]{64}$') {
    throw 'release_identity.json contains an invalid signerSha256.'
}
if (-not $expectedPackageName) {
    throw 'release_identity.json contains an invalid packageName.'
}

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

    $actualPackageName = Get-ApkPackageName -Path $apkPath
    if ($actualPackageName -ne $expectedPackageName) {
        throw (
            "$apkName uses package $actualPackageName; " +
            "expected $expectedPackageName."
        )
    }

    $actualSigner = Get-ApkSignerSha256 -Path $apkPath
    if ($actualSigner -ne $trustedSigner) {
        throw (
            "$apkName is signed by $actualSigner, but the trusted release " +
            "identity uses $trustedSigner."
        )
    }

    $hash = Get-FileSha256 -Path $apkPath
    $sizeMb = [Math]::Round((Get-Item -LiteralPath $apkPath).Length / 1MB, 2)
    Write-Host (
        "$apkName VersionCode=$actualVersionCode Size=${sizeMb}MB " +
        "SHA256=$hash"
    )
}

Write-Host (
    "Release verification passed. PublishedVersionCode=$publishedVersionCode " +
    "BuildVersionCode=$ExpectedVersionCode Package=$expectedPackageName " +
    "SignerSHA256=$trustedSigner"
)
