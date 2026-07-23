param(
    [string]$TestOutputRoot,
    [string]$NodePath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($TestOutputRoot)) {
    $TestOutputRoot = Join-Path $root '.test-output'
}
$TestOutputRoot = [IO.Path]::GetFullPath($TestOutputRoot)
if ([string]::IsNullOrWhiteSpace($NodePath)) {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($null -ne $nodeCommand) {
        $NodePath = $nodeCommand.Source
    } else {
        $bundledNode = Get-ChildItem -Path (Join-Path $HOME '.cache\codex-runtimes\*\dependencies\node\bin\node.exe') -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $bundledNode) { throw 'Node.js is required for the MCP regression test. Pass -NodePath when node is not on PATH.' }
        $NodePath = $bundledNode.FullName
    }
}
$main = Join-Path $root 'src\CodexMonitorHUD.ps1'
$core = Join-Path $root 'src\MonitorHud.Core.psm1'
$behaviorRuntimeTest = Join-Path $root 'scripts\test-behavior-isolated.ps1'
$installTransactionTest = Join-Path $root 'scripts\test-install-transaction.ps1'
$parsePaths = @($main,$core) + @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.ps1' | ForEach-Object FullName)

foreach ($path in $parsePaths) {
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
    if ($errors.Count) { throw ($errors | ForEach-Object { $_.ToString() } | Out-String) }
}

[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\HudWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\SettingsWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\ColorPickerWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\TaskBubbleWindow.xaml')) | Out-Null

$legacySelfTestRoot = Join-Path $TestOutputRoot 'legacy-self-test'
try {
    if (Test-Path -LiteralPath $legacySelfTestRoot) { Remove-Item -LiteralPath $legacySelfTestRoot -Recurse -Force }
    $legacySessionRoot = Join-Path $legacySelfTestRoot 'sessions\2026\07\18'
    New-Item -ItemType Directory -Force -Path $legacySessionRoot | Out-Null
    $legacyRecord = [ordered]@{
        timestamp = '2026-07-18T00:00:00Z'
        type = 'event_msg'
        payload = [ordered]@{
            type = 'token_count'
            info = [ordered]@{
                last_token_usage = [ordered]@{ input_tokens=100; cached_input_tokens=60; output_tokens=20; reasoning_output_tokens=5; total_tokens=120 }
                total_token_usage = [ordered]@{ total_tokens=1000 }
                model_context_window = 1000
            }
        }
    } | ConvertTo-Json -Compress -Depth 8
    [IO.File]::WriteAllText((Join-Path $legacySessionRoot 'synthetic-self-test.jsonl'), $legacyRecord, (New-Object Text.UTF8Encoding($false)))
    $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $main -SelfTest -SelfTestSessionsRoot (Join-Path $legacySelfTestRoot 'sessions') | ConvertFrom-Json
} finally {
    if (Test-Path -LiteralPath $legacySelfTestRoot) { Remove-Item -LiteralPath $legacySelfTestRoot -Recurse -Force }
}
if (-not $result.accounting_ok) { throw 'Token accounting self-test failed.' }
if (($result.cached + $result.uncached) -ne $result.input) { throw 'Input split self-test failed.' }
if (($result.input + $result.output) -ne $result.call_total) { throw 'Call total self-test failed.' }

Import-Module $core -Force
$contextThresholds = @(75,90,98)
if ((Get-HudContextAlertLevel 74.9 $contextThresholds) -ne 0 -or (Get-HudContextAlertLevel 75 $contextThresholds) -ne 1 -or (Get-HudContextAlertLevel 90 $contextThresholds) -ne 2 -or (Get-HudContextAlertLevel 98 $contextThresholds) -ne 3) { throw 'Three-stage context threshold self-test failed.' }
if ((@(Get-HudContextAlertThresholds @('98','75','90')) -join ',') -ne '75,90,98' -or (@(Get-HudContextAlertThresholds @('90','','')) -join ',') -ne '90' -or (@(Get-HudContextAlertThresholds @('96','76','96')) -join ',') -ne '76,96' -or $null -ne (Get-HudContextAlertThresholds @('0','',''))) { throw 'Editable context threshold normalization self-test failed.' }
if ((Get-HudTaskDeepLink '019f69dc-91bf-7c33-b47b-604b9eaa04b6') -ne 'codex://threads/019f69dc-91bf-7c33-b47b-604b9eaa04b6' -or $null -ne (Get-HudTaskDeepLink '../unsafe')) { throw 'Codex task deep-link validation self-test failed.' }
$darkEffect = Get-HudSurfaceEffectProfile -Background '#EE111827' -Foreground '#FFF8FAFC' -Surface solid -EffectColor '#FF0A84FF' -BaseOpacity 0.72 -BaseBlur 20
$lightEffect = Get-HudSurfaceEffectProfile -Background '#F4F8FAFC' -Foreground '#FF172033' -Surface solid -EffectColor '#FF0A84FF' -BaseOpacity 0.72 -BaseBlur 20
$gradientEffect = Get-HudSurfaceEffectProfile -Background '#FFFFFFFF' -Foreground '#FFF8FAFC' -Surface gradient -GradientStart '#FF101426' -GradientEnd '#FF222B45' -EffectColor '#FF7C3AED' -BaseOpacity 0.70 -BaseBlur 30
$imageEffect = Get-HudSurfaceEffectProfile -Background '#FFFFFFFF' -Foreground '#FFF8FAFC' -Surface image -EffectColor '#FF7C3AED' -BaseOpacity 0.70 -BaseBlur 30
if ($darkEffect.Tone -ne 'dark' -or $lightEffect.Tone -ne 'light' -or $gradientEffect.Tone -ne 'dark' -or $imageEffect.Tone -ne 'dark') { throw 'Dark/light theme surface classification self-test failed.' }
if ([double]$darkEffect.PeakOpacity -le [double]$lightEffect.PeakOpacity -or [double]$darkEffect.Blur -le [double]$lightEffect.Blur -or [string]$darkEffect.Color -eq [string]$lightEffect.Color) { throw 'Theme-adaptive effect compensation self-test failed.' }
if ([double]$darkEffect.PeakOpacity -gt 1.0 -or [double]$lightEffect.PeakOpacity -gt 0.92 -or [double]$darkEffect.Blur -gt 72.0) { throw 'Theme-adaptive effect bounds self-test failed.' }
$completeTail = Split-HudJsonLines '' '{"type":"event_msg","payload":{"type":"token_count"}}'
if ($completeTail.CompleteLines.Count -ne 1 -or -not [string]::IsNullOrEmpty([string]$completeTail.PendingText)) { throw 'Complete no-newline JSON tail self-test failed.' }
$partialTail = Split-HudJsonLines '' '{"type":"event_msg"'
if ($partialTail.CompleteLines.Count -ne 0 -or [string]::IsNullOrEmpty([string]$partialTail.PendingText)) { throw 'Partial JSON tail retention self-test failed.' }
$locale = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'locales\en.json') | ConvertFrom-Json
$contextRecord = [ordered]@{ type='turn_context'; payload=[ordered]@{ cwd='C:\Synthetic\pro-workspace'; model='gpt-test' } } | ConvertTo-Json -Compress
$contextSnapshot = Convert-HudRecord $contextRecord
if ($contextSnapshot.Kind -ne 'context' -or $contextSnapshot.Workspace -ne 'pro-workspace' -or $contextSnapshot.Model -ne 'gpt-test') { throw 'Privacy-safe task label parse self-test failed.' }
$completeRecord = [ordered]@{ timestamp=[DateTimeOffset]::Now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_complete'; turn_id='turn-visible'; last_agent_message='Done.' } } | ConvertTo-Json -Compress
$silentCompleteRecord = [ordered]@{ timestamp=[DateTimeOffset]::Now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_complete'; turn_id='turn-silent'; last_agent_message='' } } | ConvertTo-Json -Compress
$abortedRecord = [ordered]@{ timestamp=[DateTimeOffset]::Now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='turn_aborted' } } | ConvertTo-Json -Compress
if ((Convert-HudRecord $completeRecord).Kind -ne 'completed' -or (Convert-HudRecord $abortedRecord).Kind -ne 'aborted') { throw 'Explicit terminal-event parse self-test failed.' }
if ((Convert-HudRecord $silentCompleteRecord).Kind -ne 'completed_silent') { throw 'Silent turn completion must not trigger a user-facing completion reminder.' }
if ($null -ne (Convert-HudRecord '')) { throw 'Blank JSONL line must be ignored safely.' }
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
$pricingCatalog = Get-HudPricingCatalog $root (Join-Path $root 'pricing.default.json')
$costSnapshot = [pscustomobject]@{ Model='gpt-5.6-luna'; Input=100; Cached=50; Output=20; TaskInput=1000000; TaskCached=500000; TaskOutput=100000 }
$costEstimate = Get-HudCostEstimate $costSnapshot $pricingCatalog
if (-not $pricingCatalog.Loaded -or [Math]::Abs([double]$costEstimate.CostUsd - 1.15) -gt 0.000001 -or (Format-HudCost $costEstimate.CostUsd) -ne '~$1.15') { throw 'Local API-equivalent cost estimate self-test failed.' }
$costSnapshot | Add-Member -NotePropertyName EstimatedCostUsd -NotePropertyValue ([double]$costEstimate.CostUsd)
$costSnapshot | Add-Member -NotePropertyName Uncached -NotePropertyValue 50
$costSnapshot | Add-Member -NotePropertyName Reasoning -NotePropertyValue 0
$costSnapshot | Add-Member -NotePropertyName CallTotal -NotePropertyValue 120
$costSnapshot | Add-Member -NotePropertyName TaskTotal -NotePropertyValue 1100000
$costSnapshot | Add-Member -NotePropertyName ContextPercent -NotePropertyValue 10
$costSnapshot | Add-Member -NotePropertyName Timestamp -NotePropertyValue ([DateTimeOffset]::Now)
$costConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
foreach($field in $costConfig.fields.PSObject.Properties){$costConfig.fields.($field.Name)=$false};$costConfig.fields.estimatedCost=$true
if ((@(Get-HudMetrics $costSnapshot $costConfig $locale) | Select-Object -First 1).Value -ne '~$1.15') { throw 'HUD cost metric rendering self-test failed.' }
$unknownCost = Get-HudCostEstimate ([pscustomobject]@{Model='not-priced';Input=1;Cached=0;Output=1}) $pricingCatalog
if ($null -ne $unknownCost) { throw 'Unpriced models must not produce a guessed cost.' }

$localeKeys = $null
foreach ($name in @('zh-CN','en','symbols')) {
    $currentKeys = @((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root ('locales\' + $name + '.json')) | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object)
    if ($null -eq $localeKeys) { $localeKeys = $currentKeys }
    elseif (Compare-Object $localeKeys $currentKeys) { throw "Locale key mismatch: $name" }
}

$themes = @(Get-HudThemes $root)
if ($themes.Count -lt 10) { throw 'Theme discovery self-test failed.' }
foreach ($theme in $themes) {
    $allowedThemeSettings = @('background','foreground','muted','accent','border','cornerRadius','opacity','fontSize','layout','separator','transparencyMode','showStatusDot','animateUpdates','themeStyle','multiTask','attention','agentNotification','statusColors')
    foreach ($property in $theme.settings.PSObject.Properties.Name) { if ($allowedThemeSettings -notcontains $property) { throw "Theme '$($theme.id)' contains unsupported setting '$property'." } }
    if ($null -ne $theme.settings.PSObject.Properties['attention']) {
        foreach ($property in $theme.settings.attention.PSObject.Properties.Name) { if (@('summaryMode','listMode','taskBubbleMode','dotEnabled','dotPattern','dotBrightness','dotSpeed','dotBreathing') -notcontains $property) { throw "Theme '$($theme.id)' attempts to change reminder trigger behavior." } }
    }
    if ($null -ne $theme.settings.PSObject.Properties['agentNotification']) {
        foreach ($property in $theme.settings.agentNotification.PSObject.Properties.Name) { if (@('mode','color','glowPreset','intensity') -notcontains $property) { throw "Theme '$($theme.id)' attempts to change agent-notification permission or trigger behavior." } }
    }
    foreach ($required in @('background','foreground','accent','border')) {
        if ($theme.settings.PSObject.Properties.Name -notcontains $required) { throw "Theme '$($theme.id)' is missing '$required'." }
        [void][Windows.Media.ColorConverter]::ConvertFromString([string]$theme.settings.$required)
    }
}
$defaultConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
foreach ($status in @('active','listening','idle','paused','error','completed','aborted')) {
    [void][Windows.Media.ColorConverter]::ConvertFromString([string]$defaultConfig.statusColors.$status)
}
if ([bool]$defaultConfig.mousePassthrough) { throw 'Mouse click-through must default to disabled.' }
if ([string]$defaultConfig.statusPalette -ne 'default') { throw 'Default status palette marker is missing.' }
if ([string]$defaultConfig.monitorScope -ne 'aggregate' -or [string]$defaultConfig.multiTask.displayMode -ne 'summary') { throw 'Lightweight summary defaults are missing.' }
if ([int]$defaultConfig.multiTask.maxSplitBubbles -ne 6 -or [string]$defaultConfig.multiTask.nameMode -ne 'hover') { throw 'Multi-task guardrail defaults are missing.' }
if ([string]$defaultConfig.multiTask.listStyle -ne 'rows' -or [string]$defaultConfig.multiTask.listDensity -ne 'compact' -or [string]$defaultConfig.attention.summaryMode -ne 'halo' -or [string]$defaultConfig.attention.listMode -ne 'flow' -or [string]$defaultConfig.attention.taskBubbleMode -ne 'flow' -or [string]$defaultConfig.transparencyMode -ne 'uniform') { throw 'List density, per-surface attention or transparency defaults are missing.' }
if (-not [bool]$defaultConfig.attention.dotEnabled -or -not [bool]$defaultConfig.attention.dotBreathing -or [string]$defaultConfig.attention.dotPattern -ne 'heartbeat' -or [string]$defaultConfig.attention.dotBrightness -ne 'balanced') { throw 'Independent status-dot reminder defaults are missing.' }
if ([bool]$defaultConfig.attention.onSettled -or [int]$defaultConfig.attention.completionGraceSeconds -ne 8) { throw 'Low-false-positive reminder defaults are missing.' }
if ([int]$defaultConfig.statusTiming.terminalHoldSeconds -ne 120 -or [string]$defaultConfig.statusTiming.terminalExitMode -ne 'gentle') { throw 'Completed-task retention must default to two minutes with the gentle departure cue.' }
if ([string]$defaultConfig.themeStyle.surface -ne 'solid' -or [string]$defaultConfig.themeStyle.shadow -ne 'soft' -or [double]$defaultConfig.themeStyle.statusDotSize -ne 8.0) { throw 'Rich theme-style defaults are missing.' }
if ([bool]$defaultConfig.fields.estimatedCost -or [bool]$defaultConfig.multiTask.listFields.estimatedCost -or [bool]$defaultConfig.multiTask.bubbleFields.estimatedCost) { throw 'API-equivalent cost must remain opt-in on every surface.' }
if ([bool]$defaultConfig.agentNotifications.enabled -or [string]$defaultConfig.agentNotifications.permission -ne 'text') { throw 'Codex proactive notifications must remain opt-in with text-only permission by default.' }
if (@('violet','aqua','amber','custom') -notcontains [string]$defaultConfig.agentNotifications.glowPreset -or [string]$defaultConfig.agentNotifications.color -notmatch '^#[0-9A-Fa-f]{8}$') { throw 'Codex notification glow preset or color default is invalid.' }
if ([string]$defaultConfig.multiTask.listDetail -ne 'balanced' -or -not [bool]$defaultConfig.multiTask.bubbleFields.taskTotal) { throw 'List detail or task-bubble field defaults are invalid.' }
if ([string]$defaultConfig.language -ne 'en' -or [bool]$defaultConfig.behavior.openTaskOnDoubleClick -or [bool]$defaultConfig.behavior.idleIndicator.enabled -or [bool]$defaultConfig.behavior.contextAlerts.enabled -or [bool]$defaultConfig.fields.context) { throw 'Prompt-language fallback or dependent lightweight behavior defaults are invalid.' }
if ([string]$defaultConfig.behavior.idleIndicator.layout -ne 'overall' -or [string]$defaultConfig.behavior.idleIndicator.taskStyle -ne 'dot') { throw 'Backward-compatible quiet-indicator layout defaults are invalid.' }
if ((@($defaultConfig.behavior.contextAlerts.thresholds) -join ',') -ne '75,90,98') { throw 'Default context alert thresholds are invalid.' }
$mainText = Get-Content -Raw -Encoding UTF8 -LiteralPath $main
$mcpText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\mcp-server.mjs')
$settingsXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\SettingsWindow.xaml')
$installText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'scripts\install.ps1')
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root '.codex-plugin\plugin.json') | ConvertFrom-Json
if ([string]$manifest.version -ne '2.2.0' -or $mcpText -notmatch 'version: "2\.2\.0"' -or [string]$manifest.version -match 'preview') { throw 'Stable v2.2.0 manifest and MCP version are not aligned.' }
$installManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'install-manifest.json') | ConvertFrom-Json
if ([string]$installManifest.version -ne '2.2.0' -or [string]$installManifest.releaseTag -ne 'v2.2.0' -or -not [bool]$installManifest.rules.preferVerifiedRelease -or -not [bool]$installManifest.rules.preserveSettings -or -not [bool]$installManifest.rules.retainRollback -or $null -ne $installManifest.platforms.'macos-arm64') { throw 'Deterministic Windows v2.2.0 repository-install manifest is invalid.' }
$dotnetRequired = @(
    'CodexMonitorHud.slnx',
    'src-dotnet/CodexMonitorHud.Core/CodexMonitorHud.Core.csproj',
    'src-dotnet/CodexMonitorHud.App/CodexMonitorHud.App.csproj',
    'src-dotnet/CodexMonitorHud.Core/State/SessionMonitorEngine.cs',
    'src-dotnet/CodexMonitorHud.App/HudApplicationController.cs',
    'src-dotnet/CodexMonitorHud.App/HudAnimations.cs',
    'tests-dotnet/CodexMonitorHud.Core.Tests/CodexMonitorHud.Core.Tests.csproj',
    'scripts/build-dotnet.ps1',
    'scripts/test-dotnet.ps1',
    'scripts/compare-runtime-performance.ps1'
)
foreach ($relativePath in $dotnetRequired) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath))) { throw "v2.2.0 compiled architecture file is missing: $relativePath" }
}
$coreProjectText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src-dotnet\CodexMonitorHud.Core\CodexMonitorHud.Core.csproj')
$coreSourceText = (Get-ChildItem -LiteralPath (Join-Path $root 'src-dotnet\CodexMonitorHud.Core') -Recurse -Filter *.cs | ForEach-Object { Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName }) -join "`n"
$appSourceText = (Get-ChildItem -LiteralPath (Join-Path $root 'src-dotnet\CodexMonitorHud.App') -Filter *.cs | ForEach-Object { Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName }) -join "`n"
$compiledSourceText = $coreSourceText + "`n" + $appSourceText
if ($coreProjectText -match 'net10\.0-windows' -or $coreSourceText -match 'System\.Windows|user32\.dll|WindowsBase') { throw 'Platform-neutral Core acquired a Windows-only dependency.' }
$programText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src-dotnet\CodexMonitorHud.App\Program.cs')
$healthLiteral = [regex]::Match($programText, 'HudRecordParser\.Parse\("(?<json>\{.*?\})"\);')
if (-not $healthLiteral.Success) { throw 'Compiled health-check parser fixture is missing.' }
try { $null = ([regex]::Unescape($healthLiteral.Groups['json'].Value) | ConvertFrom-Json) }
catch { throw 'Compiled health-check parser fixture is invalid JSON.' }
$appLocaleKeys = @([regex]::Matches($appSourceText, '(?<![\.\w])Get\([^,]+,\s*"([^"]+)"\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
foreach ($localePath in @('locales\en.json','locales\zh-CN.json','locales\symbols.json')) {
    $localeObject = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $localePath) | ConvertFrom-Json
    foreach ($key in $appLocaleKeys) {
        if ($null -eq $localeObject.PSObject.Properties[$key]) { throw "Compiled HUD locale key '$key' is missing from $localePath." }
    }
}
foreach ($xamlPath in @('src\HudWindow.xaml','src\TaskBubbleWindow.xaml')) {
    $xamlText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $xamlPath)
    $controlNames = @([regex]::Matches($xamlText, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    foreach ($name in $controlNames) {
        if ($name -in @('HudWindow','TaskBubbleWindow','IconChrome','ToggleChrome','TaskBubbleNumberBadge')) { continue }
        if ($appSourceText -notmatch ('"' + [regex]::Escape($name) + '"')) { throw "Compiled HUD does not bind required XAML control '$name' from $xamlPath." }
    }
}
$compiledControlTypes = @{}
foreach ($xamlPath in @('src\HudWindow.xaml','src\TaskBubbleWindow.xaml')) {
    [xml]$compiledXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $xamlPath)
    $namespaceManager = New-Object Xml.XmlNamespaceManager($compiledXaml.NameTable)
    $namespaceManager.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
    foreach ($node in $compiledXaml.SelectNodes('//*[@x:Name]',$namespaceManager)) {
        $name = $node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml')
        $compiledControlTypes[$name] = $node.LocalName
    }
}
foreach ($binding in [regex]::Matches($appSourceText, 'Require<(?<type>\w+)>\(Window,\s*"(?<name>[^"]+)"\)')) {
    $name = $binding.Groups['name'].Value
    $type = $binding.Groups['type'].Value
    if (-not $compiledControlTypes.ContainsKey($name) -or [string]$compiledControlTypes[$name] -ne $type) {
        throw "Compiled HUD XAML binding '$name' does not match required control type '$type'."
    }
}
$startText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'scripts\start.ps1')
if ($startText -notmatch 'runtime\\win-x64' -or $startText -notmatch 'CodexMonitorHud\.dll' -or $startText -notmatch 'CodexMonitorHUD\.ps1' -or $startText -notmatch '\$compiledStarted') { throw 'Compiled-first startup with legacy rollback is not intact.' }
foreach ($required in @('eventArgs.Handled = true','TimeSpan.FromMilliseconds(1500)','PollBacklog','HasTitleBacklog','GlobalReadBudgetBytes','SessionChangeTracker(Path.GetDirectoryName(_sessionIndexPath)','ChangeAvailable += QueueWake','DecodePixelWidth = 1920','_surfaceCache','_appearanceSignature != appearanceSignature','ResetSummaryAttentionVisual','ResetAttention','Agent notice accepted for task #')) {
    if ($compiledSourceText -notmatch [regex]::Escape($required)) { throw "Compiled stability or adaptive-runtime path '$required' is missing." }
}
foreach ($required in @('hudHeartbeatIsFresh','hudRestartAttempts.length >= 3','5 * 60 * 1000','setInterval(maintainHud, 5000)')) {
    if ($mcpText -notmatch [regex]::Escape($required)) { throw "Bounded MCP HUD restart path '$required' is missing." }
}
if ($mcpText -notmatch 'monitor_hud_disable_click_through' -or $mainText -notmatch 'passthrough-off\.signal') { throw 'Click-through recovery tool or signal is missing.' }
if ($mainText -notmatch 'System\.Windows\.Forms\.NotifyIcon' -or $mainText -notmatch 'Disable-HudMousePassthrough' -or $mainText -notmatch '\$trayZh\.disableMousePassthrough' -or $mainText -notmatch '\$trayIcon\.Text') { throw 'Localized click-through tray recovery entry is missing.' }
if ($settingsXaml -notmatch 'MousePassthroughCheck' -or $settingsXaml -notmatch 'TickFrequency="0\.1"' -or $settingsXaml -notmatch 'OpacitySlider[^>]+Minimum="0\.15"') { throw 'Click-through setting or low/smooth opacity controls are missing.' }
if ($settingsXaml -notmatch 'TaskRetentionCombo' -or $settingsXaml -notmatch 'Retention1800Item' -or $settingsXaml -notmatch 'TerminalExitModeCombo' -or $settingsXaml -notmatch 'TerminalExitBeaconItem' -or $mainText -match 'TerminalSilent.*return \$false' -or $mainText -notmatch 'Start-HudTerminalExitAnimation' -or $mainText -notmatch 'Update-TerminalExitState' -or $mainText -notmatch 'Get-HudSessionIdentity[\s\S]{0,2400}-TotalCount 64' -or $mainText -notmatch 'record\.payload\.cwd' -or $mainText -notmatch 'Set-HudSessionIdentityFromRecord' -or $mainText -notmatch 'IdentityMetadataFound' -or (Get-Content -Raw -Encoding UTF8 -LiteralPath $core) -notmatch "@\('fade','gentle','focus','beacon'\)") { throw 'Completed-task retention/departure, workspace identity, or late-metadata filter is missing.' }
foreach ($localOnlyName in @('private','AGENTS.md','WORKSPACE_STATE.md')) {
    if ($installText -notmatch [regex]::Escape("'$localOnlyName'")) { throw "Installer must exclude local-only '$localOnlyName' material." }
}
foreach ($localOnlyName in @('.agents','.codex','node_modules','sessions','logs','archive')) {
    if ($installText -notmatch [regex]::Escape("'$localOnlyName'")) { throw "Installer must exclude local-only '$localOnlyName' material." }
}
foreach ($localOnlyPath in @('docs/MAINTENANCE_WORKFLOW.md','docs/MACOS_PREVIEW_TESTING.md','scripts/prepare-delivery.ps1')) {
    if ($installText -notmatch [regex]::Escape("'$localOnlyPath'")) { throw "Installer must exclude local-only '$localOnlyPath' material." }
}
if ($installText -notmatch '\$excludedRootNames' -or $installText -notmatch '\$excludedRelativePaths') { throw 'Installer exclusion boundary is missing.' }
$releaseText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'scripts\prepare-release.ps1')
foreach ($required in @("[string]`$Version = '2.2.0'",'$excludedDirectoryNames',"'.agents'","'.codex'","'bin'","'obj'",'$excludedRelativePaths')) {
    if ($releaseText -notmatch [regex]::Escape($required)) { throw "Release-package exclusion or 2.2.0 default '$required' is missing." }
}
if ([string]$installManifest.platforms.'windows-x64'.asset -ne 'CodexMonitorHUD-windows-x64.zip' -or $releaseText -notmatch [regex]::Escape("'CodexMonitorHUD-windows-x64.zip'")) { throw 'Release asset name and Windows install manifest are not aligned.' }
if ($installText -notmatch 'DefaultLanguage' -or $installText -notmatch 'Test-Path -LiteralPath \$settingsPath') { throw 'First-install prompt-language selection or upgrade-preservation guard is missing.' }
foreach ($required in @('RollbackVersion','Switch-InstalledTree','.codex-monitor-hud-stage-','.codex-monitor-hud-rollback-','compare-runtime-performance.ps1')) {
    if ($installText -notmatch [regex]::Escape($required)) { throw "Transactional install or rollback path '$required' is missing." }
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installTransactionTest -TestOutputRoot $TestOutputRoot
if ($LASTEXITCODE -ne 0) { throw 'Transactional install rollback self-test failed.' }
foreach ($required in @('ThemeWorkshopDropZone','ThemeImportButton','AttentionHelp','ToolTipService.InitialShowDelay')) { if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Polished settings affordance '$required' is missing." } }
foreach ($required in @('MultiTaskTab','DisplayModeCombo','ListStyleCombo','ListDensityCombo','ListDetailCombo','TaskNameModeCombo','MaxSplitCombo','AutoSplitCheck','BubbleFieldModel','PositionCustomItem','SummaryAttentionModeCombo','ListAttentionModeCombo','TaskBubbleAttentionModeCombo','SummaryAttentionFlowItem','SummaryAttentionFocusItem','DotAttentionEnabledCheck','DotPatternCombo','DotBrightnessCombo','DotSpeedCombo','DotBreathingCheck','TransparencyModeCombo')) {
    if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Multi-task setting '$required' is missing." }
}
foreach ($required in @('FieldEstimatedCost','BubbleFieldEstimatedCost','PricingPathText','PricingStatusText')) { if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Cost-estimate setting '$required' is missing." } }
foreach ($required in @('AgentNotificationEnabledCheck','AgentNotificationPermissionCombo','AgentNotificationModeCombo','AgentNotificationGlowPresetCombo','AgentNotificationIntensityCombo','AgentNotificationDurationCombo','AgentNotificationColorText')) { if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Codex notification setting '$required' is missing." } }
foreach ($required in @('BehaviorTab','OpenTaskOnDoubleClickCheck','IdleIndicatorEnabledCheck','IdleIndicatorDelayCombo','IdleIndicatorLayoutCombo','IdleIndicatorTaskStyleCombo','IdleIndicatorBubblesCheck','ContextMetricVisibleCheck','ContextAlertsEnabledCheck','ContextThreshold1Text','ContextThreshold2Text','ContextThreshold3Text')) { if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Behavior setting '$required' is missing." } }
foreach ($required in @('Open-HudTaskInCodex','Get-HudTaskDeepLink','Get-HudContextAlertThresholds','Get-HudContextAlertVisualSpec','Start-HudContextAlertAnimation','Stop-HudContextAlertAnimation','Reset-HudContextAlertRuntime','Update-HudIdleIndicatorMode','Set-TaskBubbleIndicatorCollapsed','Update-HudContextAlertState','ContextAlertLevel')) { if ($mainText -notmatch [regex]::Escape($required) -and (Get-Content -Raw -Encoding UTF8 -LiteralPath $core) -notmatch [regex]::Escape($required)) { throw "Behavior runtime path '$required' is missing." } }
foreach ($required in @('monitor_hud_notify','boundedAnimation','notificationPermission','notificationsRoot','maxLength: 160','permission === "expressive"')) { if ($mcpText -notmatch [regex]::Escape($required)) { throw "Bounded Codex notification MCP path '$required' is missing." } }
foreach ($required in @('Process-HudAgentNotifications','Start-HudAgentAnimation','AgentNoticeText','AgentNoticeRecipe','agentNotificationBadge','AttentionReason -eq ''agent''')) { if ($mainText -notmatch [regex]::Escape($required)) { throw "Targeted Codex notification runtime path '$required' is missing." } }
foreach ($required in @('Show-TaskBubble','Render-TaskList','Get-TaskListDensityMetrics','Get-TaskListMetricsText','Split-AllTaskBubbles','Merge-AllTaskBubbles','TaskBubbleResizeThumb','trayViewModeItem')) {
    if ($mainText -notmatch [regex]::Escape($required)) { throw "Multi-task runtime path '$required' is missing." }
}
if ($mainText -notmatch '\$taskCount -gt 0' -or $mainText -notmatch 'PreviewListDensity') { throw 'Persistent list toggle or density preview path is missing.' }
foreach ($required in @('Get-TaskListSubtitle','$identityHost.Children.Add($name)','$identityHost.Children.Add($subtitle)')) { if ($mainText -notmatch [regex]::Escape($required)) { throw "List item title/subtitle hierarchy '$required' is missing." } }
foreach ($required in @('Get-RuntimeHudLocale','lastContextMenuSignature','if (-not $changed) {','previousSignature','FileInfo = $File','[IO.File]::Exists($openSignal)','Render-HudMetrics','lastHudAppearanceSignature','hudMetricControls','lastTaskListRenderSignature','SettingsHost','reload-settings.signal','Invoke-HudIdleMemoryTrim','SetProcessWorkingSetSize')) { if ($mainText -notmatch [regex]::Escape($required)) { throw "Idle-render or locale-cache optimization '$required' is missing." } }
if ([regex]::Matches($mainText, '\[IO\.File\]::WriteAllText\(\$reloadSettingsSignal').Count -lt 2) { throw 'Settings-host live preview no longer notifies the compiled HUD before the window closes.' }
if ($compiledSourceText -notmatch [regex]::Escape('!state.IdentityMetadataFound || state.IsInternalSession || state.Dismissed')) { throw 'Confirmed user sessions without an initial token snapshot are no longer visible as waiting tasks.' }
$coreText = Get-Content -Raw -Encoding UTF8 -LiteralPath $core
foreach ($required in @('[Collections.Generic.Queue[string]]::new()','isRelevantEvent','trimmedCandidate.EndsWith')) { if ($coreText -notmatch [regex]::Escape($required)) { throw "Streaming session filter '$required' is missing." } }
if ($mainText -notmatch 'lastUpdateAnimationSignature' -or $mainText -notmatch 'Update animation:' -or $mainText -match 'DoubleAnimation\(0\.58, 1\.0') { throw 'Event-bound non-flashing update animation guard is missing.' }
$hudXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\HudWindow.xaml')
if ($hudXaml -notmatch 'TaskListScroller[^>]+MinWidth="900"') { throw 'Task-list minimum width guard is missing; the right-side count toggle can be clipped by a fully populated metric row.' }
$bubbleXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\TaskBubbleWindow.xaml')
if ($hudXaml -notmatch 'HudListToggleButton' -or $bubbleXaml -notmatch 'TaskBubbleResizeThumb') { throw 'Custom list toggle or task-bubble resize affordance is missing.' }
foreach ($required in @('QuietIndicatorPanel','QuietOverallDot','QuietOverallRing','QuietIndicatorSeparator','QuietTaskIndicators')) { if ($hudXaml -notmatch [regex]::Escape($required)) { throw "Quiet task-light surface '$required' is missing." } }
foreach ($required in @('StatusPaletteCodexMicro','StatusPaletteCodexMicroSource','#FF9CD5FE','#FFFFD0B8','#FFFF7373','#FF9BF396','PreviewQuietLayout','PreviewQuietTaskStyle','Quiet task indicators:')) { if ($settingsXaml -notmatch [regex]::Escape($required) -and $mainText -notmatch [regex]::Escape($required)) { throw "Codex Micro palette or quiet-preview path '$required' is missing." } }
foreach ($windowXaml in @($hudXaml,$bubbleXaml,$settingsXaml)) {
    foreach ($required in @('UseLayoutRounding="True"','SnapsToDevicePixels="True"','TextOptions.TextFormattingMode="Display"','TextOptions.TextRenderingMode="ClearType"')) {
        if ($windowXaml -notmatch [regex]::Escape($required)) { throw "High-DPI text rendering option '$required' is missing." }
    }
}
if ($hudXaml -match 'DropShadowEffect' -or $bubbleXaml -match 'DropShadowEffect' -or $mainText -notmatch 'SetProcessDpiAwarenessContext') { throw 'Persistent HUD shadow removal or per-monitor DPI awareness is missing.' }
foreach ($required in @('TaskBubbleDismissButton','Dismiss-HudTask','Dismissed = $false','state.Dismissed = $false','session_index.jsonl','thread_name','Refresh-HudSessionIndex')) { if ($bubbleXaml -notmatch [regex]::Escape($required) -and $mainText -notmatch [regex]::Escape($required)) { throw "Task dismissal or official thread-title path '$required' is missing." } }
if ($bubbleXaml -notmatch 'TaskBubbleContextMetric' -or $mainText -notmatch 'Start-HudContextAlertAnimation \$contextMetricContainer' -or $mainText -notmatch 'Start-HudContextAlertAnimation \$entry\.ContextMetric' -or $mainText -notmatch 'contextAlerts\.enabled = \[bool\]\$contextAlertsEnabledCheck\.IsChecked -and \[bool\]\$config\.fields\.context') { throw 'Context-metric-only alert routing or display dependency is missing.' }
foreach ($localeFile in @('locales\zh-CN.json','locales\en.json','locales\symbols.json')) { if ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $localeFile)) -notmatch 'noActiveTasks') { throw "Deleted/no-active task copy is missing from '$localeFile'." } }
$shortcutText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'scripts\create-shortcuts.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $root 'assets\codex-monitor-hud.ico')) -or $mainText -notmatch 'SetCurrentProcessExplicitAppUserModelID' -or $mainText -notmatch 'SendMessage\(' -or $mainText -notmatch 'Set-HudWindowIcon' -or $shortcutText -notmatch 'IconLocation' -or $shortcutText -notmatch 'safeVersion' -or $shortcutText -notmatch 'ie4uinit') { throw 'Native taskbar and cache-busted shortcut icon path is missing.' }

$migrationRoot = Join-Path $TestOutputRoot 'config-migration'
try {
    if (Test-Path -LiteralPath $migrationRoot) { Remove-Item -LiteralPath $migrationRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $migrationRoot | Out-Null
    $legacySettingsPath = Join-Path $migrationRoot 'settings.json'
    [ordered]@{ fields=[ordered]@{context=$false}; behavior=[ordered]@{contextAlerts=[ordered]@{enabled=$true;thresholds=@(75,90,98)}}; multiTask=[ordered]@{ taskFields=[ordered]@{ model=$false; callTotal=$true; taskTotal=$false; updated=$false }; listDensity='invalid' }; statusTiming=[ordered]@{ terminalExitMode='invalid' } } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $legacySettingsPath -Encoding UTF8
    $migrationPaths = [pscustomobject]@{ DefaultConfigPath=(Join-Path $root 'config.default.json'); ConfigPath=$legacySettingsPath }
    $migratedConfig = Get-HudConfig $migrationPaths
    if ([string]$migratedConfig.multiTask.listDensity -ne 'compact' -or [bool]$migratedConfig.multiTask.bubbleFields.model -or -not [bool]$migratedConfig.multiTask.bubbleFields.callTotal) { throw 'Legacy task-field or list-density migration self-test failed.' }
    if (-not [bool]$migratedConfig.multiTask.listFields.model -or [bool]$migratedConfig.multiTask.listFields.taskTotal) { throw 'Legacy settings unexpectedly replaced compact list-field defaults.' }
    if ([string]$migratedConfig.statusTiming.terminalExitMode -ne 'gentle') { throw 'Invalid legacy terminal-exit mode did not migrate to the gentle default.' }
    if ([bool]$migratedConfig.behavior.contextAlerts.enabled) { throw 'Context alerts must normalize off when the context metric is hidden.' }
} finally {
    if (Test-Path -LiteralPath $migrationRoot) { Remove-Item -LiteralPath $migrationRoot -Recurse -Force }
}
foreach ($surfaceMode in @('summaryMode','listMode','taskBubbleMode')) {
    if ($mainText -notmatch ('Start-HudAttentionAnimation[^\r\n]+config\.attention\.' + $surfaceMode)) { throw "Per-surface reminder path '$surfaceMode' is missing." }
}
foreach ($required in @('completed_silent','PendingCompletionTurnId','completionGraceSeconds','LastListAttentionRevision','config.multiTask.displayMode -eq ''summary''')) { if ($mainText -notmatch [regex]::Escape($required) -and $required -ne 'completed_silent') { throw "Low-false-positive or per-surface routing path '$required' is missing." } }
if ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\MonitorHud.Core.psm1')) -notmatch 'completed_silent') { throw 'Silent completion filtering is missing.' }
foreach ($path in @('docs\AI_PORTING_AND_CUSTOMIZATION_GUIDE.md','skills\create-monitor-hud-theme\SKILL.md','skills\create-monitor-hud-theme\references\theme-format.md')) { if (-not (Test-Path -LiteralPath (Join-Path $root $path))) { throw "Customization artifact '$path' is missing." } }
if (-not (Test-Path -LiteralPath (Join-Path $root 'scripts\test-terminal-exit-isolated.ps1')) -or -not (Test-Path -LiteralPath $behaviorRuntimeTest)) { throw 'Terminal departure or behavior runtime regression is missing.' }
foreach ($required in @('Import-HudThemeFile','Assert-HudThemeDefinition','\.cmhud-theme','System\.IO\.Compression','New-HudSurfaceBrush')) { if ($mainText -notmatch $required) { throw "Theme workshop runtime path '$required' is missing." } }
foreach ($required in @('Start-HudDotAttentionAnimation','Start-HudSurfaceAttentionAnimation','dotEnabled','dotBreathing','dotBrightness','dotPattern','dotSpeed')) {
    if ($mainText -notmatch [regex]::Escape($required)) { throw "Stackable attention path '$required' is missing." }
}
foreach ($required in @('Get-HudEffectProfile','Get-HudSurfaceEffectProfile','profile.PeakOpacity','profile.FlowCore','profile.FlowShoulderAlpha')) {
    if ($mainText -notmatch [regex]::Escape($required) -and (Get-Content -Raw -Encoding UTF8 -LiteralPath $core) -notmatch [regex]::Escape($required)) { throw "Theme-adaptive notification effect path '$required' is missing." }
}
foreach ($mode in @('halo','breathe','flow','focus')) {
    if ($mainText -notmatch [regex]::Escape("'$mode'")) { throw "Surface attention mode '$mode' is missing." }
}

$mcpTestRoot = Join-Path $TestOutputRoot 'mcp-notice'
$previousLocalAppData = $env:LOCALAPPDATA
$previousDisableAutoStart = $env:CODEX_MONITOR_HUD_DISABLE_AUTO_START
try {
    if (Test-Path -LiteralPath $mcpTestRoot) { Remove-Item -LiteralPath $mcpTestRoot -Recurse -Force }
    $mcpStateRoot = Join-Path $mcpTestRoot 'CodexMonitorHUD'
    New-Item -ItemType Directory -Force -Path $mcpStateRoot | Out-Null
    $mcpSettings = $defaultConfig.PSObject.Copy()
    $mcpSettings.agentNotifications.enabled = $true
    $mcpSettings.agentNotifications.permission = 'expressive'
    $mcpSettings | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $mcpStateRoot 'settings.json')
    [ordered]@{version=1;tasks=@([ordered]@{task_number=7;workspace='synthetic-workspace';status='active';updated_at='2026-07-15T12:00:00Z'})} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $mcpStateRoot 'task-registry.json')
    $env:LOCALAPPDATA = $mcpTestRoot
    $env:CODEX_MONITOR_HUD_DISABLE_AUTO_START = '1'
    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = $NodePath
    $processInfo.Arguments = ('"{0}"' -f (Join-Path $root 'src\mcp-server.mjs'))
    $processInfo.WorkingDirectory = $root
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $processInfo
    [void]$process.Start()
    $capabilityRequest = [ordered]@{jsonrpc='2.0';id=1;method='tools/call';params=[ordered]@{name='monitor_hud_notification_capabilities';arguments=[ordered]@{}}} | ConvertTo-Json -Compress -Depth 8
    $noticeRequest = [ordered]@{jsonrpc='2.0';id=2;method='tools/call';params=[ordered]@{name='monitor_hud_notify';arguments=[ordered]@{message=('x'*180);task_number=7;animation=[ordered]@{layers=@('glow','pulse','breathe','flow','invalid');intensity=99;tempo_ms=1;cycles=99;glow_radius=99;scale=2;direction='right-to-left'}}}} | ConvertTo-Json -Compress -Depth 10
    $process.StandardInput.WriteLine($capabilityRequest)
    $process.StandardInput.WriteLine($noticeRequest)
    $process.StandardInput.Close()
    $mcpOutput = $process.StandardOutput.ReadToEnd()
    $mcpError = $process.StandardError.ReadToEnd()
    $process.WaitForExit(10000) | Out-Null
    if ($process.ExitCode -ne 0) { throw ('MCP notice process failed: ' + $mcpError) }
    $responses = @($mcpOutput -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($responses.Count -ne 2 -or [string]$responses[0].result.content[0].text -notmatch '"permission": "expressive"' -or [string]$responses[0].result.content[0].text -notmatch 'synthetic-workspace') { throw ('Per-task notification capability discovery self-test failed: ' + $mcpOutput) }
    $noticeFile = Get-ChildItem -LiteralPath (Join-Path $mcpStateRoot 'notifications') -File -Filter '*.json' | Select-Object -First 1
    $queuedNotice = Get-Content -Raw -Encoding UTF8 -LiteralPath $noticeFile.FullName | ConvertFrom-Json
    if ([string]$queuedNotice.message.Length -ne '160' -or [int]$queuedNotice.task_number -ne 7 -or [double]$queuedNotice.animation.intensity -ne 1 -or [int]$queuedNotice.animation.cycles -ne 8 -or @($queuedNotice.animation.layers).Count -ne 4) { throw 'Bounded expressive notification payload self-test failed.' }
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:CODEX_MONITOR_HUD_DISABLE_AUTO_START = $previousDisableAutoStart
    if (Test-Path -LiteralPath $mcpTestRoot) { Remove-Item -LiteralPath $mcpTestRoot -Recurse -Force }
}
if ($mainText -match '[\u4e00-\u9fff]') { throw 'PowerShell source contains hard-coded CJK text; tray/runtime labels must come from UTF-8 locale JSON.' }
foreach ($palette in @('default','intuitive','colorblind','calm')) {
    if ($mainText -notmatch ("(?m)^\s*" + [regex]::Escape($palette) + "\s*=\s*\[ordered\]")) { throw "Status palette '$palette' is missing." }
}

$pool = New-HudTaskNumberPool 512
$activeNumbers = @{}
$clock = [DateTimeOffset]::Parse('2026-07-14T00:00:00Z')
for ($index = 0; $index -lt 64; $index++) {
    $number = Get-HudTaskNumber $pool $clock
    if ($activeNumbers.ContainsKey($number)) { throw 'Duplicate task number during initial allocation.' }
    $activeNumbers[$number] = $true
}
for ($cycle = 0; $cycle -lt 10000; $cycle++) {
    $clock = $clock.AddMilliseconds(40)
    $released = [int](@($activeNumbers.Keys | Sort-Object)[($cycle % 64)])
    $activeNumbers.Remove($released)
    Add-HudReleasedTaskNumber $pool $released 120 $clock
    $replacement = Get-HudTaskNumber $pool $clock
    if ($activeNumbers.ContainsKey($replacement)) { throw "Task number collision during churn: $replacement" }
    $activeNumbers[$replacement] = $true
    if ($activeNumbers.Count -ne 64) { throw 'Visible task-number set changed size during churn.' }
    if ($pool.Released.Count -gt 512) { throw 'Released task-number pool exceeded its bound.' }
}
if (@($activeNumbers.Keys | Sort-Object -Unique).Count -ne 64) { throw 'Visible task numbers are not unique after churn.' }

$discoveryRoot = Join-Path $TestOutputRoot 'session-discovery'
try {
    if (Test-Path -LiteralPath $discoveryRoot) { Remove-Item -LiteralPath $discoveryRoot -Recurse -Force }
    $discoveryNow = Get-Date
    $discoveryDay = Join-Path (Join-Path (Join-Path $discoveryRoot $discoveryNow.Year.ToString('0000')) $discoveryNow.Month.ToString('00')) $discoveryNow.Day.ToString('00')
    New-Item -ItemType Directory -Force -Path $discoveryDay | Out-Null
    $syntheticSession = Join-Path $discoveryDay 'synthetic-active.jsonl'
    [IO.File]::WriteAllText($syntheticSession, '{}')
    $activeFiles = @(Get-ActiveHudSessionFiles $discoveryRoot 60)
    if ($activeFiles.Count -ne 1 -or [string]$activeFiles[0].FullName -ne [string]$syntheticSession) { throw 'Active session discovery self-test failed.' }
} finally {
    if (Test-Path -LiteralPath $discoveryRoot) { Remove-Item -LiteralPath $discoveryRoot -Recurse -Force }
}
$capRoot = Join-Path $TestOutputRoot 'session-cap'
$capNow = Get-Date
$capDay = Join-Path (Join-Path (Join-Path $capRoot $capNow.Year.ToString('0000')) $capNow.Month.ToString('00')) $capNow.Day.ToString('00')
try {
    if (Test-Path -LiteralPath $capRoot) { Remove-Item -LiteralPath $capRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $capDay | Out-Null
    for ($index = 1; $index -le 70; $index++) { [IO.File]::WriteAllText((Join-Path $capDay ('task-{0:d2}.jsonl' -f $index)), '{}') }
    if (@(Get-ActiveHudSessionFiles $capRoot 60).Count -ne 64) { throw 'Active-session 64-file guardrail self-test failed.' }
} finally {
    if (Test-Path -LiteralPath $capRoot) { Remove-Item -LiteralPath $capRoot -Recurse -Force }
}

$resumedRoot = Join-Path $TestOutputRoot 'resumed-old-thread'
try {
    if (Test-Path -LiteralPath $resumedRoot) { Remove-Item -LiteralPath $resumedRoot -Recurse -Force }
    $oldFolder = Join-Path $resumedRoot '2025\01\02'
    $resumedNow = Get-Date
    $todayFolder = Join-Path (Join-Path (Join-Path $resumedRoot $resumedNow.Year.ToString('0000')) $resumedNow.Month.ToString('00')) $resumedNow.Day.ToString('00')
    New-Item -ItemType Directory -Force -Path $oldFolder,$todayFolder | Out-Null
    $oldResumed = Join-Path $oldFolder 'old-but-resumed.jsonl'
    $todayIdle = Join-Path $todayFolder 'today-but-idle.jsonl'
    [IO.File]::WriteAllText($oldResumed,'{}')
    [IO.File]::WriteAllText($todayIdle,'{}')
    [IO.File]::SetLastWriteTimeUtc($oldResumed,[DateTime]::UtcNow)
    [IO.File]::SetLastWriteTimeUtc($todayIdle,[DateTime]::UtcNow.AddHours(-2))
    $resumedFiles = @(Get-ActiveHudSessionFiles $resumedRoot 60)
    if ($resumedFiles.Count -ne 1 -or [string]$resumedFiles[0].FullName -ne [string]$oldResumed) { throw 'Resumed old-date conversation discovery self-test failed.' }
} finally {
    if (Test-Path -LiteralPath $resumedRoot) { Remove-Item -LiteralPath $resumedRoot -Recurse -Force }
}

# Regression for GitHub issue #2: date-format shortcuts once produced folders
# such as 2026M7d15 and then fell back to a single session. Discovery must use
# the real yyyy\MM\dd layout and retain every recent session across old folders.
$multiDateRoot = Join-Path $TestOutputRoot 'multi-date-active-tasks'
try {
    if (Test-Path -LiteralPath $multiDateRoot) { Remove-Item -LiteralPath $multiDateRoot -Recurse -Force }
    $sessionFolders = @(
        (Join-Path $multiDateRoot '2024\01\02'),
        (Join-Path $multiDateRoot '2025\12\31'),
        (Join-Path $multiDateRoot '2026\07\14'),
        (Join-Path $multiDateRoot '2026\07\15')
    )
    $expectedPaths = @()
    for ($index = 0; $index -lt $sessionFolders.Count; $index++) {
        $folder = $sessionFolders[$index]
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        $sessionPath = Join-Path $folder ('synthetic-task-{0}.jsonl' -f ($index + 1))
        [IO.File]::WriteAllText($sessionPath,($contextRecord + "`n" + $rateRecord),(New-Object Text.UTF8Encoding($false)))
        [IO.File]::SetLastWriteTimeUtc($sessionPath,[DateTime]::UtcNow.AddMinutes(-($index * 5)))
        $expectedPaths += $sessionPath
    }

    $issueFiles = @(Get-ActiveHudSessionFiles $multiDateRoot 30)
    if ($issueFiles.Count -ne 4) { throw ('Multi-date active-session discovery regression failed: expected 4, found ' + $issueFiles.Count) }
    $actualPaths = @($issueFiles | ForEach-Object { $_.FullName } | Sort-Object)
    if ((Compare-Object @($expectedPaths | Sort-Object) $actualPaths).Count -ne 0) { throw 'Multi-date active-session discovery returned the wrong files.' }

    $issueSnapshots = @($issueFiles | ForEach-Object { Get-LatestHudSnapshot $_ } | Where-Object { $null -ne $_ })
    $issueAggregate = Merge-HudSnapshots $issueSnapshots $locale
    if ($issueSnapshots.Count -ne 4 -or $null -eq $issueAggregate -or $issueAggregate.ActiveTasks -ne 4) { throw 'Multi-date active-task aggregate regression failed.' }
} finally {
    if (Test-Path -LiteralPath $multiDateRoot) { Remove-Item -LiteralPath $multiDateRoot -Recurse -Force }
}

& (Join-Path $root 'scripts\test-install-protocol.ps1')

Write-Output 'PowerShell syntax: OK'
Write-Output 'XAML syntax: OK'
Write-Output 'Synthetic Codex log parse: OK'
Write-Output 'Token accounting: OK'
Write-Output 'Concurrent task aggregation: OK'
Write-Output 'Observed remaining allowance: OK (5h and weekly)'
Write-Output 'Opt-in API-equivalent cost estimate: OK (local pricing, cached-input rate, unpriced guard)'
Write-Output 'Immediate tail and allowance-only refresh: OK'
Write-Output 'Locale key parity: OK'
Write-Output ("Theme schema and colors: OK ({0} themes)" -f $themes.Count)
Write-Output 'Rich theme bounds and safe visual behavior: OK'
Write-Output 'Status palette: OK (7 states)'
Write-Output 'Mouse click-through defaults, tray and recovery: OK'
Write-Output 'Multi-task modes, density, field separation, resizing and guardrails: OK'
Write-Output 'Behavior architecture: OK (task deep links, quiet indicator, three context stages)'
Write-Output 'Stackable dot and surface reminders: OK'
Write-Output 'Opt-in targeted Codex notices and bounded live choreography: OK'
Write-Output 'Native taskbar, tray and cache-busted shortcut icon: OK'
Write-Output 'Stable numbering stress: OK (10,000 churn cycles, 64 visible tasks)'
Write-Output ("Active session discovery and 64-file cap: OK ({0} live file(s))" -f $activeFiles.Count)
Write-Output 'Resumed old-date conversation discovery: OK'
Write-Output 'Multi-date active task discovery: OK (GitHub issue #2 regression)'
