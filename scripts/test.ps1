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

$activeFiles = @(Get-ActiveHudSessionFiles (Join-Path $HOME '.codex\sessions') 60)
if ($activeFiles.Count -lt 1) { throw 'Active session discovery self-test failed.' }

Write-Output 'PowerShell syntax: OK'
Write-Output 'XAML syntax: OK'
Write-Output 'Live Codex log parse: OK'
Write-Output 'Token accounting: OK'
Write-Output 'Concurrent task aggregation: OK'
Write-Output 'Observed remaining allowance: OK (5h and weekly)'
Write-Output 'Locale key parity: OK'
Write-Output ("Theme schema and colors: OK ({0} themes)" -f $themes.Count)
Write-Output 'Theme/layout independence: OK'
Write-Output 'Status palette: OK (5 states)'
Write-Output ("Active session discovery: OK ({0} file(s))" -f $activeFiles.Count)
