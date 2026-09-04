param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('zh-CN','en')][string]$DefaultLanguage = 'en',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$RollbackVersion,
    [string]$PerformanceMetricsRoot,
    [switch]$UseBundledRuntime,
    [switch]$SkipLaunch,
    [switch]$SkipShortcuts
)

$ErrorActionPreference = 'Stop'
$pluginName = 'codex-monitor-hud'
$pluginsRoot = Join-Path $HOME 'plugins'
$targetRoot = Join-Path $pluginsRoot $pluginName
$legacyPluginRoot = Join-Path $pluginsRoot 'codex-token-strip'
$marketplacePath = Join-Path $HOME '.agents\plugins\marketplace.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD'
$settingsPath = Join-Path $stateRoot 'settings.json'
$encoding = New-Object Text.UTF8Encoding($false)

function Get-PluginVersion {
    param([string]$Root)
    $manifestPath = Join-Path $Root '.codex-plugin\plugin.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return 'unknown' }
    try {
        $version = [string](Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json).version
        return $(if ($version -match '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') { $version } else { 'unknown' })
    }
    catch { return 'unknown' }
}

function Stop-InstalledHud {
    if (-not (Test-Path -LiteralPath $stateRoot)) { return }
    [IO.File]::WriteAllText((Join-Path $stateRoot 'manual-exit.signal'), [DateTime]::UtcNow.ToString('O'), $encoding)
    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'), $encoding)
    $heartbeatPath = Join-Path $stateRoot 'hud.heartbeat'
    for ($attempt = 0; $attempt -lt 30 -and (Test-Path -LiteralPath $heartbeatPath); $attempt++) {
        Start-Sleep -Milliseconds 200
    }
}

function Clear-HudStopSignals {
    # Stop-InstalledHud intentionally writes both signals. A replacement host
    # must never inherit either one or it can exit immediately after launch.
    foreach ($signalName in @('manual-exit.signal','exit.signal')) {
        Remove-Item -LiteralPath (Join-Path $stateRoot $signalName) -Force -ErrorAction SilentlyContinue
    }
}

function Copy-PluginTree {
    param([string]$From, [string]$To)
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    $excludedRootNames = @('.git','.agents','.codex','artifacts','.test-output','private','node_modules','sessions','logs','archive','Microsoft','AGENTS.md','WORKSPACE_STATE.md')
    $excludedRelativePaths = @('docs/MAINTENANCE_WORKFLOW.md','docs/MACOS_PREVIEW_TESTING.md','scripts/prepare-delivery.ps1')
    foreach ($item in Get-ChildItem -Force -LiteralPath $From | Where-Object { $_.Name -notin $excludedRootNames -and $_.Name -notlike '.test-output*' }) {
        Copy-Item -LiteralPath $item.FullName -Destination $To -Recurse -Force
    }
    foreach ($relativePath in $excludedRelativePaths) {
        Remove-Item -LiteralPath (Join-Path $To $relativePath) -Force -ErrorAction SilentlyContinue
    }
    foreach ($buildDirectory in Get-ChildItem -LiteralPath $To -Recurse -Directory -Force | Where-Object { $_.Name -in @('bin','obj') } | Sort-Object { $_.FullName.Length } -Descending) {
        Remove-Item -LiteralPath $buildDirectory.FullName -Recurse -Force
    }
    foreach ($unsafeFile in Get-ChildItem -LiteralPath $To -Recurse -File -Force | Where-Object {
        $_.Name -in @('.DS_Store','Thumbs.db','settings.json') -or
        $_.Name -like '.env*' -or
        $_.Name -like '*.user.json' -or
        $_.Extension.ToLowerInvariant() -in @('.log','.zip','.db','.sqlite','.sqlite3','.jsonl')
    }) {
        Remove-Item -LiteralPath $unsafeFile.FullName -Force
    }
}

function Switch-InstalledTree {
    param([string]$StageRoot)
    Stop-InstalledHud
    $oldLocation = $null
    $temporaryOld = $null
    if (Test-Path -LiteralPath $targetRoot) {
        $installedVersion = Get-PluginVersion $targetRoot
        $rollbackRoot = Join-Path $pluginsRoot ('.codex-monitor-hud-rollback-' + $installedVersion)
        if (Test-Path -LiteralPath $rollbackRoot) {
            $temporaryOld = Join-Path $pluginsRoot ('.codex-monitor-hud-replaced-' + [Guid]::NewGuid().ToString('N'))
            Move-Item -LiteralPath $targetRoot -Destination $temporaryOld
            $oldLocation = $temporaryOld
        } else {
            Move-Item -LiteralPath $targetRoot -Destination $rollbackRoot
            $oldLocation = $rollbackRoot
        }
    }
    try {
        Move-Item -LiteralPath $StageRoot -Destination $targetRoot
    } catch {
        if ($null -ne $oldLocation -and -not (Test-Path -LiteralPath $targetRoot) -and (Test-Path -LiteralPath $oldLocation)) {
            Move-Item -LiteralPath $oldLocation -Destination $targetRoot
        }
        throw
    }
    return [pscustomobject]@{
        PreviousRoot = $oldLocation
        TemporaryPrevious = $temporaryOld
    }
}

function Complete-InstalledTreeSwitch {
    param($Transaction)
    if ($null -ne $Transaction -and
        $null -ne $Transaction.TemporaryPrevious -and
        (Test-Path -LiteralPath $Transaction.TemporaryPrevious)) {
        Remove-Item -LiteralPath $Transaction.TemporaryPrevious -Recurse -Force
    }
}

function Undo-InstalledTreeSwitch {
    param($Transaction)
    if ($null -eq $Transaction) { return }
    Stop-InstalledHud
    $failedRoot = $null
    if (Test-Path -LiteralPath $targetRoot) {
        $failedRoot = Join-Path $pluginsRoot ('.codex-monitor-hud-failed-' + [Guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $targetRoot -Destination $failedRoot
    }
    try {
        if ($null -ne $Transaction.PreviousRoot -and (Test-Path -LiteralPath $Transaction.PreviousRoot)) {
            Move-Item -LiteralPath $Transaction.PreviousRoot -Destination $targetRoot
        }
    } catch {
        if ($null -ne $failedRoot -and
            (Test-Path -LiteralPath $failedRoot) -and
            -not (Test-Path -LiteralPath $targetRoot)) {
            Move-Item -LiteralPath $failedRoot -Destination $targetRoot
            $failedRoot = $null
        }
        throw
    } finally {
        if ($null -ne $failedRoot -and (Test-Path -LiteralPath $failedRoot)) {
            Remove-Item -LiteralPath $failedRoot -Recurse -Force
        }
    }
}

function Update-PersonalMarketplace {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marketplacePath) | Out-Null
    if (Test-Path -LiteralPath $marketplacePath) {
        $marketplace = Get-Content -Raw -Encoding UTF8 -LiteralPath $marketplacePath | ConvertFrom-Json
    } else {
        $marketplace = [pscustomobject]@{ name='personal'; interface=[pscustomobject]@{displayName='Personal'}; plugins=@() }
    }
    $entry = [pscustomobject]@{
        name = $pluginName
        source = [pscustomobject]@{ source='local'; path='./plugins/' + $pluginName }
        policy = [pscustomobject]@{ installation='AVAILABLE'; authentication='ON_INSTALL' }
        category = 'Productivity'
    }
    $marketplace.plugins = @(@($marketplace.plugins | Where-Object { $_.name -ne $pluginName }) + $entry)
    $temporary = $marketplacePath + '.tmp.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, ($marketplace | ConvertTo-Json -Depth 8), $encoding)
        Move-Item -LiteralPath $temporary -Destination $marketplacePath -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Assert-MarketplaceReadable {
    if (-not (Test-Path -LiteralPath $marketplacePath)) { return }
    try { $null = Get-Content -Raw -Encoding UTF8 -LiteralPath $marketplacePath | ConvertFrom-Json }
    catch { throw "Personal marketplace JSON is invalid; installation was not switched: $marketplacePath" }
}

function Get-MarketplaceSnapshot {
    if (Test-Path -LiteralPath $marketplacePath) {
        return [pscustomobject]@{ Exists=$true; Bytes=[IO.File]::ReadAllBytes($marketplacePath) }
    }
    return [pscustomobject]@{ Exists=$false; Bytes=$null }
}

function Restore-MarketplaceSnapshot {
    param($Snapshot)
    if ($null -eq $Snapshot) { return }
    if ($Snapshot.Exists) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marketplacePath) | Out-Null
        [IO.File]::WriteAllBytes($marketplacePath, [byte[]]$Snapshot.Bytes)
    } else {
        Remove-Item -LiteralPath $marketplacePath -Force -ErrorAction SilentlyContinue
    }
}

New-Item -ItemType Directory -Force -Path $pluginsRoot | Out-Null

if (-not [string]::IsNullOrWhiteSpace($RollbackVersion)) {
    $rollbackRoot = Join-Path $pluginsRoot ('.codex-monitor-hud-rollback-' + $RollbackVersion)
    if (-not (Test-Path -LiteralPath $rollbackRoot)) { throw "No local rollback copy exists for $RollbackVersion at $rollbackRoot." }
    if ((Get-PluginVersion $rollbackRoot) -ne $RollbackVersion) { throw 'Rollback copy manifest does not match the requested version.' }
    foreach ($required in @('.codex-plugin\plugin.json','config.default.json','scripts\start.ps1','src\CodexMonitorHUD.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $rollbackRoot $required))) { throw "Rollback copy is incomplete: $required" }
    }
    $rollbackStage = Join-Path $pluginsRoot ('.codex-monitor-hud-stage-' + [Guid]::NewGuid().ToString('N'))
    $rollbackTransaction = $null
    $rollbackMarketplaceSnapshot = Get-MarketplaceSnapshot
    try {
        Copy-PluginTree $rollbackRoot $rollbackStage
        Assert-MarketplaceReadable
        $rollbackTransaction = Switch-InstalledTree $rollbackStage
        try {
            Update-PersonalMarketplace
            if (-not $SkipShortcuts) {
                & (Join-Path $targetRoot 'scripts\create-shortcuts.ps1') -TargetRoot $targetRoot
            }
            Clear-HudStopSignals
            & (Join-Path $targetRoot 'scripts\start.ps1') -Settings
            Complete-InstalledTreeSwitch $rollbackTransaction
        } catch {
            try { Undo-InstalledTreeSwitch $rollbackTransaction }
            finally { Restore-MarketplaceSnapshot $rollbackMarketplaceSnapshot }
            throw
        }
        Write-Output "Rolled back: $targetRoot -> $RollbackVersion"
    } finally {
        if (Test-Path -LiteralPath $rollbackStage) { Remove-Item -LiteralPath $rollbackStage -Recurse -Force }
    }
    return
}

if (Test-Path -LiteralPath $legacyPluginRoot) {
    throw "Legacy Codex Token HUD plugin detected at $legacyPluginRoot. Uninstall that separate v1 identity first; no files were changed."
}

$compiledApp = Join-Path $SourceRoot 'runtime\win-x64\app\CodexMonitorHud.dll'
$buildScript = Join-Path $SourceRoot 'scripts\build-dotnet.ps1'
$privateSdk = Join-Path $SourceRoot 'private\toolchain\dotnet\dotnet.exe'
$systemSdk = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $UseBundledRuntime -and (Test-Path -LiteralPath $buildScript) -and ((Test-Path -LiteralPath $privateSdk) -or $null -ne $systemSdk)) {
    # A staged runtime may belong to an earlier source edit. Developer installs
    # always rebuild when an SDK is available; installed copies can still be
    # repaired or rolled back without requiring a global SDK.
    & $buildScript -Configuration Release
} elseif (-not (Test-Path -LiteralPath $compiledApp)) {
    throw 'The compiled v3.2.2 runtime is missing and no .NET 10 SDK is available to build it.'
}

$stageRoot = Join-Path $pluginsRoot ('.codex-monitor-hud-stage-' + [Guid]::NewGuid().ToString('N'))
$validationRoot = Join-Path $env:TEMP ('codex-monitor-hud-install-gate-' + [Guid]::NewGuid().ToString('N'))
$healthPath = Join-Path $validationRoot 'health.json'
$installTransaction = $null
$settingsCreated = $false
$marketplaceSnapshot = Get-MarketplaceSnapshot
try {
    Copy-PluginTree $SourceRoot $stageRoot
    $stageDotnet = Join-Path $stageRoot 'runtime\win-x64\dotnet\dotnet.exe'
    $stageApp = Join-Path $stageRoot 'runtime\win-x64\app\CodexMonitorHud.dll'
    & $stageDotnet $stageApp --plugin-root $stageRoot --health-check $healthPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $healthPath)) { throw 'Staged install health check failed.' }
    $health = Get-Content -Raw -Encoding UTF8 -LiteralPath $healthPath | ConvertFrom-Json
    if ([string]$health.version -ne '3.2.2' -or [string]$health.config -ne 'ok' -or [string]$health.xaml -ne 'ok' -or [string]$health.parser -ne 'ok') {
        throw ('Staged install health check returned an invalid result: ' + ($health | ConvertTo-Json -Compress))
    }
    # Full static tests are a source-tree/release gate.  A user install only
    # needs the staged runtime health check above before the atomic switch.
    Assert-MarketplaceReadable
    $installTransaction = Switch-InstalledTree $stageRoot
    try {
        Update-PersonalMarketplace
        if (-not (Test-Path -LiteralPath $settingsPath)) {
            New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
            $initialSettings = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $targetRoot 'config.default.json') | ConvertFrom-Json
            $initialSettings.language = $DefaultLanguage
            $settingsTemporary = $settingsPath + '.tmp.' + [Guid]::NewGuid().ToString('N')
            try {
                [IO.File]::WriteAllText($settingsTemporary, ($initialSettings | ConvertTo-Json -Depth 12), $encoding)
                Move-Item -LiteralPath $settingsTemporary -Destination $settingsPath
                $settingsCreated = $true
            } finally {
                Remove-Item -LiteralPath $settingsTemporary -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $SkipShortcuts) {
            & (Join-Path $targetRoot 'scripts\create-shortcuts.ps1') -TargetRoot $targetRoot
        }
        Clear-HudStopSignals
        if (-not $SkipLaunch) {
            & (Join-Path $targetRoot 'scripts\start.ps1') -Settings
        }
        Complete-InstalledTreeSwitch $installTransaction
    } catch {
        if ($settingsCreated) { Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue }
        try { Undo-InstalledTreeSwitch $installTransaction }
        finally { Restore-MarketplaceSnapshot $marketplaceSnapshot }
        if (Test-Path -LiteralPath (Join-Path $targetRoot 'scripts\create-shortcuts.ps1')) {
            try { & (Join-Path $targetRoot 'scripts\create-shortcuts.ps1') -TargetRoot $targetRoot } catch { }
        }
        throw
    }
} finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
    if (Test-Path -LiteralPath $validationRoot) { Remove-Item -LiteralPath $validationRoot -Recurse -Force }
}

Write-Output "Installed transactionally: $targetRoot"
Write-Output "Marketplace: $marketplacePath"
Write-Output "Rollback command: scripts\install.ps1 -RollbackVersion <version>"
Write-Output "First-install language: $DefaultLanguage (existing settings are preserved)"
Write-Output 'Windows login startup is disabled. The Codex plugin MCP host starts the HUD when Codex loads the plugin.'
Write-Output 'Restart Codex or start a new task after enabling the plugin.'
Write-Output 'Basic monitoring is ready. Optional features remain user-controlled: proactive Codex notices and expressive choreography, Theme Workshop, API-equivalent cost, split bubbles, advanced transparency, and click-through.'
