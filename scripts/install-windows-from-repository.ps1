param(
    [ValidateSet('Install','Repair','Rollback','Uninstall')][string]$Operation = 'Install',
    [ValidateSet('zh-CN','en')][string]$DefaultLanguage = 'en',
    [string]$RollbackVersion = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $root 'install-manifest.json') -Encoding UTF8 -Raw | ConvertFrom-Json

if (-not [Environment]::Is64BitOperatingSystem) { throw 'status=unsupported platform=windows architecture=x86' }
if ($Operation -eq 'Rollback') {
    if ([string]::IsNullOrWhiteSpace($RollbackVersion)) { throw '-RollbackVersion is required for rollback.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\install.ps1') -RollbackVersion $RollbackVersion
    exit $LASTEXITCODE
}
if ($Operation -eq 'Uninstall') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\uninstall.ps1')
    exit $LASTEXITCODE
}

$asset = [string]$manifest.platforms.'windows-x64'.asset
$baseUrl = '{0}/releases/download/{1}' -f $manifest.repository,$manifest.releaseTag
$temporaryRoot = Join-Path $env:TEMP ('codex-monitor-hud-repository-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null

function Receive-TrustedFile([string]$Uri,[string]$Destination) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
        return $true
    } catch [Net.WebException] {
        $response = $_.Exception.Response
        if ($null -ne $response -and [int]$response.StatusCode -eq 404) { return $false }
        throw 'status=failed reason=release-network'
    }
}

try {
    $checksumsPath = Join-Path $temporaryRoot 'SHA256SUMS.txt'
    $archivePath = Join-Path $temporaryRoot $asset
    $releaseAvailable = Receive-TrustedFile "$baseUrl/$($manifest.checksumAsset)" $checksumsPath
    if ($releaseAvailable) { $releaseAvailable = Receive-TrustedFile "$baseUrl/$asset" $archivePath }

    if ($releaseAvailable) {
        $checksumLine = Get-Content -LiteralPath $checksumsPath -Encoding ASCII |
            Where-Object { $_ -match ('^[0-9A-Fa-f]{64}\s+\*?' + [regex]::Escape($asset) + '$') } |
            Select-Object -First 1
        if ($null -eq $checksumLine) { throw 'status=failed reason=checksum-entry-missing' }
        $expected = ($checksumLine -split '\s+')[0].ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -ne $actual) { throw 'status=failed reason=checksum-mismatch' }

        $stage = Join-Path $temporaryRoot 'stage'
        Expand-Archive -LiteralPath $archivePath -DestinationPath $stage
        $candidateInstaller = Get-ChildItem -LiteralPath $stage -Recurse -File -Filter 'install.ps1' |
            Where-Object { $_.FullName -match '[\\/]scripts[\\/]install\.ps1$' } |
            Select-Object -First 1
        if ($null -eq $candidateInstaller) { throw 'status=failed reason=release-layout' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $candidateInstaller.FullName -DefaultLanguage $DefaultLanguage
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\install.ps1') -DefaultLanguage $DefaultLanguage
    }
    if ($LASTEXITCODE -ne 0) { throw "status=failed reason=installer-exit-$LASTEXITCODE" }
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
