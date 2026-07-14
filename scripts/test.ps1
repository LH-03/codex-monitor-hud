$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore
$root = Split-Path -Parent $PSScriptRoot
$main = Join-Path $root 'src\CodexTokenHUD.ps1'
$core = Join-Path $root 'src\TokenHud.Core.psm1'

foreach ($path in @($main, $core)) {
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
    if ($errors.Count) { throw ($errors | ForEach-Object { $_.ToString() } | Out-String) }
}

[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\HudWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\SettingsWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\ColorPickerWindow.xaml')) | Out-Null

$result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $main -SelfTest | ConvertFrom-Json
if (-not $result.accounting_ok) { throw 'Token accounting self-test failed.' }
if (($result.cached + $result.uncached) -ne $result.input) { throw 'Input split self-test failed.' }
if (($result.input + $result.output) -ne $result.call_total) { throw 'Call total self-test failed.' }

Import-Module $core -Force
$completeTail = Split-HudJsonLines '' '{"type":"event_msg","payload":{"type":"token_count"}}'
if ($completeTail.CompleteLines.Count -ne 1 -or -not [string]::IsNullOrEmpty([string]$completeTail.PendingText)) { throw 'Complete no-newline JSON tail self-test failed.' }
$partialTail = Split-HudJsonLines '' '{"type":"event_msg"'
if ($partialTail.CompleteLines.Count -ne 0 -or [string]::IsNullOrEmpty([string]$partialTail.PendingText)) { throw 'Partial JSON tail retention self-test failed.' }
$locale = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'locales\en.json') | ConvertFrom-Json
$a = [pscustomobject]@{ Timestamp=[DateTimeOffset]::Now.AddSeconds(-1); Input=100; Cached=60; Uncached=40; Output=20; Reasoning=5; CallTotal=120; TaskTotal=1000; ContextPercent=30; ContextWindow=1000; Model='model-a' }
$b = [pscustomobject]@{ Timestamp=[DateTimeOffset]::Now; Input=200; Cached=150; Uncached=50; Output=30; Reasoning=7; CallTotal=230; TaskTotal=2000; ContextPercent=40; ContextWindow=2000; Model='model-b' }
$merged = Merge-HudSnapshots @($a,$b) $locale
if ($merged.Input -ne 300 -or $merged.Cached -ne 210 -or $merged.Uncached -ne 90 -or $merged.CallTotal -ne 350 -or $merged.TaskTotal -ne 3000 -or $merged.ActiveTasks -ne 2) {
    throw 'Concurrent aggregate self-test failed.'
}

$rateRecord = [ordered]@{
    timestamp = '2026-07-13T08:00:00Z'
    type = 'event_msg'
    payload = [ordered]@{
        type = 'token_count'
        info = [ordered]@{
            last_token_usage = [ordered]@{ input_tokens=100; cached_input_tokens=60; output_tokens=20; reasoning_output_tokens=5; total_tokens=120 }
            total_token_usage = [ordered]@{ total_tokens=1000 }
            model_context_window = 1000
        }
        rate_limits = [ordered]@{
            primary = [ordered]@{ used_percent=14; window_minutes=300; resets_at=0 }
            secondary = [ordered]@{ used_percent=18; window_minutes=10080; resets_at=0 }
        }
    }
} | ConvertTo-Json -Compress -Depth 8
$rateSnapshot = Convert-HudRecord $rateRecord
if ($rateSnapshot.FiveHourRemainingPercent -ne 86 -or $rateSnapshot.WeeklyRemainingPercent -ne 82) { throw 'Remaining allowance parse self-test failed.' }
$allowanceOnlyRecord = $rateRecord | ConvertFrom-Json
$allowanceOnlyRecord.timestamp = '2026-07-13T08:01:00Z'
$allowanceOnlyRecord.payload.info.last_token_usage.input_tokens = 0
$allowanceOnlyRecord.payload.info.last_token_usage.output_tokens = 0
$allowanceOnlyRecord.payload.rate_limits.secondary.used_percent = 38
$allowanceOnlySnapshot = Convert-HudRecord ($allowanceOnlyRecord | ConvertTo-Json -Compress -Depth 8)
if ($allowanceOnlySnapshot.Kind -ne 'allowance' -or $allowanceOnlySnapshot.WeeklyRemainingPercent -ne 62) { throw 'Allowance-only maintenance snapshot self-test failed.' }
$olderUsage = $rateSnapshot.PSObject.Copy()
$newerUsage = $rateSnapshot.PSObject.Copy()
$olderUsage.Timestamp = [DateTimeOffset]::Parse('2026-07-13T08:02:00Z')
$olderUsage.AllowanceTimestamp = [DateTimeOffset]::Parse('2026-07-13T08:00:00Z')
$olderUsage.WeeklyRemainingPercent = 82
$newerUsage.Timestamp = [DateTimeOffset]::Parse('2026-07-13T08:01:00Z')
$newerUsage.AllowanceTimestamp = [DateTimeOffset]::Parse('2026-07-13T08:01:00Z')
$newerUsage.WeeklyRemainingPercent = 62
if ((Get-LatestHudAllowanceSnapshot @($olderUsage,$newerUsage)).WeeklyRemainingPercent -ne 62) { throw 'Newest account allowance selection self-test failed.' }
$rateConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
foreach ($field in $rateConfig.fields.PSObject.Properties) { $rateConfig.fields.($field.Name) = $false }
$rateConfig.fields.weeklyRemaining = $true
$rateMetrics = @(Get-HudMetrics $rateSnapshot $rateConfig $locale)
if (($rateMetrics | Where-Object Key -eq 'weeklyRemaining').Value -ne '82%') { throw 'Remaining allowance metric self-test failed.' }

$localeKeys = $null
foreach ($name in @('zh-CN','en','symbols')) {
    $currentKeys = @((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root ('locales\' + $name + '.json')) | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object)
    if ($null -eq $localeKeys) { $localeKeys = $currentKeys }
    elseif (Compare-Object $localeKeys $currentKeys) { throw "Locale key mismatch: $name" }
}

$themes = @(Get-HudThemes $root)
if ($themes.Count -lt 10) { throw 'Theme discovery self-test failed.' }
foreach ($theme in $themes) {
    if ($theme.settings.PSObject.Properties.Name -contains 'layout' -or $theme.settings.PSObject.Properties.Name -contains 'numberFormat') { throw "Theme '$($theme.id)' contains behavior settings." }
    foreach ($required in @('background','foreground','accent','border')) {
        if ($theme.settings.PSObject.Properties.Name -notcontains $required) { throw "Theme '$($theme.id)' is missing '$required'." }
        [void][Windows.Media.ColorConverter]::ConvertFromString([string]$theme.settings.$required)
    }
}
$defaultConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
foreach ($status in @('active','listening','idle','paused','error')) {
    [void][Windows.Media.ColorConverter]::ConvertFromString([string]$defaultConfig.statusColors.$status)
}
if ([bool]$defaultConfig.mousePassthrough) { throw 'Mouse click-through must default to disabled.' }
if ([string]$defaultConfig.statusPalette -ne 'default') { throw 'Default status palette marker is missing.' }
$mainText = Get-Content -Raw -Encoding UTF8 -LiteralPath $main
$mcpText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\mcp-server.mjs')
$settingsXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\SettingsWindow.xaml')
if ($mcpText -notmatch 'token_hud_disable_click_through' -or $mainText -notmatch 'passthrough-off\.signal') { throw 'Click-through recovery tool or signal is missing.' }
if ($mainText -notmatch 'System\.Windows\.Forms\.NotifyIcon' -or $mainText -notmatch 'Disable-HudMousePassthrough' -or $mainText -notmatch '\$trayZh\.disableMousePassthrough' -or $mainText -notmatch '\$trayIcon\.Text') { throw 'Localized click-through tray recovery entry is missing.' }
if ($settingsXaml -notmatch 'MousePassthroughCheck' -or $settingsXaml -notmatch 'TickFrequency="0\.1"') { throw 'Click-through setting or smooth font-size step is missing.' }
foreach ($palette in @('default','intuitive','colorblind','calm')) {
    if ($mainText -notmatch ("(?m)^\s*" + [regex]::Escape($palette) + "\s*=\s*\[ordered\]")) { throw "Status palette '$palette' is missing." }
}

$activeFiles = @(Get-ActiveHudSessionFiles (Join-Path $HOME '.codex\sessions') 60)
if ($activeFiles.Count -lt 1) { throw 'Active session discovery self-test failed.' }

Write-Output 'PowerShell syntax: OK'
Write-Output 'XAML syntax: OK'
Write-Output 'Live Codex log parse: OK'
Write-Output 'Token accounting: OK'
Write-Output 'Concurrent task aggregation: OK'
Write-Output 'Observed remaining allowance: OK (5h and weekly)'
Write-Output 'Immediate tail and allowance-only refresh: OK'
Write-Output 'Locale key parity: OK'
Write-Output ("Theme schema and colors: OK ({0} themes)" -f $themes.Count)
Write-Output 'Theme/layout independence: OK'
Write-Output 'Status palette: OK (5 states)'
Write-Output 'Mouse click-through defaults, tray and recovery: OK'
Write-Output ("Active session discovery: OK ({0} file(s))" -f $activeFiles.Count)
