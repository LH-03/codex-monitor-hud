param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$pluginName = 'codex-token-strip'
$targetRoot = Join-Path $HOME ('plugins\' + $pluginName)
$marketplacePath = Join-Path $HOME '.agents\plugins\marketplace.json'
$legacyStartup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Token Strip.lnk'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexTokenHUD'

# Ask an existing HUD instance to exit before replacing files. The signal does
# not touch Codex logs or saved settings and makes upgrades deterministic.
if (Test-Path -LiteralPath $stateRoot) {
    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'))
    Start-Sleep -Milliseconds 1200
}

if ((Resolve-Path -LiteralPath $SourceRoot).Path -ne $targetRoot) {
    New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
    $items = Get-ChildItem -Force -LiteralPath $SourceRoot | Where-Object { $_.Name -notin @('.git','artifacts','.test-output') }
    foreach ($item in $items) {
        Copy-Item -LiteralPath $item.FullName -Destination $targetRoot -Recurse -Force
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

if (Test-Path -LiteralPath $legacyStartup) { Remove-Item -LiteralPath $legacyStartup -Force }

& (Join-Path $targetRoot 'scripts\test.ps1')
& (Join-Path $targetRoot 'scripts\create-shortcuts.ps1') -TargetRoot $targetRoot
& (Join-Path $targetRoot 'scripts\start.ps1') -Settings

Write-Output "Installed: $targetRoot"
Write-Output "Marketplace: $marketplacePath"
Write-Output 'Windows login startup is disabled. The Codex plugin MCP host starts the HUD when Codex loads the plugin.'
Write-Output 'Restart Codex or start a new task after enabling the plugin.'
Write-Output 'Open settings later from the desktop shortcut or Start menu: Codex Token HUD.'
