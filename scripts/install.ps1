param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$pluginName = 'codex-monitor-hud'
$targetRoot = Join-Path $HOME ('plugins\' + $pluginName)
$legacyPluginRoot = Join-Path $HOME 'plugins\codex-token-strip'
$marketplacePath = Join-Path $HOME '.agents\plugins\marketplace.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD'

if (Test-Path -LiteralPath $legacyPluginRoot) {
    throw "Legacy Codex Token HUD plugin detected at $legacyPluginRoot. This is a fresh v2 identity; uninstall the legacy plugin first. No settings or legacy files were migrated or deleted."
}

# Ask an existing HUD instance to exit before replacing files. The signal does
# not touch Codex logs or saved settings and makes upgrades deterministic.
if (Test-Path -LiteralPath $stateRoot) {
    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'))
    $heartbeatPath = Join-Path $stateRoot 'hud.heartbeat'
    for ($attempt = 0; $attempt -lt 30 -and (Test-Path -LiteralPath $heartbeatPath); $attempt++) {
        Start-Sleep -Milliseconds 200
    }
}

if ((Resolve-Path -LiteralPath $SourceRoot).Path -ne $targetRoot) {
    New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
    # Developer-only material must never become part of an installed plugin.
    $excludedRootNames = @('.git','artifacts','.test-output','private','AGENTS.md','WORKSPACE_STATE.md')
    $excludedRelativePaths = @('docs/MAINTENANCE_WORKFLOW.md','scripts/prepare-delivery.ps1')
    $items = Get-ChildItem -Force -LiteralPath $SourceRoot | Where-Object { $_.Name -notin $excludedRootNames }
    foreach ($item in $items) {
        $copied = $false
        for ($attempt = 0; $attempt -lt 30 -and -not $copied; $attempt++) {
            try { Copy-Item -LiteralPath $item.FullName -Destination $targetRoot -Recurse -Force; $copied=$true }
            catch [IO.IOException] { if($attempt -ge 29){throw}; Start-Sleep -Milliseconds 200 }
        }
    }

    # A copy-only upgrade leaves obsolete scripts and skills from older builds
    # behind. The plugin directory is installer-owned, so remove files absent
    # from the validated maintenance source while keeping user settings outside
    # this directory untouched.
    foreach ($installedFile in Get-ChildItem -LiteralPath $targetRoot -Recurse -File -Force) {
        $relativePath = $installedFile.FullName.Substring($targetRoot.Length).TrimStart('\')
        $rootName = ($relativePath -split '[\\/]')[0]
        $normalizedRelativePath = $relativePath.Replace('\','/')
        if ($rootName -in $excludedRootNames -or $normalizedRelativePath -in $excludedRelativePaths -or -not (Test-Path -LiteralPath (Join-Path $SourceRoot $relativePath))) {
            Remove-Item -LiteralPath $installedFile.FullName -Force
        }
    }
    foreach ($installedDirectory in Get-ChildItem -LiteralPath $targetRoot -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending) {
        if (@(Get-ChildItem -LiteralPath $installedDirectory.FullName -Force).Count -eq 0) {
            Remove-Item -LiteralPath $installedDirectory.FullName -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marketplacePath) | Out-Null
if (Test-Path -LiteralPath $marketplacePath) {
    $marketplace = Get-Content -Raw -Encoding UTF8 -LiteralPath $marketplacePath | ConvertFrom-Json
} else {
    $marketplace = [pscustomobject]@{
        name = 'personal'
        interface = [pscustomobject]@{ displayName = 'Personal' }
        plugins = @()
    }
}

$entry = [pscustomobject]@{
    name = $pluginName
    source = [pscustomobject]@{ source = 'local'; path = './plugins/' + $pluginName }
    policy = [pscustomobject]@{ installation = 'AVAILABLE'; authentication = 'ON_INSTALL' }
    category = 'Productivity'
}
$others = @($marketplace.plugins | Where-Object { $_.name -ne $pluginName })
$marketplace.plugins = @($others + $entry)
$marketplace | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $marketplacePath

& (Join-Path $targetRoot 'scripts\test.ps1')
& (Join-Path $targetRoot 'scripts\create-shortcuts.ps1') -TargetRoot $targetRoot
& (Join-Path $targetRoot 'scripts\start.ps1') -Settings

Write-Output "Installed: $targetRoot"
Write-Output "Marketplace: $marketplacePath"
Write-Output 'Windows login startup is disabled. The Codex plugin MCP host starts the HUD when Codex loads the plugin.'
Write-Output 'Restart Codex or start a new task after enabling the plugin.'
Write-Output 'Open settings later from the desktop shortcut or Start menu: Codex Monitor HUD.'
Write-Output 'Basic monitoring is ready. Optional features remain user-controlled: proactive Codex notices and expressive choreography, Theme Workshop, API-equivalent cost, split bubbles, advanced transparency, and click-through.'
Write-Output 'After installation, explain those optional DIY features to the user; do not enable them without permission.'
