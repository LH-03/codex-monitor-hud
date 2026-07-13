param([switch]$RemoveSettings)

$ErrorActionPreference = 'Stop'
$pluginName = 'codex-token-strip'
$targetRoot = Join-Path $HOME ('plugins\' + $pluginName)
$marketplacePath = Join-Path $HOME '.agents\plugins\marketplace.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexTokenHUD'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Token HUD Settings.lnk'
$startMenuFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Token HUD'

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'))

if (Test-Path -LiteralPath $marketplacePath) {
    $marketplace = Get-Content -Raw -Encoding UTF8 -LiteralPath $marketplacePath | ConvertFrom-Json
    $marketplace.plugins = @($marketplace.plugins | Where-Object { $_.name -ne $pluginName })
    $marketplace | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $marketplacePath
}

if ((Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path -ne $targetRoot -and (Test-Path -LiteralPath $targetRoot)) {
    Remove-Item -LiteralPath $targetRoot -Recurse -Force
} else {
    Write-Output "Plugin files remain at $targetRoot because the uninstaller is running from that directory. Remove it after Codex closes."
}

if ($RemoveSettings -and (Test-Path -LiteralPath $stateRoot)) {
    Start-Sleep -Milliseconds 900
    Remove-Item -LiteralPath $stateRoot -Recurse -Force
}

if (Test-Path -LiteralPath $desktopShortcut) { Remove-Item -LiteralPath $desktopShortcut -Force }
if (Test-Path -LiteralPath $startMenuFolder) { Remove-Item -LiteralPath $startMenuFolder -Recurse -Force }

Write-Output 'Codex Token HUD was removed from the personal marketplace.'
