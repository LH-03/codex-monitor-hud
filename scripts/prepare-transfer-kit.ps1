param(
    [Parameter(Mandatory)]
    [string]$ReleasePackage,
    [switch]$IncludeOwnerPrivate,
    [string]$Version = '3.0.0',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$releasePackage = (Resolve-Path -LiteralPath $ReleasePackage).Path
if ((Split-Path -Leaf $releasePackage) -ne 'CodexMonitorHUD-windows-x64.zip') {
    throw 'ReleasePackage must be the generated CodexMonitorHUD-windows-x64.zip file.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $kind = if ($IncludeOwnerPrivate) { 'owner-snapshot' } else { 'portable-kit' }
    $OutputRoot = Join-Path $sourceRoot ("artifacts\\{0}-v{1}-{2}" -f $kind,$Version,$stamp)
}
$outputRoot = [IO.Path]::GetFullPath($OutputRoot)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'artifacts'))
if (-not $outputRoot.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must stay under the repository artifacts directory.'
}

$stageRoot = Join-Path $outputRoot 'stage'
$sourceDestination = Join-Path $stageRoot 'source'
$releaseDestination = Join-Path $stageRoot 'release'
$archiveName = if ($IncludeOwnerPrivate) { "CodexMonitorHUD-v${Version}-owner-snapshot.zip" } else { "CodexMonitorHUD-v${Version}-portable-kit.zip" }
$archivePath = Join-Path $outputRoot $archiveName

$excludedRootNames = @('artifacts','.test-output','Microsoft')
if (-not $IncludeOwnerPrivate) {
    $excludedRootNames += @('.git','.agents','.codex','private','node_modules','sessions','logs','archive')
}
$excludedDirectoryNames = if ($IncludeOwnerPrivate) { @('bin','obj') } else { @('bin','obj') }

function Get-LongPath {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith('\\?\')) { return $fullPath }
    return '\\?\' + $fullPath
}

New-Item -ItemType Directory -Force -Path $sourceDestination,$releaseDestination | Out-Null
$files = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Where-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@([char]92,[char]47))
    $parts = $relative -split '[\\/]'
    $parts[0] -notin $excludedRootNames -and
    $parts[0] -notlike '.test-output*' -and
    @($parts | Where-Object { $_ -in $excludedDirectoryNames }).Count -eq 0
} | Sort-Object FullName

foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@([char]92,[char]47))
    $destination = Join-Path $sourceDestination $relative
    [IO.Directory]::CreateDirectory((Get-LongPath (Split-Path -Parent $destination))) | Out-Null
    [IO.File]::Copy((Get-LongPath $file.FullName), (Get-LongPath $destination), $true)
}

Copy-Item -LiteralPath $releasePackage -Destination (Join-Path $releaseDestination 'CodexMonitorHUD-windows-x64.zip') -Force
$releaseDirectory = Split-Path -Parent $releasePackage
foreach ($name in @('SHA256SUMS.txt','RELEASE_UPLOAD.md')) {
    $candidate = Join-Path $releaseDirectory $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        Copy-Item -LiteralPath $candidate -Destination (Join-Path $releaseDestination $name) -Force
    }
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'START_HERE_ON_SECOND_PC.md') -Destination (Join-Path $stageRoot 'START_HERE_ON_SECOND_PC.md') -Force

$mode = if ($IncludeOwnerPrivate) { 'owner full snapshot: private handoffs, toolchains, records, and Git history are included' } else { 'portable clean kit: private/state/Git content is excluded' }
$manifest = @"
# Transfer kit contents

Version: $Version
Mode: $mode
Source files: $($files.Count)
Release asset: CodexMonitorHUD-windows-x64.zip

Excluded from both variants: generated artifacts from prior runs and build `bin`/`obj` intermediates.
Do not upload this transfer archive to GitHub. Use the release asset under `release/` for a public GitHub Release instead.
"@
Set-Content -LiteralPath (Join-Path $stageRoot 'TRANSFER_KIT_CONTENTS.md') -Value $manifest -Encoding utf8

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $archivePath) { [IO.File]::Delete($archivePath) }
$zip = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $stageRoot -File -Recurse -Force | ForEach-Object {
        $entryName = $_.FullName.Substring($stageRoot.Length).TrimStart([char[]]@([char]92,[char]47)) -replace '\\','/'
        $entry = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
        $input = [IO.File]::OpenRead((Get-LongPath $_.FullName))
        $output = $entry.Open()
        try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
    }
} finally {
    $zip.Dispose()
}
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
"$hash  $archiveName" | Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') -Encoding ascii

Write-Output "Transfer archive: $archivePath"
Write-Output "SHA-256: $hash"
Write-Output "Source files: $($files.Count)"
Write-Output "Mode: $mode"
