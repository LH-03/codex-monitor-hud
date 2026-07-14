$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore
$root = Split-Path -Parent $PSScriptRoot
$main = Join-Path $root 'src\CodexMonitorHUD.ps1'
$core = Join-Path $root 'src\MonitorHud.Core.psm1'

foreach ($path in @($main, $core)) {
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
    if ($errors.Count) { throw ($errors | ForEach-Object { $_.ToString() } | Out-String) }
}

[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\HudWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\SettingsWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\ColorPickerWindow.xaml')) | Out-Null
[xml](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\TaskBubbleWindow.xaml')) | Out-Null

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
if ([string]$defaultConfig.themeStyle.surface -ne 'solid' -or [string]$defaultConfig.themeStyle.shadow -ne 'soft' -or [double]$defaultConfig.themeStyle.statusDotSize -ne 8.0) { throw 'Rich theme-style defaults are missing.' }
if ([bool]$defaultConfig.fields.estimatedCost -or [bool]$defaultConfig.multiTask.listFields.estimatedCost -or [bool]$defaultConfig.multiTask.bubbleFields.estimatedCost) { throw 'API-equivalent cost must remain opt-in on every surface.' }
if ([bool]$defaultConfig.agentNotifications.enabled -or [string]$defaultConfig.agentNotifications.permission -ne 'text') { throw 'Codex proactive notifications must remain opt-in with text-only permission by default.' }
if (@('violet','aqua','amber','custom') -notcontains [string]$defaultConfig.agentNotifications.glowPreset -or [string]$defaultConfig.agentNotifications.color -notmatch '^#[0-9A-Fa-f]{8}$') { throw 'Codex notification glow preset or color default is invalid.' }
if ([bool]$defaultConfig.multiTask.listFields.taskTotal -or -not [bool]$defaultConfig.multiTask.bubbleFields.taskTotal) { throw 'List and task-bubble field defaults are not independent.' }
$mainText = Get-Content -Raw -Encoding UTF8 -LiteralPath $main
$mcpText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\mcp-server.mjs')
$settingsXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\SettingsWindow.xaml')
if ($mcpText -notmatch 'monitor_hud_disable_click_through' -or $mainText -notmatch 'passthrough-off\.signal') { throw 'Click-through recovery tool or signal is missing.' }
if ($mainText -notmatch 'System\.Windows\.Forms\.NotifyIcon' -or $mainText -notmatch 'Disable-HudMousePassthrough' -or $mainText -notmatch '\$trayZh\.disableMousePassthrough' -or $mainText -notmatch '\$trayIcon\.Text') { throw 'Localized click-through tray recovery entry is missing.' }
if ($settingsXaml -notmatch 'MousePassthroughCheck' -or $settingsXaml -notmatch 'TickFrequency="0\.1"' -or $settingsXaml -notmatch 'OpacitySlider[^>]+Minimum="0\.15"') { throw 'Click-through setting or low/smooth opacity controls are missing.' }
foreach ($required in @('ThemeWorkshopDropZone','ThemeImportButton','AttentionHelp','ToolTipService.InitialShowDelay')) { if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Polished settings affordance '$required' is missing." } }
foreach ($required in @('MultiTaskTab','DisplayModeCombo','ListStyleCombo','ListDensityCombo','TaskNameModeCombo','MaxSplitCombo','AutoSplitCheck','ListFieldModel','BubbleFieldModel','PositionCustomItem','SummaryAttentionModeCombo','ListAttentionModeCombo','TaskBubbleAttentionModeCombo','SummaryAttentionFlowItem','SummaryAttentionFocusItem','DotAttentionEnabledCheck','DotPatternCombo','DotBrightnessCombo','DotSpeedCombo','DotBreathingCheck','TransparencyModeCombo')) {
    if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Multi-task setting '$required' is missing." }
}
foreach ($required in @('FieldEstimatedCost','ListFieldEstimatedCost','BubbleFieldEstimatedCost','PricingPathText','PricingStatusText')) { if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Cost-estimate setting '$required' is missing." } }
foreach ($required in @('AgentNotificationEnabledCheck','AgentNotificationPermissionCombo','AgentNotificationModeCombo','AgentNotificationGlowPresetCombo','AgentNotificationIntensityCombo','AgentNotificationDurationCombo','AgentNotificationColorText')) { if ($settingsXaml -notmatch [regex]::Escape($required)) { throw "Codex notification setting '$required' is missing." } }
foreach ($required in @('monitor_hud_notify','boundedAnimation','notificationPermission','notificationsRoot','maxLength: 160','permission === "expressive"')) { if ($mcpText -notmatch [regex]::Escape($required)) { throw "Bounded Codex notification MCP path '$required' is missing." } }
foreach ($required in @('Process-HudAgentNotifications','Start-HudAgentAnimation','AgentNoticeText','AgentNoticeRecipe','agentNotificationBadge','AttentionReason -eq ''agent''')) { if ($mainText -notmatch [regex]::Escape($required)) { throw "Targeted Codex notification runtime path '$required' is missing." } }
foreach ($required in @('Show-TaskBubble','Render-TaskList','Get-TaskListDensityMetrics','Split-AllTaskBubbles','Merge-AllTaskBubbles','TaskBubbleResizeThumb','trayViewModeItem')) {
    if ($mainText -notmatch [regex]::Escape($required)) { throw "Multi-task runtime path '$required' is missing." }
}
if ($mainText -notmatch '\$taskCount -gt 0' -or $mainText -notmatch 'PreviewListDensity') { throw 'Persistent list toggle or density preview path is missing.' }
if ($mainText -notmatch 'lastUpdateAnimationSignature' -or $mainText -notmatch 'Update animation:' -or $mainText -match 'DoubleAnimation\(0\.58, 1\.0') { throw 'Event-bound non-flashing update animation guard is missing.' }
$hudXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\HudWindow.xaml')
$bubbleXaml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\TaskBubbleWindow.xaml')
if ($hudXaml -notmatch 'HudListToggleButton' -or $bubbleXaml -notmatch 'TaskBubbleResizeThumb') { throw 'Custom list toggle or task-bubble resize affordance is missing.' }
foreach ($required in @('TaskBubbleDismissButton','Dismiss-HudTask','Dismissed = $false','state.Dismissed = $false','session_index.jsonl','thread_name','Refresh-HudSessionIndex')) { if ($bubbleXaml -notmatch [regex]::Escape($required) -and $mainText -notmatch [regex]::Escape($required)) { throw "Task dismissal or official thread-title path '$required' is missing." } }
foreach ($localeFile in @('locales\zh-CN.json','locales\en.json','locales\symbols.json')) { if ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $localeFile)) -notmatch 'noActiveTasks') { throw "Deleted/no-active task copy is missing from '$localeFile'." } }
$shortcutText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'scripts\create-shortcuts.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $root 'assets\codex-monitor-hud.ico')) -or $mainText -notmatch 'SetCurrentProcessExplicitAppUserModelID' -or $mainText -notmatch 'SendMessage\(' -or $mainText -notmatch 'Set-HudWindowIcon' -or $shortcutText -notmatch 'IconLocation' -or $shortcutText -notmatch 'safeVersion' -or $shortcutText -notmatch 'ie4uinit') { throw 'Native taskbar and cache-busted shortcut icon path is missing.' }

$migrationRoot = Join-Path $root '.test-output\config-migration'
try {
    if (Test-Path -LiteralPath $migrationRoot) { Remove-Item -LiteralPath $migrationRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $migrationRoot | Out-Null
    $legacySettingsPath = Join-Path $migrationRoot 'settings.json'
    [ordered]@{ multiTask=[ordered]@{ taskFields=[ordered]@{ model=$false; callTotal=$true; taskTotal=$false; updated=$false }; listDensity='invalid' } } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $legacySettingsPath -Encoding UTF8
    $migrationPaths = [pscustomobject]@{ DefaultConfigPath=(Join-Path $root 'config.default.json'); ConfigPath=$legacySettingsPath }
    $migratedConfig = Get-HudConfig $migrationPaths
    if ([string]$migratedConfig.multiTask.listDensity -ne 'compact' -or [bool]$migratedConfig.multiTask.bubbleFields.model -or -not [bool]$migratedConfig.multiTask.bubbleFields.callTotal) { throw 'Legacy task-field or list-density migration self-test failed.' }
    if (-not [bool]$migratedConfig.multiTask.listFields.model -or [bool]$migratedConfig.multiTask.listFields.taskTotal) { throw 'Legacy settings unexpectedly replaced compact list-field defaults.' }
} finally {
    if (Test-Path -LiteralPath $migrationRoot) { Remove-Item -LiteralPath $migrationRoot -Recurse -Force }
}
foreach ($surfaceMode in @('summaryMode','listMode','taskBubbleMode')) {
    if ($mainText -notmatch ('Start-HudAttentionAnimation[^\r\n]+config\.attention\.' + $surfaceMode)) { throw "Per-surface reminder path '$surfaceMode' is missing." }
}
foreach ($required in @('completed_silent','PendingCompletionTurnId','completionGraceSeconds','LastListAttentionRevision','config.multiTask.displayMode -eq ''summary''')) { if ($mainText -notmatch [regex]::Escape($required) -and $required -ne 'completed_silent') { throw "Low-false-positive or per-surface routing path '$required' is missing." } }
if ((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'src\MonitorHud.Core.psm1')) -notmatch 'completed_silent') { throw 'Silent completion filtering is missing.' }
foreach ($path in @('docs\AI_PORTING_AND_CUSTOMIZATION_GUIDE.md','skills\create-monitor-hud-theme\SKILL.md','skills\create-monitor-hud-theme\references\theme-format.md')) { if (-not (Test-Path -LiteralPath (Join-Path $root $path))) { throw "Customization artifact '$path' is missing." } }
foreach ($required in @('Import-HudThemeFile','Assert-HudThemeDefinition','\.cmhud-theme','System\.IO\.Compression','New-HudSurfaceBrush')) { if ($mainText -notmatch $required) { throw "Theme workshop runtime path '$required' is missing." } }
foreach ($required in @('Start-HudDotAttentionAnimation','Start-HudSurfaceAttentionAnimation','dotEnabled','dotBreathing','dotBrightness','dotPattern','dotSpeed')) {
    if ($mainText -notmatch [regex]::Escape($required)) { throw "Stackable attention path '$required' is missing." }
}
foreach ($mode in @('halo','breathe','flow','focus')) {
    if ($mainText -notmatch [regex]::Escape("'$mode'")) { throw "Surface attention mode '$mode' is missing." }
}

$mcpTestRoot = Join-Path $root '.test-output\mcp-notice'
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
    $processInfo.FileName = $env:ComSpec
    $processInfo.Arguments = ('/d /s /c "set LOCALAPPDATA={0}&&set CODEX_MONITOR_HUD_DISABLE_AUTO_START=1&&node ""{1}"""' -f $mcpTestRoot,(Join-Path $root 'src\mcp-server.mjs'))
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

$activeFiles = @(Get-ActiveHudSessionFiles (Join-Path $HOME '.codex\sessions') 60)
if ($activeFiles.Count -lt 1) { throw 'Active session discovery self-test failed.' }
$capRoot = Join-Path $root '.test-output\session-cap'
$capDay = Join-Path $capRoot (Get-Date).ToString('yyyy\MM\dd')
try {
    if (Test-Path -LiteralPath $capRoot) { Remove-Item -LiteralPath $capRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $capDay | Out-Null
    for ($index = 1; $index -le 70; $index++) { [IO.File]::WriteAllText((Join-Path $capDay ('task-{0:d2}.jsonl' -f $index)), '{}') }
    if (@(Get-ActiveHudSessionFiles $capRoot 60).Count -ne 64) { throw 'Active-session 64-file guardrail self-test failed.' }
} finally {
    if (Test-Path -LiteralPath $capRoot) { Remove-Item -LiteralPath $capRoot -Recurse -Force }
}

$resumedRoot = Join-Path $root '.test-output\resumed-old-thread'
try {
    if (Test-Path -LiteralPath $resumedRoot) { Remove-Item -LiteralPath $resumedRoot -Recurse -Force }
    $oldFolder = Join-Path $resumedRoot '2025\01\02'
    $todayFolder = Join-Path $resumedRoot (Get-Date).ToString('yyyy\MM\dd')
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

Write-Output 'PowerShell syntax: OK'
Write-Output 'XAML syntax: OK'
Write-Output 'Live Codex log parse: OK'
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
Write-Output 'Stackable dot and surface reminders: OK'
Write-Output 'Opt-in targeted Codex notices and bounded live choreography: OK'
Write-Output 'Native taskbar, tray and cache-busted shortcut icon: OK'
Write-Output 'Stable numbering stress: OK (10,000 churn cycles, 64 visible tasks)'
Write-Output ("Active session discovery and 64-file cap: OK ({0} live file(s))" -f $activeFiles.Count)
Write-Output 'Resumed old-date conversation discovery: OK'
