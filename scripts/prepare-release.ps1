param(
    [string]$Version = '3.0.0',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputRoot = Join-Path $sourceRoot ("artifacts\\release-v{0}-{1}" -f $Version,$stamp)
}
$outputRoot = [IO.Path]::GetFullPath($OutputRoot)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'artifacts'))
if (-not $outputRoot.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must stay under the repository artifacts directory.'
}

$stageRoot = Join-Path $outputRoot 'stage'
$archiveName = 'CodexMonitorHUD-windows-x64.zip'
$archivePath = Join-Path $outputRoot $archiveName
$excludedRootNames = @('.git','.agents','.codex','artifacts','.test-output','private','node_modules','sessions','logs','archive','Microsoft')
$excludedDirectoryNames = @('bin','obj')
$excludedFileNames = @('.DS_Store','Thumbs.db','settings.json','AGENTS.md','WORKSPACE_STATE.md')
$excludedExtensions = @('.log','.zip','.db','.sqlite','.sqlite3','.jsonl')
$excludedRelativePaths = @('docs/MAINTENANCE_WORKFLOW.md','docs/MACOS_PREVIEW_TESTING.md','scripts/prepare-delivery.ps1')

New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
$files = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Where-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@([char]92,[char]47))
    $parts = $relative -split '[\\/]'
    $rootName = $parts[0]
    $rootName -notin $excludedRootNames -and
    $rootName -notlike '.test-output*' -and
    @($parts | Where-Object { $_ -in $excludedDirectoryNames }).Count -eq 0 -and
    ($relative -replace '\\','/') -notin $excludedRelativePaths -and
    $_.Name -notin $excludedFileNames -and
    $_.Extension.ToLowerInvariant() -notin $excludedExtensions -and
    $_.Name -notlike '.env*' -and
    $_.Name -notlike '*.user.json'
} | Sort-Object FullName

if ($files.Count -eq 0) { throw 'No public package files were found.' }
foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@([char]92,[char]47))
    $destination = Join-Path $stageRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
}

$packageFiles = Get-ChildItem -LiteralPath $stageRoot -File -Recurse -Force | ForEach-Object {
    $_.FullName.Substring($stageRoot.Length).TrimStart([char[]]@([char]92,[char]47)) -replace '\\','/'
} | Sort-Object
$packageFiles | Set-Content -LiteralPath (Join-Path $outputRoot 'PACKAGE_FILES.txt') -Encoding utf8
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
"$hash  $archiveName" | Set-Content -LiteralPath (Join-Path $outputRoot 'SHA256SUMS.txt') -Encoding ascii

$upload = @"
# Release upload fields

Archive: $archiveName

SHA-256:

~~~text
$hash  $archiveName
~~~

Package files: $($packageFiles.Count)

Upload the archive and SHA256SUMS.txt to the normal v${Version} GitHub Release after the main commit is pushed. Use GITHUB_RELEASE_DRAFT_${Version}.md for the title and body.
"@
Set-Content -LiteralPath (Join-Path $outputRoot 'RELEASE_UPLOAD.md') -Value $upload -Encoding utf8

Write-Output "Release package: $archivePath"
Write-Output "SHA-256: $hash"
Write-Output "Package files: $($packageFiles.Count)"
Write-Output "Upload fields: $(Join-Path $outputRoot 'RELEASE_UPLOAD.md')"
