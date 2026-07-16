param(
    [switch]$Managed,
    [int]$ParentPid = 0,
    [switch]$OpenSettings,
    [switch]$SelfTest,
    [switch]$DebugLog,
    [string]$InstanceId = '',
    [string]$RenderPreview,
    [string]$RenderSettingsPreview,
    [string]$RenderColorPickerPreview,
    [string]$ImportThemeFile,
    [switch]$PreviewSettingsAdvanced,
    [switch]$PreviewSettingsReminders,
    [ValidateSet('general','multi','metrics','appearance')][string]$PreviewSettingsTab = 'general',
    [ValidateSet('zh-CN','en','symbols')][string]$PreviewLanguage = 'zh-CN',
    [ValidateSet('chips','compact','inline','outline','cards','stacked')][string]$PreviewLayout = 'chips',
    [ValidateSet('summary','list')][string]$PreviewHudMode = 'summary',
    [ValidateSet('rows','cards','rail')][string]$PreviewListStyle = 'rows',
    [ValidateSet('compact','balanced','relaxed')][string]$PreviewListDensity = 'compact',
    [ValidateSet('none','off','halo','breathe','flow','focus')][string]$PreviewAttentionMode = 'none',
    [ValidateSet('uniform','layered','focus')][string]$PreviewTransparencyMode = 'uniform',
    [double]$PreviewOpacity = 0,
    [double]$PreviewFontSize = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('HudNativeMethods' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class HudNativeMethods {
    [DllImport("user32.dll", EntryPoint="GetWindowLongW", SetLastError=true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint="SetWindowLongW", SetLastError=true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadImage(IntPtr instance, string name, uint type, int width, int height, uint loadFlags);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
}
'@
}

# Per-monitor V2 prevents Windows from bitmap-scaling the transparent HUD when
# it moves between displays with different scale factors, which softens text.
try { [void][HudNativeMethods]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { }

# A dedicated AppUserModelID prevents Windows from grouping the settings window
# under powershell.exe and selecting the PowerShell taskbar icon for the group.
try { [void][HudNativeMethods]::SetCurrentProcessExplicitAppUserModelID('CodexMonitorHUD.Desktop') } catch { }

$pluginRoot = Split-Path -Parent $PSScriptRoot
$script:windowIconHandles = @{}
Import-Module (Join-Path $PSScriptRoot 'MonitorHud.Core.psm1') -Force
$paths = Get-HudPaths $pluginRoot
$debugPath = Join-Path $pluginRoot '.test-output\runtime.log'

function Write-HudDebug {
    param([string]$Message)
    if (-not $DebugLog) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $debugPath) | Out-Null
    ('{0:O} {1}' -f [DateTime]::Now, $Message) | Add-Content -Encoding UTF8 -LiteralPath $debugPath
}
$openSignal = Join-Path $paths.StateRoot 'open-settings.signal'
$showSignal = Join-Path $paths.StateRoot 'show.signal'
$hideSignal = Join-Path $paths.StateRoot 'hide.signal'
$pauseSignal = Join-Path $paths.StateRoot 'pause.signal'
$passthroughOffSignal = Join-Path $paths.StateRoot 'passthrough-off.signal'
$exitSignal = Join-Path $paths.StateRoot 'exit.signal'
$hostsRoot = Join-Path $paths.StateRoot 'hosts'
$notificationsRoot = Join-Path $paths.StateRoot 'notifications'
$hudHeartbeat = Join-Path $paths.StateRoot 'hud.heartbeat'
$lastHudHeartbeat = [DateTime]::MinValue

$mutex = $null
$isUtilityRun = $SelfTest -or -not [string]::IsNullOrWhiteSpace($RenderPreview) -or -not [string]::IsNullOrWhiteSpace($RenderSettingsPreview) -or -not [string]::IsNullOrWhiteSpace($RenderColorPickerPreview) -or -not [string]::IsNullOrWhiteSpace($ImportThemeFile)
if (-not $isUtilityRun) {
    $createdNew = $false
    $mutexSuffix = if ([string]::IsNullOrWhiteSpace($InstanceId)) { '' } else { '-' + ([regex]::Replace($InstanceId, '[^A-Za-z0-9_.-]', '_')) }
    $mutex = New-Object Threading.Mutex($true, ('Local\CodexMonitorHUD' + $mutexSuffix), [ref]$createdNew)
    if (-not $createdNew) {
        if ($OpenSettings) { [IO.File]::WriteAllText($openSignal, [DateTime]::UtcNow.ToString('O')) }
        exit 0
    }
}

function Release-HudMutex {
    if ($null -eq $mutex) { return }
    try { $mutex.ReleaseMutex() } catch { }
    try { $mutex.Dispose() } catch { }
}

if ($SelfTest) {
    try {
        $file = Get-LatestHudSessionFile $paths.SessionsRoot
        if ($null -eq $file) { throw 'No Codex session file found.' }
        $snapshot = Get-LatestHudSnapshot $file
        if ($null -eq $snapshot) { throw 'No valid token_count record found.' }
        [pscustomobject]@{
            session = $file.Name
            input = $snapshot.Input
            cached = $snapshot.Cached
            uncached = $snapshot.Uncached
            output = $snapshot.Output
            reasoning = $snapshot.Reasoning
            call_total = $snapshot.CallTotal
            task_total = $snapshot.TaskTotal
            context_percent = $snapshot.ContextPercent
            model = $snapshot.Model
            accounting_ok = Test-HudAccounting $snapshot
        } | ConvertTo-Json
    } finally {
        Release-HudMutex
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($RenderPreview) -and [string]::IsNullOrWhiteSpace($RenderSettingsPreview) -and [string]::IsNullOrWhiteSpace($RenderColorPickerPreview)) {
    New-Item -ItemType Directory -Force -Path $paths.StateRoot | Out-Null
}

function Load-XamlWindow {
    param([Parameter(Mandatory = $true)][string]$Path)
    [xml]$xaml = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    $reader = New-Object Xml.XmlNodeReader $xaml
    [Windows.Markup.XamlReader]::Load($reader)
}

function Set-HudWindowIcon {
    param($Window)
    $iconPath = Join-Path $pluginRoot 'assets\codex-monitor-hud.ico'
    if ($null -eq $Window -or -not (Test-Path -LiteralPath $iconPath)) { return }
    try {
        $iconStream = New-Object IO.FileStream($iconPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        try {
            $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create($iconStream,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $Window.Icon = $decoder.Frames[0]
        } finally { $iconStream.Dispose() }

        # WPF's Icon property is not sufficient on every Windows build for a
        # transparent, borderless window hosted by powershell.exe. Apply both
        # native icon sizes once the HWND exists so the taskbar cannot fall
        # back to the host executable icon.
        $resourceKey = [string][Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Window)
        $iconHandleMap = $script:windowIconHandles
        $Window.Add_SourceInitialized({
            try {
                $handle = (New-Object Windows.Interop.WindowInteropHelper($Window)).Handle
                if ($handle -eq [IntPtr]::Zero) { return }
                $large = [HudNativeMethods]::LoadImage([IntPtr]::Zero, $iconPath, 1, 32, 32, 0x10)
                $small = [HudNativeMethods]::LoadImage([IntPtr]::Zero, $iconPath, 1, 16, 16, 0x10)
                if ($large -ne [IntPtr]::Zero) { [void][HudNativeMethods]::SendMessage($handle, 0x80, [IntPtr]1, $large) }
                if ($small -ne [IntPtr]::Zero) { [void][HudNativeMethods]::SendMessage($handle, 0x80, [IntPtr]0, $small) }
                $iconHandleMap[$resourceKey] = @($large, $small)
            } catch { Write-HudDebug ('Native window icon could not be applied: ' + $_.Exception.Message) }
        }.GetNewClosure())
        $Window.Add_Closed({
            if (-not $iconHandleMap.ContainsKey($resourceKey)) { return }
            foreach ($handle in @($iconHandleMap[$resourceKey])) {
                if ($handle -ne [IntPtr]::Zero) { try { [void][HudNativeMethods]::DestroyIcon($handle) } catch { } }
            }
            $iconHandleMap.Remove($resourceKey)
        }.GetNewClosure())
    } catch { Write-HudDebug ('Window icon could not be loaded: ' + $_.Exception.Message) }
}

function Find-Control {
    param($Window, [string]$Name)
    $control = $Window.FindName($Name)
    if ($null -eq $control) { throw "Required XAML control not found: $Name" }
    return $control
}

function New-HudBrush {
    param([string]$Value, [string]$Fallback = '#FFFFFFFF')
    try { return [Windows.Media.BrushConverter]::new().ConvertFromString($Value) } catch {
        return [Windows.Media.BrushConverter]::new().ConvertFromString($Fallback)
    }
}

function Get-HudRoleOpacity {
    param([ValidateSet('background','primary','secondary','decoration','status')][string]$Role)
    if ([string]$config.transparencyMode -eq 'uniform') { return 1.0 }
    $level = [double]$config.opacity
    if ([string]$config.transparencyMode -eq 'focus') {
        $status = Get-HudStatus
        $hasAttention = @(Get-HudUserTaskStates | Where-Object { $_.AttentionUntil -gt [DateTimeOffset]::Now }).Count -gt 0
        if ($hasAttention -or @('active','completed','aborted','error') -contains $status) { $level = [Math]::Max($level, 0.72) }
        elseif ($status -eq 'listening') { $level = [Math]::Max($level, 0.48) }
        else { $level = [Math]::Max(0.08, $level * 0.55) }
    }
    switch ($Role) {
        'background' { return $level }
        'primary' { return [Math]::Min(1.0, [Math]::Max(0.82, 0.76 + (0.22 * $level))) }
        'secondary' { return [Math]::Min(1.0, [Math]::Max(0.42, 0.34 + (0.48 * $level))) }
        'decoration' { return [Math]::Min(1.0, [Math]::Max(0.20, $level)) }
        default { return 1.0 }
    }
}

function New-HudRoleBrush {
    param([string]$Value, [string]$Fallback = '#FFFFFFFF', [ValidateSet('background','primary','secondary','decoration','status')][string]$Role = 'primary')
    $brush = New-HudBrush $Value $Fallback
    if ([string]$config.transparencyMode -eq 'uniform' -or $Role -eq 'status' -or $brush -isnot [Windows.Media.SolidColorBrush]) { return $brush }
    $color = $brush.Color
    $color.A = [byte][Math]::Round($color.A * (Get-HudRoleOpacity $Role))
    return New-Object Windows.Media.SolidColorBrush($color)
}

function New-HudSurfaceBrush {
    if ([string]$config.themeStyle.surface -eq 'image' -and -not [string]::IsNullOrWhiteSpace([string]$config.themeStyle.backgroundImage) -and (Test-Path -LiteralPath ([string]$config.themeStyle.backgroundImage))) {
        try {
            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = New-Object Uri(([string]$config.themeStyle.backgroundImage), [UriKind]::Absolute)
            $bitmap.EndInit()
            $bitmap.Freeze()
            $brush = New-Object Windows.Media.ImageBrush($bitmap)
            $brush.Stretch = [Windows.Media.Stretch]([string]$config.themeStyle.imageStretch)
            $brush.Opacity = [double]$config.themeStyle.imageOpacity
            return $brush
        } catch { }
    }
    if ([string]$config.themeStyle.surface -eq 'gradient') {
        try {
            $start = [Windows.Media.ColorConverter]::ConvertFromString([string]$config.themeStyle.gradientStart)
            $end = [Windows.Media.ColorConverter]::ConvertFromString([string]$config.themeStyle.gradientEnd)
            $factor = Get-HudRoleOpacity 'background'
            $start.A = [byte][Math]::Round($start.A * $factor)
            $end.A = [byte][Math]::Round($end.A * $factor)
            $angle = [double]$config.themeStyle.gradientAngle * [Math]::PI / 180.0
            $dx = [Math]::Cos($angle) * 0.5
            $dy = [Math]::Sin($angle) * 0.5
            $brush = New-Object Windows.Media.LinearGradientBrush
            $brush.StartPoint = New-Object Windows.Point((0.5-$dx),(0.5-$dy))
            $brush.EndPoint = New-Object Windows.Point((0.5+$dx),(0.5+$dy))
            [void]$brush.GradientStops.Add((New-Object Windows.Media.GradientStop($start,0.0)))
            [void]$brush.GradientStops.Add((New-Object Windows.Media.GradientStop($end,1.0)))
            return $brush
        } catch { }
    }
    return New-HudRoleBrush ([string]$config.background) '#EAFFFFFF' 'background'
}

function Get-HudEffectProfile {
    param([string]$Color, [double]$Opacity, [double]$Blur)
    return Get-HudSurfaceEffectProfile `
        -Background ([string]$config.background) `
        -Foreground ([string]$config.foreground) `
        -Surface ([string]$config.themeStyle.surface) `
        -GradientStart ([string]$config.themeStyle.gradientStart) `
        -GradientEnd ([string]$config.themeStyle.gradientEnd) `
        -EffectColor $Color `
        -BaseOpacity $Opacity `
        -BaseBlur $Blur
}

function New-AuroraBrush {
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point(0, 0)
    $brush.EndPoint = New-Object Windows.Point(1, 1)
    $factor = Get-HudRoleOpacity 'background'
    foreach ($entry in @(@('#EE171A2E',0.0),@('#E622365E',0.52),@('#E62B174B',1.0))) {
        $color = [Windows.Media.ColorConverter]::ConvertFromString([string]$entry[0])
        $color.A = [byte][Math]::Round($color.A * $factor)
        $brush.GradientStops.Add((New-Object Windows.Media.GradientStop($color, [double]$entry[1])))
    }
    return $brush
}

function Get-ComboTag {
    param($Combo)
    if ($null -eq $Combo.SelectedItem) { return $null }
    return [string]$Combo.SelectedItem.Tag
}

function Select-ComboTag {
    param($Combo, [string]$Tag)
    foreach ($item in $Combo.Items) {
        if ([string]$item.Tag -eq $Tag) { $Combo.SelectedItem = $item; return }
    }
}

$config = Get-HudConfig $paths
$pricingCatalog = Get-HudPricingCatalog $pluginRoot ([string]$config.pricing.path)
$locale = Get-HudLocale $paths ([string]$config.language)
$settingsLocale = if ([string]$config.language -eq 'symbols') { Get-HudLocale $paths 'en' } else { $locale }
$snapshot = $null
$sessionStates = @{}
$sessionIndexPath = Join-Path $HOME '.codex\session_index.jsonl'
$sessionTitleMap = @{}
$sessionIndexLastWriteUtc = [DateTime]::MinValue
$splitWindows = @{}
$taskNumberPool = New-HudTaskNumberPool 512
$initialSessionScanComplete = $false
$lastFolderScan = [DateTime]::MinValue
$lastUsageAt = [DateTimeOffset]::MinValue
$lastReadErrorAt = [DateTimeOffset]::MinValue
$paused = $false
$closingApp = $false
$syncingControls = $false
$interactivePreview = $false
$currentStatus = 'idle'
$lastMainAttentionRevision = 0
$attentionSequence = 0
$lastUpdateAnimationSignature = ''
$themes = @(Get-HudThemes $pluginRoot)
$hudHandle = [IntPtr]::Zero
$hudBaseExtendedStyle = $null
$trayIcon = $null
$summaryModeItem = $null
$listModeItem = $null
$splitModeItem = $null
$statusPalettes = [ordered]@{
    default = [ordered]@{ active='#FF34C759'; listening='#FF0A84FF'; idle='#FFFF9F0A'; paused='#FF8E8E93'; error='#FFFF453A'; completed='#FF32D74B'; aborted='#FFFF453A' }
    intuitive = [ordered]@{ active='#FF30D158'; listening='#FF0A84FF'; idle='#FF8E8E93'; paused='#FFFF9F0A'; error='#FFFF453A'; completed='#FF30D158'; aborted='#FFFF453A' }
    colorblind = [ordered]@{ active='#FF009E73'; listening='#FF56B4E9'; idle='#FF8A8A8A'; paused='#FFE69F00'; error='#FFD55E00'; completed='#FF009E73'; aborted='#FFD55E00' }
    calm = [ordered]@{ active='#FF5AC8A8'; listening='#FF6FA8DC'; idle='#FF9AA0A6'; paused='#FFD4A95B'; error='#FFD97070'; completed='#FF5AC8A8'; aborted='#FFD97070' }
}

$hud = Load-XamlWindow (Join-Path $PSScriptRoot 'HudWindow.xaml')
Set-HudWindowIcon $hud
Write-HudDebug 'HUD XAML loaded.'
$hudShell = Find-Control $hud 'HudShell'
$statusDot = Find-Control $hud 'StatusDot'
$metricsPanel = Find-Control $hud 'MetricsPanel'
$taskListToggleButton = Find-Control $hud 'TaskListToggleButton'
$taskListDivider = Find-Control $hud 'TaskListDivider'
$taskListScroller = Find-Control $hud 'TaskListScroller'
$taskListPanel = Find-Control $hud 'TaskListPanel'

$settings = Load-XamlWindow (Join-Path $PSScriptRoot 'SettingsWindow.xaml')
Set-HudWindowIcon $settings
Write-HudDebug 'Settings XAML loaded.'
$settingsShell = Find-Control $settings 'SettingsShell'
$titleBar = Find-Control $settings 'TitleBar'
$closeSettingsButton = Find-Control $settings 'CloseSettingsButton'
$themeWorkshopDropZone = Find-Control $settings 'ThemeWorkshopDropZone'
$themeImportButton = Find-Control $settings 'ThemeImportButton'
$languageCombo = Find-Control $settings 'LanguageCombo'
$layoutCombo = Find-Control $settings 'LayoutCombo'
$numberCombo = Find-Control $settings 'NumberCombo'
$positionCombo = Find-Control $settings 'PositionCombo'
$monitorScopeCombo = Find-Control $settings 'MonitorScopeCombo'
$activeWindowCombo = Find-Control $settings 'ActiveWindowCombo'
$taskRetentionCombo = Find-Control $settings 'TaskRetentionCombo'
$terminalExitModeCombo = Find-Control $settings 'TerminalExitModeCombo'
$settingsTabs = Find-Control $settings 'SettingsTabs'
$appearanceScrollViewer = Find-Control $settings 'AppearanceScrollViewer'
$multiTaskScrollViewer = Find-Control $settings 'MultiTaskScrollViewer'
$displayModeCombo = Find-Control $settings 'DisplayModeCombo'
$listStyleCombo = Find-Control $settings 'ListStyleCombo'
$listDensityCombo = Find-Control $settings 'ListDensityCombo'
$taskNameModeCombo = Find-Control $settings 'TaskNameModeCombo'
$maxSplitCombo = Find-Control $settings 'MaxSplitCombo'
$numberCooldownCombo = Find-Control $settings 'NumberCooldownCombo'
$autoSplitCheck = Find-Control $settings 'AutoSplitCheck'
$summaryAttentionModeCombo = Find-Control $settings 'SummaryAttentionModeCombo'
$listAttentionModeCombo = Find-Control $settings 'ListAttentionModeCombo'
$taskBubbleAttentionModeCombo = Find-Control $settings 'TaskBubbleAttentionModeCombo'
$dotAttentionEnabledCheck = Find-Control $settings 'DotAttentionEnabledCheck'
$dotPatternCombo = Find-Control $settings 'DotPatternCombo'
$dotBrightnessCombo = Find-Control $settings 'DotBrightnessCombo'
$dotSpeedCombo = Find-Control $settings 'DotSpeedCombo'
$dotBreathingCheck = Find-Control $settings 'DotBreathingCheck'
$attentionDurationCombo = Find-Control $settings 'AttentionDurationCombo'
$attentionCompletedCheck = Find-Control $settings 'AttentionCompletedCheck'
$attentionErrorCheck = Find-Control $settings 'AttentionErrorCheck'
$attentionSettledCheck = Find-Control $settings 'AttentionSettledCheck'
$agentNotificationEnabledCheck = Find-Control $settings 'AgentNotificationEnabledCheck'
$agentNotificationPermissionCombo = Find-Control $settings 'AgentNotificationPermissionCombo'
$agentNotificationModeCombo = Find-Control $settings 'AgentNotificationModeCombo'
$agentNotificationGlowPresetCombo = Find-Control $settings 'AgentNotificationGlowPresetCombo'
$agentNotificationIntensityCombo = Find-Control $settings 'AgentNotificationIntensityCombo'
$agentNotificationDurationCombo = Find-Control $settings 'AgentNotificationDurationCombo'
$agentNotificationColorText = Find-Control $settings 'AgentNotificationColorText'
$agentNotificationColorButton = Find-Control $settings 'AgentNotificationColorButton'
$transparencyModeCombo = Find-Control $settings 'TransparencyModeCombo'
$fontSizeSlider = Find-Control $settings 'FontSizeSlider'
$radiusSlider = Find-Control $settings 'RadiusSlider'
$opacitySlider = Find-Control $settings 'OpacitySlider'
$fontSizeValue = Find-Control $settings 'FontSizeValue'
$radiusValue = Find-Control $settings 'RadiusValue'
$opacityValue = Find-Control $settings 'OpacityValue'
$alwaysOnTopCheck = Find-Control $settings 'AlwaysOnTopCheck'
$mousePassthroughCheck = Find-Control $settings 'MousePassthroughCheck'
$mousePassthroughHint = Find-Control $settings 'MousePassthroughHint'
$statusDotCheck = Find-Control $settings 'StatusDotCheck'
$animateCheck = Find-Control $settings 'AnimateCheck'
$backgroundText = Find-Control $settings 'BackgroundText'
$foregroundText = Find-Control $settings 'ForegroundText'
$accentText = Find-Control $settings 'AccentText'
$backgroundColorButton = Find-Control $settings 'BackgroundColorButton'
$foregroundColorButton = Find-Control $settings 'ForegroundColorButton'
$accentColorButton = Find-Control $settings 'AccentColorButton'
$advancedStatusExpander = Find-Control $settings 'AdvancedStatusExpander'
$statusPaletteButtons = [ordered]@{
    default = Find-Control $settings 'StatusPaletteDefault'
    intuitive = Find-Control $settings 'StatusPaletteIntuitive'
    colorblind = Find-Control $settings 'StatusPaletteColorblind'
    calm = Find-Control $settings 'StatusPaletteCalm'
}
$statusTextControls = [ordered]@{
    active = Find-Control $settings 'StatusActiveText'
    listening = Find-Control $settings 'StatusListeningText'
    idle = Find-Control $settings 'StatusIdleText'
    paused = Find-Control $settings 'StatusPausedText'
    error = Find-Control $settings 'StatusErrorText'
    completed = Find-Control $settings 'StatusCompletedText'
    aborted = Find-Control $settings 'StatusAbortedText'
}
$statusColorButtons = [ordered]@{
    active = Find-Control $settings 'StatusActiveButton'
    listening = Find-Control $settings 'StatusListeningButton'
    idle = Find-Control $settings 'StatusIdleButton'
    paused = Find-Control $settings 'StatusPausedButton'
    error = Find-Control $settings 'StatusErrorButton'
    completed = Find-Control $settings 'StatusCompletedButton'
    aborted = Find-Control $settings 'StatusAbortedButton'
}
$activeSecondsText = Find-Control $settings 'ActiveSecondsText'
$idleSecondsText = Find-Control $settings 'IdleSecondsText'
$errorHoldSecondsText = Find-Control $settings 'ErrorHoldSecondsText'
$pricingPathText = Find-Control $settings 'PricingPathText'
$pricingStatusText = Find-Control $settings 'PricingStatusText'
$resetButton = Find-Control $settings 'ResetButton'
$saveButton = Find-Control $settings 'SaveButton'
$saveStatus = Find-Control $settings 'SaveStatus'
$settingsScrollViewer = Find-Control $settings 'SettingsScrollViewer'
$settingsTabControls = [ordered]@{
    GeneralTab = Find-Control $settings 'GeneralTab'
    MultiTaskTab = Find-Control $settings 'MultiTaskTab'
    MetricsTab = Find-Control $settings 'MetricsTab'
    AppearanceTab = Find-Control $settings 'AppearanceTab'
}
$listFieldControls = [ordered]@{
    model = Find-Control $settings 'ListFieldModel'
    callTotal = Find-Control $settings 'ListFieldCallTotal'
    taskTotal = Find-Control $settings 'ListFieldTaskTotal'
    estimatedCost = Find-Control $settings 'ListFieldEstimatedCost'
    updated = Find-Control $settings 'ListFieldUpdated'
}
$bubbleFieldControls = [ordered]@{
    model = Find-Control $settings 'BubbleFieldModel'
    callTotal = Find-Control $settings 'BubbleFieldCallTotal'
    taskTotal = Find-Control $settings 'BubbleFieldTaskTotal'
    estimatedCost = Find-Control $settings 'BubbleFieldEstimatedCost'
    updated = Find-Control $settings 'BubbleFieldUpdated'
}

$fieldControls = [ordered]@{}
foreach ($key in @('Input','Cached','Uncached','Output','Reasoning','CallTotal','TaskTotal','Context','Model','Updated','ActiveTasks','WeeklyRemaining','EstimatedCost')) {
    $control = Find-Control $settings ('Field' + $key)
    $fieldControls[[string]$control.Tag] = $control
}

$settingsTextControls = @{}
foreach ($name in @(
    'SettingsSubtitle','PresetsTitle','PresetsHint','ThemeWorkshopTitle','ThemeWorkshopHint','LanguageLayoutTitle','DisplayLanguageLabel','BubbleStyleLabel',
    'NumberFormatLabel','PositionLabel','MonitorScopeLabel','ActiveWindowLabel','TaskRetentionLabel','TerminalExitModeLabel','TerminalExitHint','MetricsTitle','MetricsHint','PricingSourceTitle','PricingSourceHint','PricingPathLabel',
    'AppearanceTitle','FontSizeLabel','RadiusLabel','OpacityLabel','BackgroundColorLabel','ForegroundColorLabel','AccentColorLabel',
    'MousePassthroughHint','StatusPalettesTitle','StatusPalettesHint','MultiTaskTitle','MultiTaskExplanation',
    'DisplayModeLabel','TaskNameModeLabel','MaxSplitLabel','NumberCooldownLabel','ListFieldsTitle','TaskBubbleFieldsTitle','TaskBubbleResizeHint',
    'ListDensityLabel',
    'ListStyleLabel','AgentNotificationTitle','AgentNotificationHint','AgentNotificationPermissionLabel','AgentNotificationModeLabel','AgentNotificationGlowPresetLabel','AgentNotificationIntensityLabel','AgentNotificationDurationLabel','AgentNotificationColorLabel',
    'AttentionTitle','AttentionHint','AttentionTriggersTitle','AttentionSurfacesTitle','SummaryAttentionModeLabel','ListAttentionModeLabel','TaskBubbleAttentionModeLabel','AttentionDurationLabel',
    'DotAttentionTitle','DotAttentionHint','DotPatternLabel','DotBrightnessLabel','DotSpeedLabel',
    'TransparencyModeLabel','TransparencyHint'
)) { $settingsTextControls[$name] = Find-Control $settings $name }

$settingsContentControls = @{}
foreach ($name in @(
    'PresetFrost','PresetMidnight','PresetAurora','PresetGraphite','PresetMinimal',
        'LanguageZhItem','LanguageEnItem','LanguageSymbolsItem','LayoutChipsItem','LayoutCompactItem','LayoutInlineItem','LayoutOutlineItem','LayoutCardsItem','LayoutStackedItem',
    'NumberExactItem','NumberCompactItem','NumberAutoItem','PositionCustomItem','PositionTopRightItem','PositionTopCenterItem','PositionTopLeftItem',
    'PositionBottomRightItem','PositionBottomCenterItem','PositionBottomLeftItem','MonitorLatestItem','MonitorAggregateItem',
    'ActiveWindow5Item','ActiveWindow15Item','ActiveWindow30Item','ActiveWindow60Item','Retention0Item','Retention30Item','Retention60Item','Retention120Item','Retention300Item','Retention600Item','Retention1800Item',
    'TerminalExitFadeItem','TerminalExitGentleItem','TerminalExitFocusItem','TerminalExitBeaconItem',
    'StatusPaletteDefault','StatusPaletteIntuitive','StatusPaletteColorblind','StatusPaletteCalm',
    'ModeSummaryItem','ModeListItem','ModeSplitItem','NameHoverItem','NameAlwaysItem','NameHiddenItem',
    'Cooldown30Item','Cooldown120Item','Cooldown300Item','Cooldown600Item',
    'ListRowsItem','ListCardsItem','ListRailItem','ListDensityCompactItem','ListDensityBalancedItem','ListDensityRelaxedItem',
    'SummaryAttentionOffItem','SummaryAttentionHaloItem','SummaryAttentionBubbleItem','SummaryAttentionFlowItem','SummaryAttentionFocusItem',
    'ListAttentionOffItem','ListAttentionHaloItem','ListAttentionBubbleItem','ListAttentionFlowItem','ListAttentionFocusItem',
    'TaskBubbleAttentionOffItem','TaskBubbleAttentionHaloItem','TaskBubbleAttentionBubbleItem','TaskBubbleAttentionFlowItem','TaskBubbleAttentionFocusItem',
    'AgentNotificationTextPermissionItem','AgentNotificationExpressivePermissionItem',
    'AgentNotificationHaloItem','AgentNotificationBreatheItem','AgentNotificationFlowItem','AgentNotificationFocusItem',
    'AgentNotificationVioletItem','AgentNotificationAquaItem','AgentNotificationAmberItem','AgentNotificationCustomItem',
    'AgentNotificationSubtleItem','AgentNotificationBalancedItem','AgentNotificationStrongItem',
    'AgentNotification8Item','AgentNotification12Item','AgentNotification20Item','AgentNotification30Item',
    'DotPatternSoftItem','DotPatternHeartbeatItem','DotPatternBeaconItem',
    'DotBrightnessSubtleItem','DotBrightnessBalancedItem','DotBrightnessBrightItem',
    'DotSpeedSlowItem','DotSpeedNormalItem','DotSpeedFastItem',
    'Attention4Item','Attention6Item','Attention10Item','Attention15Item',
    'TransparencyUniformItem','TransparencyLayeredItem','TransparencyFocusItem'
)) { $settingsContentControls[$name] = Find-Control $settings $name }

$presetPanel = $settingsContentControls['PresetFrost'].Parent
$themeButtons = @{}
$attentionHelp = Find-Control $settings 'AttentionHelp'

$colorPicker = Load-XamlWindow (Join-Path $PSScriptRoot 'ColorPickerWindow.xaml')
Set-HudWindowIcon $colorPicker
$colorPickerTitleBar = Find-Control $colorPicker 'ColorPickerTitleBar'
$colorPickerTitle = Find-Control $colorPicker 'ColorPickerTitle'
$colorPickerClose = Find-Control $colorPicker 'ColorPickerClose'
$colorWheelCanvas = Find-Control $colorPicker 'ColorWheelCanvas'
$colorWheelImage = Find-Control $colorPicker 'ColorWheelImage'
$colorWheelMarker = Find-Control $colorPicker 'ColorWheelMarker'
$pickerValueSlider = Find-Control $colorPicker 'PickerValueSlider'
$pickerAlphaSlider = Find-Control $colorPicker 'PickerAlphaSlider'
$pickerValueText = Find-Control $colorPicker 'PickerValueText'
$pickerAlphaText = Find-Control $colorPicker 'PickerAlphaText'
$pickerValueLabel = Find-Control $colorPicker 'PickerValueLabel'
$pickerAlphaLabel = Find-Control $colorPicker 'PickerAlphaLabel'
$pickerHexText = Find-Control $colorPicker 'PickerHexText'
$pickerPreview = Find-Control $colorPicker 'PickerPreview'
$pickerCancelButton = Find-Control $colorPicker 'PickerCancelButton'
$pickerApplyButton = Find-Control $colorPicker 'PickerApplyButton'
$pickerTargetText = $null
$pickerTargetButton = $null
$pickerHue = 0.0
$pickerSaturation = 0.0
$pickerSyncing = $false

function Get-ThemeDisplayName {
    param($Theme)
    $language = [string]$config.language
    if ($null -ne $Theme.names.PSObject.Properties[$language]) { return [string]$Theme.names.$language }
    if ($null -ne $Theme.names.PSObject.Properties['en']) { return [string]$Theme.names.en }
    return [string]$Theme.id
}

function Build-ThemeButtons {
    $presetPanel.Children.Clear()
    $script:themeButtons = @{}
    foreach ($theme in $themes) {
        $button = New-Object Windows.Controls.Button
        $button.Tag = [string]$theme.id
        $button.Content = Get-ThemeDisplayName $theme
        $button.ToolTip = [string]$theme.SourcePath
        $button.Add_Click([Windows.RoutedEventHandler]{ param($sender,$eventArgs); Set-Preset ([string]$sender.Tag) })
        [void]$presetPanel.Children.Add($button)
        $script:themeButtons[[string]$theme.id] = $button
    }
}

function Update-ThemeButtonLabels {
    foreach ($theme in $themes) {
        if ($themeButtons.ContainsKey([string]$theme.id)) { $themeButtons[[string]$theme.id].Content = Get-ThemeDisplayName $theme }
    }
}

function Get-BilingualText {
    param([string]$Key)
    $zh = Get-HudLocale $paths 'zh-CN'
    $en = Get-HudLocale $paths 'en'
    if ([string]$config.language -eq 'en') { return ('{0} ({1})' -f [string]$en.$Key, [string]$zh.$Key) }
    if ([string]$config.language -eq 'symbols') { return ('{0} ({1} / {2})' -f [string]$locale.$Key, [string]$zh.$Key, [string]$en.$Key) }
    return ('{0} ({1})' -f [string]$zh.$Key, [string]$en.$Key)
}

function Apply-SettingsLanguage {
    $script:locale = Get-HudLocale $paths ([string]$config.language)
    $script:settingsLocale = if ([string]$config.language -eq 'symbols') { Get-HudLocale $paths 'en' } else { $locale }
    $map = @{
        SettingsSubtitle='settingsSubtitle'; PresetsTitle='presetsTitle'; PresetsHint='presetsHint'; ThemeWorkshopTitle='themeWorkshopTitle'; ThemeWorkshopHint='themeWorkshopHint';
        LanguageLayoutTitle='languageLayoutTitle'; DisplayLanguageLabel='displayLanguage'; BubbleStyleLabel='bubbleStyle';
        NumberFormatLabel='numberFormat'; PositionLabel='position'; MonitorScopeLabel='monitorScope'; ActiveWindowLabel='activeWindow'; TaskRetentionLabel='taskRetention'; TerminalExitModeLabel='terminalExitMode'; TerminalExitHint='terminalExitHint';
        MetricsTitle='metricsTitle'; MetricsHint='metricsHint'; PricingSourceTitle='pricingSourceTitle'; PricingSourceHint='pricingSourceHint'; PricingPathLabel='pricingPathLabel'; AppearanceTitle='appearanceTitle'; FontSizeLabel='fontSize';
        RadiusLabel='cornerRadius'; OpacityLabel='opacity'; BackgroundColorLabel='backgroundColor';
        ForegroundColorLabel='foregroundColor'; AccentColorLabel='accentColor'; MousePassthroughHint='mousePassthroughHint';
        StatusPalettesTitle='statusPalettesTitle'; StatusPalettesHint='statusPalettesHint';
        MultiTaskTitle='multiTaskTitle'; MultiTaskExplanation='multiTaskExplanation'; DisplayModeLabel='displayMode';
        ListStyleLabel='listStyle'; ListDensityLabel='listDensity'; TaskNameModeLabel='taskNameMode'; MaxSplitLabel='maxSplitBubbles'; NumberCooldownLabel='numberCooldown';
        ListFieldsTitle='listFieldsTitle'; TaskBubbleFieldsTitle='taskBubbleFieldsTitle'; TaskBubbleResizeHint='taskBubbleResizeHint';
        AgentNotificationTitle='agentNotificationTitle'; AgentNotificationHint='agentNotificationHint'; AgentNotificationPermissionLabel='agentNotificationPermission';
        AgentNotificationModeLabel='agentNotificationMode'; AgentNotificationGlowPresetLabel='agentNotificationGlowPreset'; AgentNotificationIntensityLabel='agentNotificationIntensity';
        AgentNotificationDurationLabel='agentNotificationDuration'; AgentNotificationColorLabel='agentNotificationColor';
        AttentionTitle='attentionTitle'; AttentionHint='attentionHint'; AttentionTriggersTitle='attentionTriggersTitle'; AttentionSurfacesTitle='attentionSurfacesTitle';
        SummaryAttentionModeLabel='attentionSummaryMode'; ListAttentionModeLabel='attentionListMode'; TaskBubbleAttentionModeLabel='attentionTaskBubbleMode'; AttentionDurationLabel='attentionDuration';
        DotAttentionTitle='dotAttentionTitle'; DotAttentionHint='dotAttentionHint'; DotPatternLabel='dotPattern'; DotBrightnessLabel='dotBrightness'; DotSpeedLabel='dotSpeed';
        TransparencyModeLabel='transparencyMode'; TransparencyHint='transparencyHint'
    }
    foreach ($name in $map.Keys) { $settingsTextControls[$name].Text = [string]$settingsLocale.($map[$name]) }
    foreach ($name in @('PresetsHint','MetricsHint')) {
        $settingsTextControls[$name].TextWrapping = [Windows.TextWrapping]::Wrap
        $settingsTextControls[$name].MaxWidth = 620
        $settingsTextControls[$name].HorizontalAlignment = [Windows.HorizontalAlignment]::Left
    }

    $contentMap = @{
        PresetFrost='presetFrost'; PresetMidnight='presetMidnight'; PresetAurora='presetAurora'; PresetGraphite='presetGraphite'; PresetMinimal='presetMinimal';
        LanguageZhItem='languageZh'; LanguageEnItem='languageEn'; LanguageSymbolsItem='languageSymbols';
        LayoutChipsItem='layoutChips'; LayoutCompactItem='layoutCompact'; LayoutInlineItem='layoutInline'; LayoutOutlineItem='layoutOutline'; LayoutCardsItem='layoutCards'; LayoutStackedItem='layoutStacked';
        NumberExactItem='numberExact'; NumberCompactItem='numberCompact'; NumberAutoItem='numberAuto';
        PositionCustomItem='positionCustom'; PositionTopRightItem='positionTopRight'; PositionTopCenterItem='positionTopCenter'; PositionTopLeftItem='positionTopLeft';
        PositionBottomRightItem='positionBottomRight'; PositionBottomCenterItem='positionBottomCenter'; PositionBottomLeftItem='positionBottomLeft';
        MonitorLatestItem='monitorLatest'; MonitorAggregateItem='monitorAggregate';
        ActiveWindow5Item='minutes5'; ActiveWindow15Item='minutes15'; ActiveWindow30Item='minutes30'; ActiveWindow60Item='minutes60';
        Retention0Item='retentionOff'; Retention30Item='seconds30'; Retention60Item='minutes1'; Retention120Item='minutes2'; Retention300Item='minutes5'; Retention600Item='minutes10'; Retention1800Item='minutes30';
        TerminalExitFadeItem='terminalExitFade'; TerminalExitGentleItem='terminalExitGentle'; TerminalExitFocusItem='terminalExitFocus'; TerminalExitBeaconItem='terminalExitBeacon';
        StatusPaletteDefault='statusPaletteDefault'; StatusPaletteIntuitive='statusPaletteIntuitive';
        StatusPaletteColorblind='statusPaletteColorblind'; StatusPaletteCalm='statusPaletteCalm';
        ModeSummaryItem='modeSummary'; ModeListItem='modeList'; ModeSplitItem='modeSplit';
        ListRowsItem='listRows'; ListCardsItem='listCards'; ListRailItem='listRail';
        ListDensityCompactItem='listDensityCompact'; ListDensityBalancedItem='listDensityBalanced'; ListDensityRelaxedItem='listDensityRelaxed';
        NameHoverItem='nameHover'; NameAlwaysItem='nameAlways'; NameHiddenItem='nameHidden';
        Cooldown30Item='seconds30'; Cooldown120Item='minutes2'; Cooldown300Item='minutes5'; Cooldown600Item='minutes10';
        SummaryAttentionOffItem='attentionOff'; SummaryAttentionHaloItem='attentionHalo'; SummaryAttentionBubbleItem='attentionBubble'; SummaryAttentionFlowItem='attentionFlow'; SummaryAttentionFocusItem='attentionFocus';
        ListAttentionOffItem='attentionOff'; ListAttentionHaloItem='attentionHalo'; ListAttentionBubbleItem='attentionBubble'; ListAttentionFlowItem='attentionFlow'; ListAttentionFocusItem='attentionFocus';
        TaskBubbleAttentionOffItem='attentionOff'; TaskBubbleAttentionHaloItem='attentionHalo'; TaskBubbleAttentionBubbleItem='attentionBubble'; TaskBubbleAttentionFlowItem='attentionFlow'; TaskBubbleAttentionFocusItem='attentionFocus';
        AgentNotificationTextPermissionItem='agentNotificationPermissionText'; AgentNotificationExpressivePermissionItem='agentNotificationPermissionExpressive';
        AgentNotificationHaloItem='agentNotificationHalo'; AgentNotificationBreatheItem='agentNotificationBreathe'; AgentNotificationFlowItem='agentNotificationFlow'; AgentNotificationFocusItem='agentNotificationFocus';
        AgentNotificationVioletItem='agentNotificationViolet'; AgentNotificationAquaItem='agentNotificationAqua'; AgentNotificationAmberItem='agentNotificationAmber'; AgentNotificationCustomItem='agentNotificationCustom';
        AgentNotificationSubtleItem='agentNotificationSubtle'; AgentNotificationBalancedItem='agentNotificationBalanced'; AgentNotificationStrongItem='agentNotificationStrong';
        AgentNotification8Item='seconds8'; AgentNotification12Item='seconds12'; AgentNotification20Item='seconds20'; AgentNotification30Item='seconds30Long';
        DotPatternSoftItem='dotPatternSoft'; DotPatternHeartbeatItem='dotPatternHeartbeat'; DotPatternBeaconItem='dotPatternBeacon';
        DotBrightnessSubtleItem='dotBrightnessSubtle'; DotBrightnessBalancedItem='dotBrightnessBalanced'; DotBrightnessBrightItem='dotBrightnessBright';
        DotSpeedSlowItem='dotSpeedSlow'; DotSpeedNormalItem='dotSpeedNormal'; DotSpeedFastItem='dotSpeedFast';
        Attention4Item='seconds4'; Attention6Item='seconds6'; Attention10Item='seconds10'; Attention15Item='seconds15';
        TransparencyUniformItem='transparencyUniform'; TransparencyLayeredItem='transparencyLayered'; TransparencyFocusItem='transparencyFocus'
    }
    foreach ($name in $contentMap.Keys) { $settingsContentControls[$name].Content = [string]$settingsLocale.($contentMap[$name]) }
    $zhLocale = Get-HudLocale $paths 'zh-CN'
    $enLocale = Get-HudLocale $paths 'en'
    $settingsTextControls['DisplayLanguageLabel'].Text = ('{0} / {1}' -f [string]$zhLocale.displayLanguage, [string]$enLocale.displayLanguage)
    $settingsContentControls['LanguageZhItem'].Content = ('{0} ({1})' -f [string]$zhLocale.languageZh, [string]$enLocale.languageZh)
    $settingsContentControls['LanguageEnItem'].Content = ('{0} ({1})' -f [string]$enLocale.languageEn, [string]$zhLocale.languageEn)
    $settingsContentControls['LanguageSymbolsItem'].Content = ('{0} ({1})' -f [string]$zhLocale.languageSymbols, [string]$enLocale.languageSymbols)
    Update-ThemeButtonLabels

    $english = Get-HudLocale $paths 'en'
    foreach ($key in $fieldControls.Keys) {
        $fieldControls[$key].Content = if ([string]$config.language -eq 'symbols') {
            ('{0}  {1}' -f [string]$locale.$key, [string]$english.$key)
        } else { [string]$settingsLocale.$key }
    }
    $alwaysOnTopCheck.Content = [string]$settingsLocale.alwaysOnTop
    $mousePassthroughCheck.Content = [string]$settingsLocale.mousePassthrough
    $statusDotCheck.Content = [string]$settingsLocale.statusDot
    $animateCheck.Content = [string]$settingsLocale.animateUpdates
    $animateCheck.ToolTip = [string]$settingsLocale.animateUpdatesTooltip
    $autoSplitCheck.Content = [string]$settingsLocale.autoSplitNewTasks
    $attentionCompletedCheck.Content = [string]$settingsLocale.attentionCompleted
    $attentionErrorCheck.Content = [string]$settingsLocale.attentionAbortedOrError
    $attentionSettledCheck.Content = [string]$settingsLocale.attentionSettled
    $agentNotificationEnabledCheck.Content = [string]$settingsLocale.agentNotificationEnabled
    $dotAttentionEnabledCheck.Content = [string]$settingsLocale.dotAttentionEnabled
    $dotBreathingCheck.Content = [string]$settingsLocale.dotBreathing
    $themeImportButton.Content = [string]$settingsLocale.themeImportButton
    $attentionHelp.ToolTip = [string]$settingsLocale.attentionTooltip
    $attentionCompletedCheck.ToolTip = [string]$settingsLocale.attentionCompletedTooltip
    $attentionErrorCheck.ToolTip = [string]$settingsLocale.attentionAbortedOrErrorTooltip
    $attentionSettledCheck.ToolTip = [string]$settingsLocale.attentionSettledTooltip
    $agentNotificationEnabledCheck.ToolTip = [string]$settingsLocale.agentNotificationTooltip
    foreach ($control in @($agentNotificationPermissionCombo,$agentNotificationModeCombo,$agentNotificationGlowPresetCombo,$agentNotificationIntensityCombo)) { $control.ToolTip = [string]$settingsLocale.agentNotificationTooltip }
    foreach ($control in @($summaryAttentionModeCombo,$listAttentionModeCombo,$taskBubbleAttentionModeCombo)) { $control.ToolTip = [string]$settingsLocale.attentionRoutingTooltip }
    $themeWorkshopDropZone.ToolTip = [string]$settingsLocale.themeWorkshopTooltip
    $fieldControls['estimatedCost'].ToolTip = [string]$settingsLocale.estimatedCostTooltip
    $listFieldControls['estimatedCost'].ToolTip = [string]$settingsLocale.estimatedCostTooltip
    $bubbleFieldControls['estimatedCost'].ToolTip = [string]$settingsLocale.estimatedCostTooltip
    $pricingPathText.ToolTip = [string]$settingsLocale.pricingPathTooltip
    foreach ($key in $listFieldControls.Keys) { $listFieldControls[$key].Content = [string]$settingsLocale.$key }
    foreach ($key in $bubbleFieldControls.Keys) { $bubbleFieldControls[$key].Content = [string]$settingsLocale.$key }
    $settingsTabControls['GeneralTab'].Header = [string]$settingsLocale.generalTab
    $settingsTabControls['MultiTaskTab'].Header = [string]$settingsLocale.multiTaskTab
    $settingsTabControls['MetricsTab'].Header = [string]$settingsLocale.metricsTab
    $settingsTabControls['AppearanceTab'].Header = [string]$settingsLocale.appearanceTab
    $resetButton.Content = [string]$settingsLocale.resetDefaults
    $saveButton.Content = [string]$settingsLocale.saveAndClose
    $saveStatus.Text = [string]$settingsLocale.livePreview
    $settings.Title = ('{0} - {1}' -f [string]$settingsLocale.appName, [string]$settingsLocale.settings)
    Set-ColorPickerLanguage ([string]$config.language)

    Update-ContextMenuText
}

function Set-ColorPickerLanguage {
    param([string]$Language)
    $pickerLocale = if ($Language -eq 'en') { Get-HudLocale $paths 'en' } else { Get-HudLocale $paths 'zh-CN' }
    $colorPicker.Title = ('{0} - {1}' -f [string]$pickerLocale.appName, [string]$pickerLocale.colorPickerTitle)
    $colorPickerTitle.Text = [string]$pickerLocale.colorPickerTitle
    $pickerValueLabel.Text = [string]$pickerLocale.colorPickerValue
    $pickerAlphaLabel.Text = [string]$pickerLocale.colorPickerAlpha
    $pickerCancelButton.Content = [string]$pickerLocale.cancel
    $pickerApplyButton.Content = [string]$pickerLocale.apply
}

function Convert-HsvToColor {
    param([double]$Hue, [double]$Saturation, [double]$Value, [byte]$Alpha = 255)
    $h = (($Hue % 360) + 360) % 360
    $s = [Math]::Max(0, [Math]::Min(1, $Saturation))
    $v = [Math]::Max(0, [Math]::Min(1, $Value))
    $c = $v * $s
    $x = $c * (1 - [Math]::Abs((($h / 60.0) % 2) - 1))
    $m = $v - $c
    $r = 0.0; $g = 0.0; $b = 0.0
    if ($h -lt 60) { $r=$c; $g=$x }
    elseif ($h -lt 120) { $r=$x; $g=$c }
    elseif ($h -lt 180) { $g=$c; $b=$x }
    elseif ($h -lt 240) { $g=$x; $b=$c }
    elseif ($h -lt 300) { $r=$x; $b=$c }
    else { $r=$c; $b=$x }
    return [Windows.Media.Color]::FromArgb($Alpha, [byte][Math]::Round(($r+$m)*255), [byte][Math]::Round(($g+$m)*255), [byte][Math]::Round(($b+$m)*255))
}

function Convert-ColorToHsv {
    param([Windows.Media.Color]$Color)
    $r=$Color.R/255.0; $g=$Color.G/255.0; $b=$Color.B/255.0
    $max=[Math]::Max($r,[Math]::Max($g,$b)); $min=[Math]::Min($r,[Math]::Min($g,$b)); $delta=$max-$min
    $h=0.0
    if ($delta -gt 0) {
        if ($max -eq $r) { $h=60*((($g-$b)/$delta)%6) }
        elseif ($max -eq $g) { $h=60*((($b-$r)/$delta)+2) }
        else { $h=60*((($r-$g)/$delta)+4) }
    }
    if ($h -lt 0) { $h += 360 }
    [pscustomobject]@{ Hue=$h; Saturation=$(if($max -eq 0){0}else{$delta/$max}); Value=$max; Alpha=$Color.A/255.0 }
}

function Format-HudColor {
    param([Windows.Media.Color]$Color)
    return ('#{0:X2}{1:X2}{2:X2}{3:X2}' -f $Color.A,$Color.R,$Color.G,$Color.B)
}

function New-ColorWheelBitmap {
    $size=240; $radius=118.0; $center=120.0; $stride=$size*4
    $pixels=New-Object byte[] ($stride*$size)
    for($y=0;$y -lt $size;$y++){
        for($x=0;$x -lt $size;$x++){
            $dx=$x-$center; $dy=$y-$center; $distance=[Math]::Sqrt($dx*$dx+$dy*$dy)
            $index=$y*$stride+$x*4
            if($distance -le $radius){
                $h=[Math]::Atan2($dy,$dx)*180/[Math]::PI; if($h -lt 0){$h+=360}
                $color=Convert-HsvToColor $h ([Math]::Min(1,$distance/$radius)) 1 255
                $pixels[$index]=$color.B; $pixels[$index+1]=$color.G; $pixels[$index+2]=$color.R; $pixels[$index+3]=255
            }
        }
    }
    $bitmap=New-Object Windows.Media.Imaging.WriteableBitmap($size,$size,96,96,[Windows.Media.PixelFormats]::Bgra32,$null)
    $bitmap.WritePixels((New-Object Windows.Int32Rect(0,0,$size,$size)),$pixels,$stride,0)
    return $bitmap
}

function Get-PickerColor {
    $alpha=[byte][Math]::Round([double]$pickerAlphaSlider.Value*255)
    return Convert-HsvToColor $pickerHue $pickerSaturation ([double]$pickerValueSlider.Value) $alpha
}

function Update-PickerVisuals {
    param([bool]$UpdateHex=$true)
    $color=Get-PickerColor
    $pickerPreview.Background=New-Object Windows.Media.SolidColorBrush($color)
    $pickerValueText.Text=('{0:P0}' -f [double]$pickerValueSlider.Value)
    $pickerAlphaText.Text=('{0:P0}' -f [double]$pickerAlphaSlider.Value)
    if($UpdateHex){$script:pickerSyncing=$true;try{$pickerHexText.Text=Format-HudColor $color}finally{$script:pickerSyncing=$false}}
    $radius=118*$pickerSaturation; $angle=$pickerHue*[Math]::PI/180
    [Windows.Controls.Canvas]::SetLeft($colorWheelMarker,120+$radius*[Math]::Cos($angle)-8)
    [Windows.Controls.Canvas]::SetTop($colorWheelMarker,120+$radius*[Math]::Sin($angle)-8)
}

function Set-PickerFromPoint {
    param([Windows.Point]$Point)
    $dx=$Point.X-120; $dy=$Point.Y-120; $distance=[Math]::Sqrt($dx*$dx+$dy*$dy)
    $script:pickerHue=[Math]::Atan2($dy,$dx)*180/[Math]::PI; if($pickerHue -lt 0){$script:pickerHue+=360}
    $script:pickerSaturation=[Math]::Min(1,$distance/118)
    Update-PickerVisuals
}

function Update-ColorSwatches {
    foreach($pair in @(@($backgroundColorButton,$backgroundText),@($foregroundColorButton,$foregroundText),@($accentColorButton,$accentText),@($agentNotificationColorButton,$agentNotificationColorText))){
        try{$pair[0].Background=New-HudBrush ([string]$pair[1].Text) '#FF0A84FF'}catch{}
    }
    foreach($key in $statusColorButtons.Keys){try{$statusColorButtons[$key].Background=New-HudBrush ([string]$statusTextControls[$key].Text) '#FF8E8E93'}catch{}}
}

function Show-ColorPicker {
    param($TargetTextBox,$TargetButton)
    try{$color=[Windows.Media.ColorConverter]::ConvertFromString([string]$TargetTextBox.Text)}catch{$color=[Windows.Media.ColorConverter]::ConvertFromString('#FF0A84FF')}
    $hsv=Convert-ColorToHsv $color
    $script:pickerHue=$hsv.Hue; $script:pickerSaturation=$hsv.Saturation
    $script:pickerTargetText=$TargetTextBox; $script:pickerTargetButton=$TargetButton
    $script:pickerSyncing=$true
    try{$pickerValueSlider.Value=$hsv.Value;$pickerAlphaSlider.Value=$hsv.Alpha}finally{$script:pickerSyncing=$false}
    Update-PickerVisuals
    $colorPicker.Owner=$settings
    [void]$colorPicker.ShowDialog()
}

$colorWheelImage.Source=New-ColorWheelBitmap
$colorWheelCanvas.Add_MouseLeftButtonDown({$colorWheelCanvas.CaptureMouse()|Out-Null;Set-PickerFromPoint ($_.GetPosition($colorWheelCanvas))})
$colorWheelCanvas.Add_MouseMove({if($_.LeftButton -eq [Windows.Input.MouseButtonState]::Pressed){Set-PickerFromPoint ($_.GetPosition($colorWheelCanvas))}})
$colorWheelCanvas.Add_MouseLeftButtonUp({$colorWheelCanvas.ReleaseMouseCapture()})
foreach($pickerSlider in @($pickerValueSlider,$pickerAlphaSlider)){$pickerSlider.Add_ValueChanged({if(-not $pickerSyncing){Update-PickerVisuals}})}
$pickerHexText.Add_LostFocus({if($pickerSyncing){return};try{$c=[Windows.Media.ColorConverter]::ConvertFromString([string]$pickerHexText.Text);$h=Convert-ColorToHsv $c;$script:pickerHue=$h.Hue;$script:pickerSaturation=$h.Saturation;$script:pickerSyncing=$true;try{$pickerValueSlider.Value=$h.Value;$pickerAlphaSlider.Value=$h.Alpha}finally{$script:pickerSyncing=$false};Update-PickerVisuals}catch{}})
$pickerApplyButton.Add_Click({$pickerTargetText.Text=Format-HudColor (Get-PickerColor);if($pickerTargetText-eq$agentNotificationColorText){Select-ComboTag $agentNotificationGlowPresetCombo 'custom'};Update-ColorSwatches;Apply-ControlsToConfig;$colorPicker.Hide()})
$pickerCancelButton.Add_Click({$colorPicker.Hide()})
$colorPickerClose.Add_Click({$colorPicker.Hide()})
$colorPickerTitleBar.Add_MouseLeftButtonDown({if($_.ButtonState -eq [Windows.Input.MouseButtonState]::Pressed){$colorPicker.DragMove()}})
$colorPicker.Add_Closing({if(-not $closingApp){$_.Cancel=$true;$colorPicker.Hide()}})

function Export-ColorPickerPreview {
    param([Parameter(Mandatory = $true)][string]$Path)
    Set-ColorPickerLanguage $PreviewLanguage
    $script:pickerHue = 208.0
    $script:pickerSaturation = 0.82
    $script:pickerSyncing = $true
    try { $pickerValueSlider.Value = 0.96; $pickerAlphaSlider.Value = 0.92 } finally { $script:pickerSyncing = $false }
    Update-PickerVisuals
    $content = $colorPicker.Content
    $size = New-Object Windows.Size(420, 580)
    $content.Measure($size)
    $content.Arrange((New-Object Windows.Rect(0, 0, 420, 580)))
    $content.UpdateLayout()
    [void]$content.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap(420, 580, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($content)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Create)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

if (-not [string]::IsNullOrWhiteSpace($RenderColorPickerPreview)) {
    try { Export-ColorPickerPreview $RenderColorPickerPreview } finally { Release-HudMutex }
    exit 0
}

function Move-HudToConfiguredPosition {
    $hud.UpdateLayout()
    $screen = [Windows.SystemParameters]::WorkArea
    $margin = 18.0
    $left = $screen.Right - $hud.ActualWidth - $margin
    $top = $screen.Top + $margin
    switch ([string]$config.position) {
        'top-left' { $left = $screen.Left + $margin; $top = $screen.Top + $margin }
        'top-center' { $left = $screen.Left + (($screen.Width - $hud.ActualWidth) / 2); $top = $screen.Top + $margin }
        'top-right' { $left = $screen.Right - $hud.ActualWidth - $margin; $top = $screen.Top + $margin }
        'bottom-left' { $left = $screen.Left + $margin; $top = $screen.Bottom - $hud.ActualHeight - $margin }
        'bottom-center' { $left = $screen.Left + (($screen.Width - $hud.ActualWidth) / 2); $top = $screen.Bottom - $hud.ActualHeight - $margin }
        'bottom-right' { $left = $screen.Right - $hud.ActualWidth - $margin; $top = $screen.Bottom - $hud.ActualHeight - $margin }
        'custom' {
            if ($null -ne $config.customLeft) { $left = [double]$config.customLeft }
            if ($null -ne $config.customTop) { $top = [double]$config.customTop }
        }
    }
    $hud.Left = [Math]::Max($screen.Left, [Math]::Min($left, $screen.Right - $hud.ActualWidth))
    $hud.Top = [Math]::Max($screen.Top, [Math]::Min($top, $screen.Bottom - $hud.ActualHeight))
}

function Add-WaitingMetric {
    $text = New-Object Windows.Controls.TextBlock
    $text.Text = if ($paused) {
        [string]$locale.paused
    } elseif ($initialSessionScanComplete -and @(Get-HudUserTaskStates).Count -eq 0) {
        [string]$locale.noActiveTasks
    } else {
        [string]$locale.waiting
    }
    $text.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Microsoft YaHei UI')
    $text.FontSize = [double]$config.fontSize
    $text.FontWeight = [Windows.FontWeights]::SemiBold
    $text.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FFFFFFFF' 'primary'
    $text.VerticalAlignment = [Windows.VerticalAlignment]::Center
    [void]$metricsPanel.Children.Add($text)
}

function Add-HudSeparator {
    if ($metricsPanel.Children.Count -eq 0) { return }
    $separator = New-Object Windows.Controls.TextBlock
    $separator.Text = if ([string]$config.separator -eq 'bar') { '|' } else { [char]0x00B7 }
    $separator.Margin = New-Object Windows.Thickness(7, 0, 7, 0)
    $separator.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $separator.Foreground = New-HudRoleBrush ([string]$config.muted) '#FF8A94A6' 'secondary'
    $separator.FontSize = [double]$config.fontSize
    [void]$metricsPanel.Children.Add($separator)
}

function Add-HudMetric {
    param($Metric)
    if ([string]$config.layout -eq 'inline') { Add-HudSeparator }

    $label = New-Object Windows.Controls.TextBlock
    $label.Text = [string]$Metric.Label
    $label.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Microsoft YaHei UI')
    $label.FontSize = [Math]::Max(10, [double]$config.fontSize - 2)
    $label.Foreground = New-HudRoleBrush ([string]$config.muted) '#FF8A94A6' 'secondary'
    $label.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $label.Margin = if ([string]$config.layout -eq 'cards') { New-Object Windows.Thickness(0, 0, 0, 2) } else { New-Object Windows.Thickness(0, 0, 6, 0) }

    $value = New-Object Windows.Controls.TextBlock
    $value.Text = [string]$Metric.Value
    $value.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Microsoft YaHei UI')
    $value.FontSize = [double]$config.fontSize
    $value.FontWeight = [Windows.FontWeights]::SemiBold
    $value.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FFFFFFFF' 'primary'
    $value.VerticalAlignment = [Windows.VerticalAlignment]::Center

    $content = New-Object Windows.Controls.StackPanel
    $content.Orientation = if ([string]$config.layout -eq 'cards') { [Windows.Controls.Orientation]::Vertical } else { [Windows.Controls.Orientation]::Horizontal }
    [void]$content.Children.Add($label)
    [void]$content.Children.Add($value)

    $container = New-Object Windows.Controls.Border
    $container.Child = $content
    $container.VerticalAlignment = [Windows.VerticalAlignment]::Center
    if ([string]$config.layout -eq 'chips') {
        $accent = [Windows.Media.ColorConverter]::ConvertFromString([string]$config.accent)
        $accent.A = 24
        $container.Background = New-Object Windows.Media.SolidColorBrush($accent)
        $container.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(8, [double]$config.cornerRadius - 10))
        $container.Padding = New-Object Windows.Thickness(10, 6, 10, 6)
        $container.Margin = New-Object Windows.Thickness(0, 0, 6, 0)
    } elseif ([string]$config.layout -eq 'compact') {
        $accent = [Windows.Media.ColorConverter]::ConvertFromString([string]$config.accent)
        $accent.A = 18
        $container.Background = New-Object Windows.Media.SolidColorBrush($accent)
        $container.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(7, [double]$config.cornerRadius - 12))
        $container.Padding = New-Object Windows.Thickness(7, 4, 7, 4)
        $container.Margin = New-Object Windows.Thickness(0, 0, 4, 0)
    } elseif ([string]$config.layout -eq 'outline') {
        $accent = [Windows.Media.ColorConverter]::ConvertFromString([string]$config.accent)
        $fill = $accent; $fill.A = 8
        $stroke = $accent; $stroke.A = 82
        $container.Background = New-Object Windows.Media.SolidColorBrush($fill)
        $container.BorderBrush = New-Object Windows.Media.SolidColorBrush($stroke)
        $container.BorderThickness = New-Object Windows.Thickness(1)
        $container.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(8, [double]$config.cornerRadius - 10))
        $container.Padding = New-Object Windows.Thickness(9, 5, 9, 5)
        $container.Margin = New-Object Windows.Thickness(0, 0, 6, 0)
    } elseif ([string]$config.layout -eq 'cards') {
        $accent = [Windows.Media.ColorConverter]::ConvertFromString([string]$config.accent)
        $fill = $accent; $fill.A = 16
        $stroke = $accent; $stroke.A = 42
        $container.Background = New-Object Windows.Media.SolidColorBrush($fill)
        $container.BorderBrush = New-Object Windows.Media.SolidColorBrush($stroke)
        $container.BorderThickness = New-Object Windows.Thickness(1)
        $container.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(9, [double]$config.cornerRadius - 8))
        $container.Padding = New-Object Windows.Thickness(11, 8, 11, 8)
        $container.Margin = New-Object Windows.Thickness(0, 0, 6, 0)
    } elseif ([string]$config.layout -eq 'stacked') {
        $container.Padding = New-Object Windows.Thickness(4, 3, 4, 3)
        $container.Margin = New-Object Windows.Thickness(0, 0, 0, 2)
    }
    [void]$metricsPanel.Children.Add($container)
}

function Get-NextTaskNumber {
    return Get-HudTaskNumber $taskNumberPool
}

function Release-TaskNumber {
    param([int]$Number)
    Add-HudReleasedTaskNumber $taskNumberPool $Number ([int]$config.multiTask.numberCooldownSeconds)
}

function Get-TaskDisplayName {
    param($State, [switch]$IncludeNumber)
    $workspace = Get-TaskProjectName $State
    $label = if ($null -ne $State.PSObject.Properties['ConversationLabel']) { [string]$State.ConversationLabel } else { '' }
    $identity = if ([string]$config.multiTask.nameMode -ne 'hidden' -and -not [string]::IsNullOrWhiteSpace($label)) { ('{0} {1} {2}' -f $workspace,[char]0x00B7,$label) } else { $workspace }
    $time = ([DateTimeOffset]$State.StartedAt).ToLocalTime().ToString('HH:mm')
    $name = ('{0} {1} {2}' -f $identity, [char]0x00B7, $time)
    if ($IncludeNumber) { return ('#{0} {1} {2}' -f [int]$State.Number, [char]0x00B7, $name) }
    return $name
}

function Get-TaskProjectName {
    param($State)
    $workspace = [string]$State.Workspace
    if ([string]::IsNullOrWhiteSpace($workspace)) { return [string]$settingsLocale.unnamedWorkspace }
    return $workspace
}

function Get-TaskBaseIdentity {
    param($State)
    $workspace = Get-TaskProjectName $State
    $label = if ($null -ne $State.PSObject.Properties['ConversationLabel']) { [string]$State.ConversationLabel } else { '' }
    if ([string]$config.multiTask.nameMode -eq 'hidden' -or [string]::IsNullOrWhiteSpace($label)) { return $workspace }
    return ('{0} {1} {2}' -f $workspace,[char]0x00B7,$label)
}

function Test-HudUserTaskState {
    param($State)
    if ($null -eq $State -or $null -eq $State.Snapshot) { return $false }
    # Do not render a task until its identity header is available. This keeps a
    # just-created auto-review/subagent file out of the UI instead of showing
    # it briefly as a separate user conversation.
    if ($null -ne $State.PSObject.Properties['IdentityMetadataFound'] -and -not [bool]$State.IdentityMetadataFound) { return $false }
    if ($null -ne $State.PSObject.Properties['IsInternalSession'] -and [bool]$State.IsInternalSession) { return $false }
    if ($null -ne $State.PSObject.Properties['Dismissed'] -and [bool]$State.Dismissed) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.TerminalStatus) -and $State.TerminalAt -ne [DateTimeOffset]::MinValue) {
        if ($State.AgentNoticeUntil -gt [DateTimeOffset]::Now) { return $true }
        if ($null -ne $State.PSObject.Properties['TerminalExitCompleted'] -and [bool]$State.TerminalExitCompleted) { return $false }
    }
    return $true
}

function Get-HudUserTaskStates {
    return @($sessionStates.Values | Where-Object { Test-HudUserTaskState $_ })
}

function Get-TaskStatus {
    param($State)
    if ($paused) { return 'paused' }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.TerminalStatus) -and $State.TerminalAt -ne [DateTimeOffset]::MinValue) {
        if ($null -eq $State.PSObject.Properties['TerminalExitCompleted'] -or -not [bool]$State.TerminalExitCompleted) { return [string]$State.TerminalStatus }
    }
    if ($null -ne $State.LastReadErrorAt -and $State.LastReadErrorAt -ne [DateTimeOffset]::MinValue) {
        if (([DateTimeOffset]::Now - $State.LastReadErrorAt).TotalSeconds -le [double]$config.statusTiming.errorHoldSeconds) { return 'error' }
    }
    if ($null -eq $State.Snapshot) { return 'idle' }
    $reference = if ($State.LastUsageAt -ne [DateTimeOffset]::MinValue) { $State.LastUsageAt } else { [DateTimeOffset]$State.Snapshot.Timestamp }
    $age = ([DateTimeOffset]::Now - $reference).TotalSeconds
    if ($age -le [double]$config.statusTiming.activeSeconds) { return 'active' }
    if ($age -le [double]$config.statusTiming.idleSeconds) { return 'listening' }
    return 'idle'
}

function Get-TaskStatusText {
    param([string]$Status)
    $key = [string](@{active='statusActive';listening='statusListening';idle='statusIdle';paused='statusPaused';error='statusError';completed='statusCompleted';aborted='statusAborted'}[$Status])
    return [string]$settingsLocale.$key
}

function Set-TaskAttention {
    param($State, [ValidateSet('completed','aborted','error','settled')][string]$Reason)
    $enabled = switch ($Reason) {
        'completed' { [bool]$config.attention.onCompleted }
        'aborted' { [bool]$config.attention.onAbortedOrError }
        'error' { [bool]$config.attention.onAbortedOrError }
        'settled' { [bool]$config.attention.onSettled }
    }
    $enabledSurfaces = @('summaryMode','listMode','taskBubbleMode') | Where-Object { [string]$config.attention.$_ -ne 'off' }
    if (-not $enabled -or ($enabledSurfaces.Count -eq 0 -and -not [bool]$config.attention.dotEnabled)) { return }
    $script:attentionSequence++
    $State.AttentionRevision = $script:attentionSequence
    $State.AttentionReason = $Reason
    $State.AttentionUntil = [DateTimeOffset]::Now.AddSeconds([int]$config.attention.durationSeconds)
    Write-HudDebug ('Attention triggered: {0} {1} r{2}' -f [string]$State.Workspace,$Reason,[int]$State.AttentionRevision)
}

function Clear-PendingTaskCompletion {
    param($State)
    $State.PendingCompletionTurnId = ''
    $State.PendingCompletionDueAt = [DateTimeOffset]::MinValue
}

function Reset-TerminalExitState {
    param($State)
    $State.TerminalExitStarted = $false
    $State.TerminalExitCompleted = $false
    $State.TerminalExitUntil = [DateTimeOffset]::MinValue
}

function Get-HudTerminalExitSpec {
    param([string]$Mode = ([string]$config.statusTiming.terminalExitMode))
    switch ($Mode) {
        'fade' { return [pscustomobject]@{ Mode='fade'; DurationMs=1200; Scale=1.000; Glow=0.00; Blur=0.0; Flow=$false } }
        'focus' { return [pscustomobject]@{ Mode='focus'; DurationMs=3600; Scale=1.035; Glow=0.82; Blur=34.0; Flow=$false } }
        'beacon' { return [pscustomobject]@{ Mode='beacon'; DurationMs=5000; Scale=1.055; Glow=1.00; Blur=50.0; Flow=$true } }
        default { return [pscustomobject]@{ Mode='gentle'; DurationMs=2400; Scale=1.016; Glow=0.38; Blur=18.0; Flow=$false } }
    }
}

function Update-TerminalExitState {
    param($State)
    if ([string]::IsNullOrWhiteSpace([string]$State.TerminalStatus) -or $State.TerminalAt -eq [DateTimeOffset]::MinValue) {
        if ([bool]$State.TerminalExitStarted -or [bool]$State.TerminalExitCompleted) { Reset-TerminalExitState $State; return $true }
        return $false
    }
    if ([bool]$State.TerminalExitCompleted) { return $false }
    $now = [DateTimeOffset]::Now
    if ($State.AgentNoticeUntil -gt $now -or $State.AttentionUntil -gt $now) { return $false }
    $retentionUntil = $State.TerminalAt.AddSeconds([double]$config.statusTiming.terminalHoldSeconds)
    if ($retentionUntil -gt $now) { return $false }
    if (-not [bool]$State.TerminalExitStarted) {
        $spec = Get-HudTerminalExitSpec
        $State.TerminalExitStarted = $true
        $State.TerminalExitUntil = $now.AddMilliseconds([double]$spec.DurationMs)
        $State.TerminalExitRevision = [int]$State.TerminalExitRevision + 1
        Write-HudDebug ('Terminal exit started: {0} mode={1} r{2}' -f [string]$State.Workspace,[string]$spec.Mode,[int]$State.TerminalExitRevision)
        return $true
    }
    if ($State.TerminalExitUntil -le $now) {
        $State.TerminalExitCompleted = $true
        Write-HudDebug ('Terminal exit completed: ' + [string]$State.Workspace)
        return $true
    }
    return $false
}

function Confirm-PendingTaskCompletion {
    param($State)
    if ($State.PendingCompletionDueAt -eq [DateTimeOffset]::MinValue -or $State.PendingCompletionDueAt -gt [DateTimeOffset]::Now) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.PendingCompletionTurnId) -and
        -not [string]::IsNullOrWhiteSpace([string]$State.ActiveTurnId) -and
        [string]$State.PendingCompletionTurnId -ne [string]$State.ActiveTurnId) {
        Clear-PendingTaskCompletion $State
        return $false
    }
    $State.TerminalStatus = 'completed'
    $State.TerminalAt = [DateTimeOffset]::Now
    $State.TerminalSilent = $false
    Reset-TerminalExitState $State
    Clear-PendingTaskCompletion $State
    Set-TaskAttention $State 'completed'
    return $true
}

function Update-TaskStatusTransition {
    param($State)
    $nextStatus = Get-TaskStatus $State
    $previousStatus = [string]$State.LastRenderedStatus
    if (-not [string]::IsNullOrWhiteSpace($previousStatus) -and $previousStatus -ne $nextStatus) {
        if ($nextStatus -eq 'error') { Set-TaskAttention $State 'error' }
        elseif ($nextStatus -eq 'idle' -and @('active','listening') -contains $previousStatus -and [bool]$State.HasObservedActivity -and [string]::IsNullOrWhiteSpace([string]$State.TerminalStatus)) {
            Set-TaskAttention $State 'settled'
        }
    }
    return $nextStatus
}

function Add-HudAttentionKeyFrame {
    param($Animation, [double]$Percent, [double]$Value)
    $frame = New-Object Windows.Media.Animation.LinearDoubleKeyFrame
    $frame.KeyTime = [Windows.Media.Animation.KeyTime]::FromPercent($Percent)
    $frame.Value = $Value
    [void]$Animation.KeyFrames.Add($frame)
}

function Start-HudTerminalExitAnimation {
    param($Container, [string]$Mode, [string]$Color)
    if ($null -eq $Container) { return }
    $spec = Get-HudTerminalExitSpec $Mode
    $duration = New-Object Windows.Duration([TimeSpan]::FromMilliseconds([double]$spec.DurationMs))
    $opacityFrames = switch ([string]$spec.Mode) {
        'fade' { @(@(0.00,1.00),@(0.28,1.00),@(1.00,0.00)) }
        'focus' { @(@(0.00,1.00),@(0.16,0.72),@(0.30,1.00),@(0.46,0.78),@(0.60,1.00),@(0.80,0.92),@(1.00,0.00)) }
        'beacon' { @(@(0.00,1.00),@(0.10,0.58),@(0.20,1.00),@(0.31,0.66),@(0.42,1.00),@(0.54,0.62),@(0.66,1.00),@(0.82,0.94),@(1.00,0.00)) }
        default { @(@(0.00,1.00),@(0.20,0.82),@(0.38,1.00),@(0.58,0.86),@(0.76,1.00),@(0.88,0.94),@(1.00,0.00)) }
    }
    $opacity = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $opacity.Duration = $duration
    $opacity.FillBehavior = [Windows.Media.Animation.FillBehavior]::HoldEnd
    foreach ($frame in $opacityFrames) { Add-HudAttentionKeyFrame $opacity ([double]$frame[0]) ([double]$frame[1]) }
    $Container.BeginAnimation([Windows.UIElement]::OpacityProperty,$opacity)

    $Container.RenderTransformOrigin = New-Object Windows.Point(0.5,0.5)
    $scale = New-Object Windows.Media.ScaleTransform(1.0,1.0)
    $Container.RenderTransform = $scale
    $scaleFrames = switch ([string]$spec.Mode) {
        'fade' { @(@(0.00,1.000),@(0.75,1.000),@(1.00,0.985)) }
        'focus' { @(@(0.00,1.000),@(0.18,1.035),@(0.34,1.000),@(0.50,1.035),@(0.68,1.000),@(0.84,1.018),@(1.00,0.985)) }
        'beacon' { @(@(0.00,1.000),@(0.12,1.055),@(0.24,1.000),@(0.36,1.055),@(0.48,1.000),@(0.60,1.055),@(0.73,1.000),@(0.86,1.024),@(1.00,0.980)) }
        default { @(@(0.00,1.000),@(0.22,1.016),@(0.42,1.000),@(0.62,1.016),@(0.80,1.000),@(1.00,0.985)) }
    }
    foreach ($property in @([Windows.Media.ScaleTransform]::ScaleXProperty,[Windows.Media.ScaleTransform]::ScaleYProperty)) {
        $animation = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $animation.Duration = $duration
        $animation.FillBehavior = [Windows.Media.Animation.FillBehavior]::HoldEnd
        foreach ($frame in $scaleFrames) { Add-HudAttentionKeyFrame $animation ([double]$frame[0]) ([double]$frame[1]) }
        $scale.BeginAnimation($property,$animation)
    }

    if ([double]$spec.Glow -gt 0) {
        $profile = Get-HudEffectProfile $Color ([double]$spec.Glow) ([double]$spec.Blur)
        $effect = New-Object Windows.Media.Effects.DropShadowEffect
        try { $effect.Color = [Windows.Media.ColorConverter]::ConvertFromString([string]$profile.Color) } catch { $effect.Color = [Windows.Media.Colors]::LimeGreen }
        $effect.ShadowDepth = 0
        $effect.BlurRadius = [double]$profile.Blur
        $effect.Opacity = [double]$profile.MinimumOpacity
        $Container.Effect = $effect
        $glow = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $glow.Duration = $duration
        $glow.FillBehavior = [Windows.Media.Animation.FillBehavior]::HoldEnd
        foreach ($frame in @(@(0.00,[double]$profile.MinimumOpacity),@(0.18,[double]$profile.PeakOpacity),@(0.38,0.12),@(0.58,[double]$profile.PeakOpacity),@(0.78,0.10),@(1.00,0.00))) { Add-HudAttentionKeyFrame $glow ([double]$frame[0]) ([double]$frame[1]) }
        $effect.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty,$glow)
    }

    if ([bool]$spec.Flow -and $Container -is [Windows.Controls.Border]) {
        $profile = Get-HudEffectProfile $Color ([double]$spec.Glow) ([double]$spec.Blur)
        $resolvedColor = try { [Windows.Media.ColorConverter]::ConvertFromString([string]$profile.Color) } catch { [Windows.Media.ColorConverter]::ConvertFromString('#FF32D74B') }
        $rgb = ('{0:X2}{1:X2}{2:X2}' -f $resolvedColor.R,$resolvedColor.G,$resolvedColor.B)
        $gradient = New-Object Windows.Media.LinearGradientBrush
        $gradient.StartPoint = New-Object Windows.Point(0,0.5); $gradient.EndPoint = New-Object Windows.Point(1,0.5)
        foreach ($stopSpec in @(@(0.00,('#00'+$rgb)),@(0.38,('#24'+$rgb)),@(0.50,[string]$profile.FlowCore),@(0.62,('#'+[string]$profile.FlowShoulderAlpha+$rgb)),@(1.00,('#00'+$rgb)))) {
            [void]$gradient.GradientStops.Add((New-Object Windows.Media.GradientStop(([Windows.Media.ColorConverter]::ConvertFromString([string]$stopSpec[1])),[double]$stopSpec[0])))
        }
        $translate = New-Object Windows.Media.TranslateTransform(-1.4,0)
        $gradient.RelativeTransform = $translate
        $Container.BorderBrush = $gradient
        $Container.BorderThickness = New-Object Windows.Thickness(2.4)
        $travel = New-Object Windows.Media.Animation.DoubleAnimation(-1.4,1.4,(New-Object Windows.Duration([TimeSpan]::FromMilliseconds(1100))))
        $travel.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior(4.0)
        $travel.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $translate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$travel)
    }
}

function Start-HudDotAttentionAnimation {
    param($Dot)
    if ($null -eq $Dot -or -not [bool]$config.attention.dotEnabled -or -not [bool]$config.showStatusDot) { return }
    $cycleMs = switch ([string]$config.attention.dotSpeed) { 'slow' { 1050 } 'fast' { 460 } default { 700 } }
    $brightness = switch ([string]$config.attention.dotBrightness) {
        'subtle' { [pscustomobject]@{ Minimum=0.58; Glow=0.40; Blur=8.0; Scale=1.10 } }
        'bright' { [pscustomobject]@{ Minimum=0.10; Glow=1.00; Blur=18.0; Scale=1.28 } }
        default { [pscustomobject]@{ Minimum=0.28; Glow=0.76; Blur=13.0; Scale=1.18 } }
    }
    $repeatCount = [Math]::Max(2, [Math]::Ceiling(([int]$config.attention.durationSeconds * 1000.0) / $cycleMs))
    $opacityAnimation = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $opacityAnimation.Duration = New-Object Windows.Duration([TimeSpan]::FromMilliseconds($cycleMs))
    $opacityAnimation.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior([double]$repeatCount)
    $opacityAnimation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    switch ([string]$config.attention.dotPattern) {
        'soft' {
            Add-HudAttentionKeyFrame $opacityAnimation 0.00 1.0; Add-HudAttentionKeyFrame $opacityAnimation 0.50 $brightness.Minimum; Add-HudAttentionKeyFrame $opacityAnimation 1.00 1.0
        }
        'beacon' {
            Add-HudAttentionKeyFrame $opacityAnimation 0.00 $brightness.Minimum; Add-HudAttentionKeyFrame $opacityAnimation 0.70 1.0; Add-HudAttentionKeyFrame $opacityAnimation 1.00 $brightness.Minimum
        }
        default {
            Add-HudAttentionKeyFrame $opacityAnimation 0.00 1.0; Add-HudAttentionKeyFrame $opacityAnimation 0.16 $brightness.Minimum; Add-HudAttentionKeyFrame $opacityAnimation 0.32 1.0
            Add-HudAttentionKeyFrame $opacityAnimation 0.46 ([Math]::Min(0.92, $brightness.Minimum + 0.16)); Add-HudAttentionKeyFrame $opacityAnimation 0.62 1.0; Add-HudAttentionKeyFrame $opacityAnimation 1.00 1.0
        }
    }
    $Dot.BeginAnimation([Windows.UIElement]::OpacityProperty, $opacityAnimation)

    $effectColor = [string]$config.accent
    try {
        if ($Dot.Fill -is [Windows.Media.SolidColorBrush]) { $effectColor = $Dot.Fill.Color.ToString() }
    } catch { }
    $profile = Get-HudEffectProfile $effectColor ([double]$brightness.Glow) ([double]$brightness.Blur)
    $glow = New-Object Windows.Media.Effects.DropShadowEffect
    try { $glow.Color = [Windows.Media.ColorConverter]::ConvertFromString([string]$profile.Color) } catch { $glow.Color = [Windows.Media.Colors]::DodgerBlue }
    $glow.ShadowDepth = 0
    $glow.BlurRadius = [double]$profile.Blur
    $glow.Opacity = [double]$profile.MinimumOpacity
    $Dot.Effect = $glow
    $glowAnimation = New-Object Windows.Media.Animation.DoubleAnimation([double]$profile.MinimumOpacity, [double]$profile.PeakOpacity, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds([Math]::Round($cycleMs / 2)))))
    $glowAnimation.AutoReverse = $true
    $glowAnimation.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior([double]$repeatCount)
    $glowAnimation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $glow.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty, $glowAnimation)

    if ([bool]$config.attention.dotBreathing) {
        $Dot.RenderTransformOrigin = New-Object Windows.Point(0.5,0.5)
        $scale = New-Object Windows.Media.ScaleTransform(1.0,1.0)
        $Dot.RenderTransform = $scale
        foreach ($property in @([Windows.Media.ScaleTransform]::ScaleXProperty,[Windows.Media.ScaleTransform]::ScaleYProperty)) {
            $scaleAnimation = New-Object Windows.Media.Animation.DoubleAnimation(1.0, [double]$brightness.Scale, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds([Math]::Round($cycleMs / 2)))))
            $scaleAnimation.AutoReverse = $true
            $scaleAnimation.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior([double]$repeatCount)
            $scaleAnimation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
            $scale.BeginAnimation($property, $scaleAnimation)
        }
    }
}

function Start-HudSurfaceAttentionAnimation {
    param($Container, [ValidateSet('off','halo','breathe','flow','focus')][string]$Mode)
    if ($Mode -eq 'off' -or $null -eq $Container) { return }
    $seconds = [int]$config.attention.durationSeconds
    $repeatCount = [Math]::Max(2, [Math]::Ceiling($seconds / 0.9))
    $repeat = New-Object Windows.Media.Animation.RepeatBehavior([double]$repeatCount)
    if ($Mode -eq 'halo') {
        $profile = Get-HudEffectProfile ([string]$config.accent) 0.72 20.0
        $effect = New-Object Windows.Media.Effects.DropShadowEffect
        $effect.Color = [Windows.Media.ColorConverter]::ConvertFromString([string]$profile.Color)
        $effect.ShadowDepth = 0; $effect.BlurRadius = [double]$profile.Blur; $effect.Opacity = 0
        $Container.Effect = $effect
        $animation = New-Object Windows.Media.Animation.DoubleAnimation([double]$profile.MinimumOpacity,[double]$profile.PeakOpacity,(New-Object Windows.Duration([TimeSpan]::FromMilliseconds(620))))
        $animation.AutoReverse=$true;$animation.RepeatBehavior=$repeat;$animation.FillBehavior=[Windows.Media.Animation.FillBehavior]::Stop
        $effect.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty,$animation)
        return
    }
    if ($Mode -eq 'flow' -and $Container -is [Windows.Controls.Border]) {
        $profile = Get-HudEffectProfile ([string]$config.accent) 0.78 20.0
        $flowColor = [Windows.Media.ColorConverter]::ConvertFromString([string]$profile.Color)
        $flowRgb = ('{0:X2}{1:X2}{2:X2}' -f $flowColor.R,$flowColor.G,$flowColor.B)
        $gradient = New-Object Windows.Media.LinearGradientBrush
        $gradient.StartPoint = New-Object Windows.Point(0,0.5); $gradient.EndPoint = New-Object Windows.Point(1,0.5)
        foreach ($stopSpec in @(@(0.00,('#00'+$flowRgb)),@(0.40,('#22'+$flowRgb)),@(0.50,[string]$profile.FlowCore),@(0.60,('#'+[string]$profile.FlowShoulderAlpha+$flowRgb)),@(1.00,('#00'+$flowRgb)))) {
            [void]$gradient.GradientStops.Add((New-Object Windows.Media.GradientStop(([Windows.Media.ColorConverter]::ConvertFromString([string]$stopSpec[1])),[double]$stopSpec[0])))
        }
        $translate = New-Object Windows.Media.TranslateTransform(-1.3,0)
        $gradient.RelativeTransform = $translate
        $Container.BorderBrush = $gradient
        $Container.BorderThickness = New-Object Windows.Thickness(2)
        $travel = New-Object Windows.Media.Animation.DoubleAnimation(-1.3,1.3,(New-Object Windows.Duration([TimeSpan]::FromMilliseconds(1050))))
        $travel.RepeatBehavior = New-Object Windows.Media.Animation.RepeatBehavior([double]([Math]::Max(2,[Math]::Ceiling($seconds / 1.05))))
        $travel.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $translate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$travel)
        return
    }
    $Container.RenderTransformOrigin = New-Object Windows.Point(0.5,0.5)
    $scale = New-Object Windows.Media.ScaleTransform(1.0,1.0)
    $Container.RenderTransform = $scale
    $strong = $Mode -eq 'focus'
    $toScale = if ($strong) { 1.035 } else { 1.016 }
    $fromOpacity = if ($strong) { 0.48 } else { 0.78 }
    $durationMs = if ($strong) { 300 } else { 560 }
    foreach ($property in @([Windows.Media.ScaleTransform]::ScaleXProperty,[Windows.Media.ScaleTransform]::ScaleYProperty)) {
        $animation = New-Object Windows.Media.Animation.DoubleAnimation(1.0,$toScale,(New-Object Windows.Duration([TimeSpan]::FromMilliseconds($durationMs))))
        $animation.AutoReverse=$true;$animation.RepeatBehavior=$repeat;$animation.FillBehavior=[Windows.Media.Animation.FillBehavior]::Stop
        $scale.BeginAnimation($property,$animation)
    }
    $opacity = New-Object Windows.Media.Animation.DoubleAnimation($fromOpacity,1.0,(New-Object Windows.Duration([TimeSpan]::FromMilliseconds($durationMs))))
    $opacity.AutoReverse=$true;$opacity.RepeatBehavior=$repeat;$opacity.FillBehavior=[Windows.Media.Animation.FillBehavior]::Stop
    $Container.BeginAnimation([Windows.UIElement]::OpacityProperty,$opacity)
}

function Start-HudAttentionAnimation {
    param($Dot, $Container, [ValidateSet('off','halo','breathe','flow','focus')][string]$Mode)
    Start-HudDotAttentionAnimation $Dot
    Start-HudSurfaceAttentionAnimation $Container $Mode
}

function Get-AgentRecipeProperty {
    param($Recipe, [string]$Name, $Fallback)
    if ($null -ne $Recipe -and $null -ne $Recipe.PSObject.Properties[$Name]) { return $Recipe.$Name }
    return $Fallback
}

function Get-HudAgentAnimationRecipe {
    param($RequestedRecipe)
    $modeLayers = switch ([string]$config.agentNotifications.mode) {
        'halo' { @('glow') }
        'breathe' { @('glow','breathe') }
        'flow' { @('glow','flow') }
        default { @('glow','pulse','breathe') }
    }
    $baseIntensity = switch ([string]$config.agentNotifications.intensity) { 'subtle' { 0.42 } 'strong' { 0.95 } default { 0.70 } }
    $recipe = [ordered]@{
        Layers = @($modeLayers)
        Color = [string]$config.agentNotifications.color
        Intensity = [double]$baseIntensity
        TempoMs = 720
        Cycles = [Math]::Max(1,[Math]::Min(8,[Math]::Ceiling(([int]$config.agentNotifications.durationSeconds * 1000.0) / 720)))
        GlowRadius = switch ([string]$config.agentNotifications.intensity) { 'subtle' { 18.0 } 'strong' { 44.0 } default { 30.0 } }
        Scale = switch ([string]$config.agentNotifications.intensity) { 'subtle' { 1.012 } 'strong' { 1.055 } default { 1.028 } }
        Direction = 'left-to-right'
    }
    if ([string]$config.agentNotifications.permission -eq 'expressive' -and $null -ne $RequestedRecipe) {
        $allowed = @('glow','pulse','breathe','flow')
        $requestedLayers = @((Get-AgentRecipeProperty $RequestedRecipe 'layers' @()) | ForEach-Object { [string]$_ } | Where-Object { $allowed -contains $_ } | Select-Object -Unique -First 4)
        if ($requestedLayers.Count -gt 0) { $recipe.Layers = $requestedLayers }
        $candidateColor = [string](Get-AgentRecipeProperty $RequestedRecipe 'color' $recipe.Color)
        if ($candidateColor -match '^#[0-9A-Fa-f]{8}$') { $recipe.Color = $candidateColor }
        $recipe.Intensity = [Math]::Max(0.2,[Math]::Min(1.0,[double](Get-AgentRecipeProperty $RequestedRecipe 'intensity' $recipe.Intensity)))
        $recipe.TempoMs = [Math]::Round([Math]::Max(240,[Math]::Min(2500,[double](Get-AgentRecipeProperty $RequestedRecipe 'tempo_ms' $recipe.TempoMs))))
        $recipe.Cycles = [Math]::Round([Math]::Max(1,[Math]::Min(8,[double](Get-AgentRecipeProperty $RequestedRecipe 'cycles' $recipe.Cycles))))
        $recipe.GlowRadius = [Math]::Max(8,[Math]::Min(60,[double](Get-AgentRecipeProperty $RequestedRecipe 'glow_radius' $recipe.GlowRadius)))
        $recipe.Scale = [Math]::Max(1,[Math]::Min(1.08,[double](Get-AgentRecipeProperty $RequestedRecipe 'scale' $recipe.Scale)))
        if ([string](Get-AgentRecipeProperty $RequestedRecipe 'direction' '') -eq 'right-to-left') { $recipe.Direction = 'right-to-left' }
    }
    return [pscustomobject]$recipe
}

function Start-HudAgentAnimation {
    param($Container, $RequestedRecipe)
    if ($null -eq $Container) { return }
    $recipe = Get-HudAgentAnimationRecipe $RequestedRecipe
    $profile = Get-HudEffectProfile ([string]$recipe.Color) ([double]$recipe.Intensity) ([double]$recipe.GlowRadius)
    $color = try { [Windows.Media.ColorConverter]::ConvertFromString([string]$profile.Color) } catch { [Windows.Media.ColorConverter]::ConvertFromString('#FF7C3AED') }
    $duration = New-Object Windows.Duration([TimeSpan]::FromMilliseconds([double]$recipe.TempoMs))
    $repeat = New-Object Windows.Media.Animation.RepeatBehavior([double][int]$recipe.Cycles)

    if (@($recipe.Layers) -contains 'glow') {
        $effect = New-Object Windows.Media.Effects.DropShadowEffect
        $effect.Color = $color; $effect.ShadowDepth = 0; $effect.BlurRadius = [double]$profile.Blur; $effect.Opacity = [double]$profile.MinimumOpacity
        $Container.Effect = $effect
        $glow = New-Object Windows.Media.Animation.DoubleAnimation([double]$profile.MinimumOpacity,[double]$profile.PeakOpacity,$duration)
        $glow.AutoReverse=$true;$glow.RepeatBehavior=$repeat;$glow.FillBehavior=[Windows.Media.Animation.FillBehavior]::Stop
        $effect.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty,$glow)
    }
    if (@($recipe.Layers) -contains 'pulse') {
        $minimum = [Math]::Max(0.50,1.0-([double]$recipe.Intensity*0.42))
        $pulse = New-Object Windows.Media.Animation.DoubleAnimation($minimum,1.0,$duration)
        $pulse.AutoReverse=$true;$pulse.RepeatBehavior=$repeat;$pulse.FillBehavior=[Windows.Media.Animation.FillBehavior]::Stop
        $Container.BeginAnimation([Windows.UIElement]::OpacityProperty,$pulse)
    }
    if (@($recipe.Layers) -contains 'breathe') {
        $Container.RenderTransformOrigin = New-Object Windows.Point(0.5,0.5)
        $scale = New-Object Windows.Media.ScaleTransform(1.0,1.0)
        $Container.RenderTransform = $scale
        foreach ($property in @([Windows.Media.ScaleTransform]::ScaleXProperty,[Windows.Media.ScaleTransform]::ScaleYProperty)) {
            $breathe = New-Object Windows.Media.Animation.DoubleAnimation(1.0,[double]$recipe.Scale,$duration)
            $breathe.AutoReverse=$true;$breathe.RepeatBehavior=$repeat;$breathe.FillBehavior=[Windows.Media.Animation.FillBehavior]::Stop
            $scale.BeginAnimation($property,$breathe)
        }
    }
    if (@($recipe.Layers) -contains 'flow' -and $Container -is [Windows.Controls.Border]) {
        $rgb = ('{0:X2}{1:X2}{2:X2}' -f $color.R,$color.G,$color.B)
        $gradient = New-Object Windows.Media.LinearGradientBrush
        $gradient.StartPoint=New-Object Windows.Point(0,0.5);$gradient.EndPoint=New-Object Windows.Point(1,0.5)
        foreach ($stopSpec in @(@(0.00,('#00'+$rgb)),@(0.38,('#18'+$rgb)),@(0.50,[string]$profile.FlowCore),@(0.62,('#'+[string]$profile.FlowShoulderAlpha+$rgb)),@(1.00,('#00'+$rgb)))) {
            [void]$gradient.GradientStops.Add((New-Object Windows.Media.GradientStop(([Windows.Media.ColorConverter]::ConvertFromString([string]$stopSpec[1])),[double]$stopSpec[0])))
        }
        $from = if ([string]$recipe.Direction -eq 'right-to-left') { 1.4 } else { -1.4 }
        $to = -$from
        $translate = New-Object Windows.Media.TranslateTransform($from,0)
        $gradient.RelativeTransform = $translate
        $Container.BorderBrush = $gradient
        $Container.BorderThickness = New-Object Windows.Thickness([Math]::Max(1.0,[Math]::Min(2.5,0.8+([double]$recipe.Intensity*1.7))))
        $travel = New-Object Windows.Media.Animation.DoubleAnimation($from,$to,$duration)
        $travel.RepeatBehavior=$repeat;$travel.FillBehavior=[Windows.Media.Animation.FillBehavior]::Stop
        $translate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$travel)
    }
}

function Get-HudAgentNoticeText {
    param($State)
    if ($null -eq $State -or $State.AgentNoticeUntil -le [DateTimeOffset]::Now -or [string]::IsNullOrWhiteSpace([string]$State.AgentNoticeText)) { return '' }
    return ('{0} #{1}  {2}' -f [string]$settingsLocale.agentNotificationBadge,[int]$State.Number,[string]$State.AgentNoticeText)
}

function Get-TaskMetricsText {
    param($State, [ValidateSet('list','bubble')][string]$Surface = 'bubble')
    if ($null -eq $State.Snapshot) { return [string]$settingsLocale.waiting }
    $fields = if ($Surface -eq 'list') { $config.multiTask.listFields } else { $config.multiTask.bubbleFields }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((Get-TaskStatusText (Get-TaskStatus $State)))
    if ([bool]$fields.model -and -not [string]::IsNullOrWhiteSpace([string]$State.Snapshot.Model)) { [void]$parts.Add([string]$State.Snapshot.Model) }
    if ([bool]$fields.callTotal) { [void]$parts.Add(('{0} {1}' -f [string]$settingsLocale.callTotal, (Format-HudNumber ([Int64]$State.Snapshot.CallTotal) ([string]$config.numberFormat)))) }
    if ([bool]$fields.taskTotal) { [void]$parts.Add(('{0} {1}' -f [string]$settingsLocale.taskTotal, (Format-HudNumber ([Int64]$State.Snapshot.TaskTotal) ([string]$config.numberFormat)))) }
    if ([bool]$fields.estimatedCost) {
        $taskCost = if ($null -ne $State.Snapshot.PSObject.Properties['EstimatedCostUsd']) { $State.Snapshot.EstimatedCostUsd } else { $null }
        [void]$parts.Add(('{0} {1}' -f [string]$settingsLocale.estimatedCost, (Format-HudCost $taskCost)))
    }
    if ([bool]$fields.updated) { [void]$parts.Add($State.Snapshot.Timestamp.ToString('HH:mm:ss')) }
    $metricsText = ($parts -join (' {0} ' -f [char]0x00B7))
    $noticeText = Get-HudAgentNoticeText $State
    $showNoticeHere = -not [string]::IsNullOrWhiteSpace($noticeText) -and ($Surface -eq 'bubble' -or ([string]$config.multiTask.displayMode -eq 'list' -and -not [bool]$State.Detached))
    if ($showNoticeHere) { return ('✦ {0}  ·  {1}' -f $noticeText,$metricsText) }
    return $metricsText
}

function Update-TaskBubble {
    param($State)
    if (-not $splitWindows.ContainsKey([string]$State.Path)) { return }
    $entry = $splitWindows[[string]$State.Path]
    $status = Get-TaskStatus $State
    $entry.Window.Topmost = [bool]$config.alwaysOnTop
    $entry.Window.Opacity = if ([string]$config.transparencyMode -eq 'uniform') { [double]$config.opacity } else { 1.0 }
    $entry.Shell.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(12, [double]$config.cornerRadius - 4))
    $entry.Shell.Background = New-HudSurfaceBrush
    $agentAttentionActive = [string]$State.AttentionReason -eq 'agent' -and $State.AttentionUntil -gt [DateTimeOffset]::Now
    if (([string]$config.attention.taskBubbleMode -ne 'flow' -and -not $agentAttentionActive) -or $State.AttentionUntil -le [DateTimeOffset]::Now) {
        $entry.Shell.BorderBrush = New-HudRoleBrush ([string]$config.border) '#22FFFFFF' 'decoration'
        $entry.Shell.BorderThickness = New-Object Windows.Thickness([double]$config.themeStyle.borderWidth)
    }
    $entry.Dot.Width = [double]$config.themeStyle.statusDotSize
    $entry.Dot.Height = [double]$config.themeStyle.statusDotSize
    $entry.Dot.Fill = New-HudBrush ([string]$config.statusColors.$status) '#FF8E8E93'
    $entry.Number.Text = ('#{0}' -f [int]$State.Number)
    $entry.Number.Foreground = New-HudRoleBrush ([string]$config.accent) '#FF0A84FF' 'primary'
    $entry.Name.Text = Get-TaskDisplayName $State
    $entry.Name.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary'
    $entry.Metrics.Text = Get-TaskMetricsText $State -Surface bubble
    $entry.Metrics.Foreground = New-HudRoleBrush ([string]$config.muted) '#FF667085' 'secondary'
    try {
        $themeFont = New-Object Windows.Media.FontFamily([string]$config.themeStyle.fontFamily)
        $entry.Number.FontFamily = $themeFont; $entry.Name.FontFamily = $themeFont; $entry.Metrics.FontFamily = $themeFont
    } catch { }
    $entry.Merge.ToolTip = [string]$settingsLocale.mergeTask
    $entry.Dismiss.ToolTip = [string]$settingsLocale.dismissTask
    $entry.Resize.ToolTip = [string]$settingsLocale.resizeTaskBubble
    if ([int]$State.AttentionRevision -gt [int]$entry.LastAttentionRevision -and $State.AttentionUntil -gt [DateTimeOffset]::Now) {
        $entry.LastAttentionRevision = [int]$State.AttentionRevision
        Write-HudDebug ('Attention surface: bubble {0} r{1} reason={2}' -f [string]$State.Workspace,[int]$State.AttentionRevision,[string]$State.AttentionReason)
        if ([string]$State.AttentionReason -eq 'agent') { Start-HudAgentAnimation $entry.Shell $State.AgentNoticeRecipe }
        else { Start-HudAttentionAnimation $entry.Dot $entry.Shell ([string]$config.attention.taskBubbleMode) }
    }
    if ([int]$State.TerminalExitRevision -gt [int]$entry.LastExitRevision -and $State.TerminalExitUntil -gt [DateTimeOffset]::Now) {
        $entry.LastExitRevision = [int]$State.TerminalExitRevision
        Write-HudDebug ('Terminal exit surface: bubble {0} r{1}' -f [string]$State.Workspace,[int]$State.TerminalExitRevision)
        Start-HudTerminalExitAnimation $entry.Shell ([string]$config.statusTiming.terminalExitMode) ([string]$config.statusColors.$status)
    }
}

function Position-TaskBubbles {
    $entries = @($splitWindows.Values | Where-Object { $_.Window.IsVisible } | Sort-Object TaskNumber)
    if ($entries.Count -eq 0) { return }
    $hud.UpdateLayout()
    $work = [Windows.SystemParameters]::WorkArea
    $gap = 8.0
    $isBottom = ([string]$config.position).StartsWith('bottom') -or ([string]$config.position -eq 'custom' -and ($hud.Top + ($hud.ActualHeight / 2)) -gt ($work.Top + ($work.Height / 2)))
    $isLeft = ([string]$config.position).EndsWith('left') -or ([string]$config.position -eq 'custom' -and ($hud.Left + ($hud.ActualWidth / 2)) -lt ($work.Left + ($work.Width / 2)))
    $cursorY = if ($isBottom) { $hud.Top - $gap } else { $hud.Top + $hud.ActualHeight + $gap }
    $columnOffset = 0.0
    $columnWidth = 0.0
    foreach ($entry in $entries) {
        $entry.Window.UpdateLayout()
        $width = [Math]::Max(220, $entry.Window.ActualWidth)
        $height = [Math]::Max(54, $entry.Window.ActualHeight)
        $columnWidth = [Math]::Max($columnWidth, $width)
        if ($isBottom) {
            $top = $cursorY - $height
            if ($top -lt ($work.Top + 12)) {
                $columnOffset += ($columnWidth + $gap)
                $columnWidth = $width
                $cursorY = $work.Bottom - 12
                $top = $cursorY - $height
            }
            $cursorY = $top - $gap
        } else {
            $top = $cursorY
            if (($top + $height) -gt ($work.Bottom - 12)) {
                $columnOffset += ($columnWidth + $gap)
                $columnWidth = $width
                $cursorY = $work.Top + 12
                $top = $cursorY
            }
            $cursorY = $top + $height + $gap
        }
        $left = if ($isLeft) { $hud.Left + $columnOffset } else { $hud.Left + $hud.ActualWidth - $width - $columnOffset }
        $entry.Window.Left = [Math]::Max($work.Left + 12, [Math]::Min($left, $work.Right - $width - 12))
        $entry.Window.Top = $top
    }
}

function Close-TaskBubble {
    param([string]$Path)
    if (-not $splitWindows.ContainsKey($Path)) { return }
    $entry = $splitWindows[$Path]
    $entry.InternalClosing = $true
    try { $entry.Window.Close() } catch { }
    $splitWindows.Remove($Path)
    if ($sessionStates.ContainsKey($Path)) { $sessionStates[$Path].Detached = $false }
}

function Show-TaskBubble {
    param($State)
    $path = [string]$State.Path
    if ($splitWindows.ContainsKey($path)) { Update-TaskBubble $State; return }
    $window = Load-XamlWindow (Join-Path $PSScriptRoot 'TaskBubbleWindow.xaml')
    Set-HudWindowIcon $window
    $entry = [pscustomobject]@{
        Path = $path
        TaskNumber = [int]$State.Number
        Window = $window
        Shell = Find-Control $window 'TaskBubbleShell'
        Dot = Find-Control $window 'TaskBubbleStatusDot'
        NumberBadge = Find-Control $window 'TaskBubbleNumberBadge'
        Number = Find-Control $window 'TaskBubbleNumber'
        Name = Find-Control $window 'TaskBubbleName'
        Metrics = Find-Control $window 'TaskBubbleMetrics'
        Merge = Find-Control $window 'TaskBubbleMergeButton'
        Dismiss = Find-Control $window 'TaskBubbleDismissButton'
        Resize = Find-Control $window 'TaskBubbleResizeThumb'
        Handle = [IntPtr]::Zero
        BaseStyle = $null
        InternalClosing = $false
        LastAttentionRevision = 0
        LastExitRevision = 0
    }
    $script:splitWindows[$path] = $entry
    $entryRecord = $entry
    $taskPath = $path
    $splitWindowMap = $script:splitWindows
    $sessionStateMap = $sessionStates
    $window.Add_SourceInitialized(({ $entryRecord.Handle=(New-Object Windows.Interop.WindowInteropHelper($entryRecord.Window)).Handle;if($entryRecord.Handle-ne[IntPtr]::Zero){$entryRecord.BaseStyle=[HudNativeMethods]::GetWindowLong($entryRecord.Handle,-20);Set-WindowMousePassthrough $entryRecord.Handle $entryRecord.BaseStyle ([bool]$config.mousePassthrough)} }).GetNewClosure())
    $entry.Merge.Add_Click(({ Set-SessionDetached $taskPath $false }).GetNewClosure())
    $entry.Dismiss.Add_Click(({ Dismiss-HudTask $taskPath }).GetNewClosure())
    $entry.Resize.Add_DragDelta(({ param($sender,$eventArgs)
        $currentWidth = [Math]::Max(280.0, [double]$entryRecord.Window.ActualWidth)
        $currentHeight = [Math]::Max(84.0, [double]$entryRecord.Window.ActualHeight)
        if ($entryRecord.Window.SizeToContent -ne [Windows.SizeToContent]::Manual) {
            $entryRecord.Window.SizeToContent = [Windows.SizeToContent]::Manual
            $entryRecord.Window.Width = $currentWidth
            $entryRecord.Window.Height = $currentHeight
        }
        $entryRecord.Window.Width = [Math]::Max(280.0, [Math]::Min(960.0, [double]$entryRecord.Window.Width + [double]$eventArgs.HorizontalChange))
        $entryRecord.Window.Height = [Math]::Max(84.0, [Math]::Min(360.0, [double]$entryRecord.Window.Height + [double]$eventArgs.VerticalChange))
        if ($sessionStateMap.ContainsKey($taskPath)) {
            $sessionStateMap[$taskPath].BubbleWidth = [double]$entryRecord.Window.Width
            $sessionStateMap[$taskPath].BubbleHeight = [double]$entryRecord.Window.Height
        }
        Position-TaskBubbles
    }).GetNewClosure())
    $window.Add_Closed(({ if($splitWindowMap.ContainsKey($taskPath)){ $record=$splitWindowMap[$taskPath];if(-not$record.InternalClosing-and$sessionStateMap.ContainsKey($taskPath)){$sessionStateMap[$taskPath].Detached=$false};$splitWindowMap.Remove($taskPath)} }).GetNewClosure())
    $State.Detached = $true
    if ([double]$State.BubbleWidth -gt 0 -and [double]$State.BubbleHeight -gt 0) {
        $window.SizeToContent = [Windows.SizeToContent]::Manual
        $window.Width = [Math]::Max(280.0, [Math]::Min(960.0, [double]$State.BubbleWidth))
        $window.Height = [Math]::Max(84.0, [Math]::Min(360.0, [double]$State.BubbleHeight))
    }
    Update-TaskBubble $State
    $window.Show()
    Position-TaskBubbles
}

function Set-SessionDetached {
    param([string]$Path, [bool]$Detached)
    if (-not $sessionStates.ContainsKey($Path)) { return }
    $state = $sessionStates[$Path]
    if ($Detached) {
        if (-not $splitWindows.ContainsKey($Path) -and $splitWindows.Count -ge [int]$config.multiTask.maxSplitBubbles) { return }
        Show-TaskBubble $state
    } else { Close-TaskBubble $Path }
    Render-TaskList
}

function Dismiss-HudTask {
    param([string]$Path)
    if (-not $sessionStates.ContainsKey($Path)) { return }
    $sessionStates[$Path].Dismissed = $true
    Close-TaskBubble $Path
    Update-DisplaySnapshot
}

function Merge-AllTaskBubbles {
    foreach ($path in @($splitWindows.Keys)) { Close-TaskBubble ([string]$path) }
    $config.multiTask.displayMode = 'summary'
    Save-HudConfig $paths $config
    Render-Hud
    Update-ContextMenuText
}

function Split-AllTaskBubbles {
    $config.multiTask.displayMode = 'split'
    $states = @(Get-HudUserTaskStates | Sort-Object LastWriteTimeUtc -Descending)
    foreach ($state in $states | Select-Object -First ([int]$config.multiTask.maxSplitBubbles)) { Show-TaskBubble $state }
    Save-HudConfig $paths $config
    Render-Hud
    Update-ContextMenuText
}

function Set-MultiTaskDisplayMode {
    param([ValidateSet('summary','list','split')][string]$Mode)
    if ($Mode -eq 'summary') { Merge-AllTaskBubbles; return }
    if ($Mode -eq 'list' -and [string]$config.multiTask.displayMode -eq 'split') {
        foreach ($path in @($splitWindows.Keys)) { Close-TaskBubble ([string]$path) }
    }
    $config.multiTask.displayMode = $Mode
    if ($Mode -eq 'split') { Split-AllTaskBubbles; return }
    Save-HudConfig $paths $config
    Render-Hud
    Update-ContextMenuText
}

function New-HudTaskActionIcon {
    param([bool]$Merge)
    $icon = New-Object Windows.Shapes.Path
    $icon.Width = 13
    $icon.Height = 13
    $icon.Stretch = [Windows.Media.Stretch]::Uniform
    $icon.Stroke = New-HudRoleBrush ([string]$config.accent) '#FF0A84FF' 'primary'
    $icon.StrokeThickness = 1.35
    $icon.StrokeStartLineCap = [Windows.Media.PenLineCap]::Round
    $icon.StrokeEndLineCap = [Windows.Media.PenLineCap]::Round
    $icon.StrokeLineJoin = [Windows.Media.PenLineJoin]::Round
    $icon.Data = [Windows.Media.Geometry]::Parse($(if ($Merge) {
        'M1.5,1.5 L10.5,1.5 L10.5,10.5 L1.5,10.5 Z M9.1,2.9 L4.1,7.9 M4.1,4.8 L4.1,7.9 L7.2,7.9'
    } else {
        'M1.5,4.5 L1.5,10.5 L7.5,10.5 M5.2,1.5 L10.5,1.5 L10.5,6.8 M10.2,1.8 L4.5,7.5'
    }))
    return $icon
}

function New-HudDismissIcon {
    $icon = New-Object Windows.Shapes.Path
    $icon.Width = 12
    $icon.Height = 12
    $icon.Stretch = [Windows.Media.Stretch]::Uniform
    $icon.Stroke = New-HudRoleBrush ([string]$config.muted) '#FF667085' 'secondary'
    $icon.StrokeThickness = 1.45
    $icon.StrokeStartLineCap = [Windows.Media.PenLineCap]::Round
    $icon.StrokeEndLineCap = [Windows.Media.PenLineCap]::Round
    $icon.Data = [Windows.Media.Geometry]::Parse('M2.5,2.5 L9.5,9.5 M9.5,2.5 L2.5,9.5')
    return $icon
}

function Get-TaskListDensityMetrics {
    switch ([string]$config.multiTask.listDensity) {
        'relaxed' {
            return [pscustomobject]@{
                RowMargin = New-Object Windows.Thickness(0,2,0,2); DotMargin = New-Object Windows.Thickness(8,0,8,0)
                BadgePadding = New-Object Windows.Thickness(7,4,7,4); BadgeMargin = New-Object Windows.Thickness(0,4,7,4); BadgeRadius = 8
                ActionSize = 30; ActionMargin = New-Object Windows.Thickness(8,3,4,3)
                CardPadding = New-Object Windows.Thickness(7,4,7,4); CardMargin = New-Object Windows.Thickness(0,4,0,4); CardRadius = 13
                MetricsMargin = New-Object Windows.Thickness(0,0,8,7); RailMargin = New-Object Windows.Thickness(0,3,0,3); RailInnerMargin = New-Object Windows.Thickness(0,3,0,3); RailContentLeft = 7
            }
        }
        'balanced' {
            return [pscustomobject]@{
                RowMargin = New-Object Windows.Thickness(0,1,0,1); DotMargin = New-Object Windows.Thickness(7,0,7,0)
                BadgePadding = New-Object Windows.Thickness(6,3,6,3); BadgeMargin = New-Object Windows.Thickness(0,2,6,2); BadgeRadius = 8
                ActionSize = 28; ActionMargin = New-Object Windows.Thickness(6,1,3,1)
                CardPadding = New-Object Windows.Thickness(6,3,6,3); CardMargin = New-Object Windows.Thickness(0,2,0,2); CardRadius = 12
                MetricsMargin = New-Object Windows.Thickness(0,0,7,5); RailMargin = New-Object Windows.Thickness(0,2,0,2); RailInnerMargin = New-Object Windows.Thickness(0,2,0,2); RailContentLeft = 6
            }
        }
        default {
            return [pscustomobject]@{
                RowMargin = New-Object Windows.Thickness(0,0,0,0); DotMargin = New-Object Windows.Thickness(6,0,6,0)
                BadgePadding = New-Object Windows.Thickness(6,2,6,2); BadgeMargin = New-Object Windows.Thickness(0,1,6,1); BadgeRadius = 7
                ActionSize = 26; ActionMargin = New-Object Windows.Thickness(5,0,2,0)
                CardPadding = New-Object Windows.Thickness(5,2,5,2); CardMargin = New-Object Windows.Thickness(0,1,0,1); CardRadius = 11
                MetricsMargin = New-Object Windows.Thickness(0,0,6,3); RailMargin = New-Object Windows.Thickness(0,1,0,1); RailInnerMargin = New-Object Windows.Thickness(0,2,0,2); RailContentLeft = 6
            }
        }
    }
}

function Render-TaskList {
    $taskListPanel.Children.Clear()
    $density = Get-TaskListDensityMetrics
    $states = @(Get-HudUserTaskStates | Sort-Object Number)
    $visible = ([string]$config.multiTask.displayMode -eq 'list')
    $taskListScroller.Visibility = if ($visible -and $states.Count -gt 0) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    $taskListDivider.Visibility = $taskListScroller.Visibility
    if (-not $visible) { return }
    foreach ($state in $states) {
        $path = [string]$state.Path
        $row = New-Object Windows.Controls.Grid
        $row.Margin = $density.RowMargin
        $row.Background = New-HudRoleBrush '#08000000' '#08000000' 'decoration'
        $gridLengthConverter = New-Object Windows.GridLengthConverter
        foreach($width in @('Auto','Auto','Auto','*','Auto','Auto')) {
            $column = New-Object Windows.Controls.ColumnDefinition
            $column.Width = $gridLengthConverter.ConvertFromString($width)
            $row.ColumnDefinitions.Add($column)
        }
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width=7;$dot.Height=7;$dot.Margin=$density.DotMargin;$dot.VerticalAlignment='Center';$dot.Fill=New-HudBrush ([string]$config.statusColors.(Get-TaskStatus $state)) '#FF8E8E93'
        [Windows.Controls.Grid]::SetColumn($dot,0);[void]$row.Children.Add($dot)
        $badge=New-Object Windows.Controls.Border;$badge.CornerRadius=New-Object Windows.CornerRadius([double]$density.BadgeRadius);$badge.Background=New-HudBrush '#120A84FF';$badge.Padding=$density.BadgePadding;$badge.Margin=$density.BadgeMargin;$badge.ToolTip=Get-TaskDisplayName $state -IncludeNumber
        $badgeText=New-Object Windows.Controls.TextBlock;$badgeText.Text=('#{0}'-f[int]$state.Number);$badgeText.FontWeight='SemiBold';$badgeText.Foreground=New-HudRoleBrush ([string]$config.accent) '#FF0A84FF' 'primary';$badge.Child=$badgeText
        [Windows.Controls.Grid]::SetColumn($badge,1);[void]$row.Children.Add($badge)
        $projectName = Get-TaskBaseIdentity $state
        $fullName = Get-TaskDisplayName $state
        $name=New-Object Windows.Controls.TextBlock;$name.Text=if([string]$config.multiTask.nameMode-eq'always'){$fullName}else{$projectName};$name.VerticalAlignment='Center';$name.Margin=New-Object Windows.Thickness(0,0,10,0);$name.MaxWidth=260;$name.TextTrimming=[Windows.TextTrimming]::CharacterEllipsis;$name.ToolTip=$fullName;$name.Foreground=New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary'
        $name.Visibility=[Windows.Visibility]::Visible
        [Windows.Controls.Grid]::SetColumn($name,2);[void]$row.Children.Add($name)
        if([string]$config.multiTask.nameMode-eq'hover'){$row.Add_MouseEnter(({ $name.Text=$fullName }).GetNewClosure());$row.Add_MouseLeave(({ $name.Text=$projectName }).GetNewClosure())}
        $metrics=New-Object Windows.Controls.TextBlock;$metrics.Text=Get-TaskMetricsText $state -Surface list;$metrics.VerticalAlignment='Center';$metrics.Foreground=New-HudRoleBrush ([string]$config.muted) '#FF667085' 'secondary';$metrics.TextTrimming='CharacterEllipsis'
        [Windows.Controls.Grid]::SetColumn($metrics,3);[void]$row.Children.Add($metrics)
        $action=New-Object Windows.Controls.Button;$action.Content=New-HudTaskActionIcon ([bool]$state.Detached);$action.Style=$hud.FindResource('HudIconButton');$action.Width=[double]$density.ActionSize;$action.Height=[double]$density.ActionSize;$action.Tag=$path;$action.Margin=$density.ActionMargin;$action.ToolTip=if([bool]$state.Detached){[string]$settingsLocale.mergeTask}else{[string]$settingsLocale.detachTask}
        $action.Add_Click(({ Set-SessionDetached $path (-not [bool]$sessionStates[$path].Detached) }).GetNewClosure())
        [Windows.Controls.Grid]::SetColumn($action,4);[void]$row.Children.Add($action)
        $dismiss=New-Object Windows.Controls.Button;$dismiss.Content=New-HudDismissIcon;$dismiss.Style=$hud.FindResource('HudIconButton');$dismiss.Width=[double]$density.ActionSize;$dismiss.Height=[double]$density.ActionSize;$dismiss.Tag=$path;$dismiss.Margin=New-Object Windows.Thickness(1,0,2,0);$dismiss.ToolTip=[string]$settingsLocale.dismissTask
        $dismiss.Add_Click(({ Dismiss-HudTask $path }).GetNewClosure())
        [Windows.Controls.Grid]::SetColumn($dismiss,5);[void]$row.Children.Add($dismiss)
        $listItem = $row
        switch ([string]$config.multiTask.listStyle) {
            'cards' {
                $row.Background = [Windows.Media.Brushes]::Transparent
                $row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
                $row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
                [Windows.Controls.Grid]::SetRowSpan($dot,2)
                [Windows.Controls.Grid]::SetRow($metrics,1)
                [Windows.Controls.Grid]::SetColumn($metrics,1)
                [Windows.Controls.Grid]::SetColumnSpan($metrics,3)
                $metrics.Margin = $density.MetricsMargin
                $metrics.TextWrapping = [Windows.TextWrapping]::Wrap
                $card = New-Object Windows.Controls.Border
                $card.CornerRadius = New-Object Windows.CornerRadius([double]$density.CardRadius)
                $card.Padding = $density.CardPadding
                $card.Margin = $density.CardMargin
                $card.Background = New-HudRoleBrush '#0D0A84FF' '#0D0A84FF' 'decoration'
                $card.BorderBrush = New-HudRoleBrush '#220A84FF' '#220A84FF' 'decoration'
                $card.BorderThickness = New-Object Windows.Thickness(1)
                $card.Child = $row
                $listItem = $card
            }
            'rail' {
                $row.Background = [Windows.Media.Brushes]::Transparent
                $dot.Visibility = [Windows.Visibility]::Collapsed
                $railGrid = New-Object Windows.Controls.Grid
                $railGrid.Margin = $density.RailMargin
                $railGrid.Background = New-HudRoleBrush '#08000000' '#08000000' 'decoration'
                $railColumn = New-Object Windows.Controls.ColumnDefinition
                $railColumn.Width = [Windows.GridLength]::new(4)
                [void]$railGrid.ColumnDefinitions.Add($railColumn)
                $contentColumn = New-Object Windows.Controls.ColumnDefinition
                $contentColumn.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
                [void]$railGrid.ColumnDefinitions.Add($contentColumn)
                $rail = New-Object Windows.Controls.Border
                $rail.CornerRadius = New-Object Windows.CornerRadius(2)
                $rail.Margin = $density.RailInnerMargin
                $rail.Background = New-HudBrush ([string]$config.statusColors.(Get-TaskStatus $state)) '#FF8E8E93'
                [Windows.Controls.Grid]::SetColumn($rail,0)
                [void]$railGrid.Children.Add($rail)
                $row.Margin = New-Object Windows.Thickness([double]$density.RailContentLeft,0,0,0)
                [Windows.Controls.Grid]::SetColumn($row,1)
                [void]$railGrid.Children.Add($row)
                $listItem = $railGrid
            }
        }
        $attentionSurface = New-Object Windows.Controls.Border
        $attentionSurface.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(9,[double]$density.CardRadius))
        $attentionSurface.BorderThickness = New-Object Windows.Thickness(0)
        $attentionSurface.Child = $listItem
        [void]$taskListPanel.Children.Add($attentionSurface)
        if ([int]$state.AttentionRevision -gt [int]$state.LastListAttentionRevision) {
            $state.LastListAttentionRevision = [int]$state.AttentionRevision
            if (-not [bool]$state.Detached -and $state.AttentionUntil -gt [DateTimeOffset]::Now) {
                Write-HudDebug ('Attention surface: list {0} r{1} reason={2}' -f [string]$state.Workspace,[int]$state.AttentionRevision,[string]$state.AttentionReason)
                if ([string]$state.AttentionReason -eq 'agent') { Start-HudAgentAnimation $attentionSurface $state.AgentNoticeRecipe }
                else { Start-HudAttentionAnimation $dot $attentionSurface ([string]$config.attention.listMode) }
            }
        }
        if ([int]$state.TerminalExitRevision -gt [int]$state.LastListExitRevision -and $state.TerminalExitUntil -gt [DateTimeOffset]::Now) {
            $state.LastListExitRevision = [int]$state.TerminalExitRevision
            Write-HudDebug ('Terminal exit surface: list {0} r{1}' -f [string]$state.Workspace,[int]$state.TerminalExitRevision)
            Start-HudTerminalExitAnimation $attentionSurface ([string]$config.statusTiming.terminalExitMode) ([string]$config.statusColors.(Get-TaskStatus $state))
        }
    }
}

function Get-HudStatus {
    if ($paused) { return 'paused' }
    $taskStatuses = @(Get-HudUserTaskStates | ForEach-Object { Get-TaskStatus $_ })
    if ($taskStatuses -contains 'aborted') { return 'aborted' }
    if ($taskStatuses -contains 'completed') { return 'completed' }
    $errorAge = ([DateTimeOffset]::Now - $lastReadErrorAt).TotalSeconds
    if ($lastReadErrorAt -ne [DateTimeOffset]::MinValue -and $errorAge -le [double]$config.statusTiming.errorHoldSeconds) { return 'error' }
    if ($null -eq $snapshot) { return 'idle' }
    $reference = if ($lastUsageAt -ne [DateTimeOffset]::MinValue) { $lastUsageAt } else { [DateTimeOffset]$snapshot.Timestamp }
    $age = ([DateTimeOffset]::Now - $reference).TotalSeconds
    if ($age -le [double]$config.statusTiming.activeSeconds) { return 'active' }
    if ($age -le [double]$config.statusTiming.idleSeconds) { return 'listening' }
    return 'idle'
}

function Get-StatusBilingual {
    param([string]$Status)
    $keys = @{ active='statusActive'; listening='statusListening'; idle='statusIdle'; paused='statusPaused'; error='statusError'; completed='statusCompleted'; aborted='statusAborted' }
    $key = [string]$keys[$Status]
    $zh = Get-HudLocale $paths 'zh-CN'
    $en = Get-HudLocale $paths 'en'
    return ('{0} ({1})' -f [string]$zh.$key, [string]$en.$key)
}

function Update-ContextMenuText {
    foreach($pair in @(
        @('settingsItem','openSettings'),
        @('passthroughItem',$(if([bool]$config.mousePassthrough){'disableMousePassthrough'}else{'enableMousePassthrough'})),
        @('pauseItem',$(if($paused){'resume'}else{'pause'})),
        @('positionItem','resetPosition'),
        @('viewModeItem','displayMode'),
        @('summaryModeItem','showSummary'),
        @('listModeItem','showTaskList'),
        @('splitModeItem','splitAll'),
        @('mergeAllItem','mergeAll'),
        @('exitItem','exit')
    )){
        $variable=Get-Variable -Name $pair[0] -Scope Script -ErrorAction SilentlyContinue
        if($null-ne$variable -and $null-ne$variable.Value){$variable.Value.Header=Get-BilingualText ([string]$pair[1])}
    }
    if ($null -ne $summaryModeItem) { $summaryModeItem.IsChecked = [string]$config.multiTask.displayMode -eq 'summary' }
    if ($null -ne $listModeItem) { $listModeItem.IsChecked = [string]$config.multiTask.displayMode -eq 'list' }
    if ($null -ne $splitModeItem) { $splitModeItem.IsChecked = [string]$config.multiTask.displayMode -eq 'split' }
    $statusVariable=Get-Variable -Name statusItem -Scope Script -ErrorAction SilentlyContinue
    if($null-ne$statusVariable -and $null-ne$statusVariable.Value){
        $zh = Get-HudLocale $paths 'zh-CN'
        $en = Get-HudLocale $paths 'en'
        $statusVariable.Value.Header = ('{0} / {1}: {2}' -f [string]$zh.statusLabel, [string]$en.statusLabel, (Get-StatusBilingual (Get-HudStatus)))
    }
    Update-HudTrayMenu
}

function Update-HudTrayMenu {
    if ($null -eq $trayIcon) { return }
    $trayZh = Get-HudLocale $paths 'zh-CN'
    $trayEn = Get-HudLocale $paths 'en'
    $trayStatusItem.Text = ('{0} / {1}: {2}' -f [string]$trayZh.statusLabel, [string]$trayEn.statusLabel, (Get-StatusBilingual (Get-HudStatus)))
    $trayOpenSettingsItem.Text = ('{0} / {1}' -f [string]$trayZh.openSettings, [string]$trayEn.openSettings)
    $trayViewModeItem.Text = ('{0} / {1}' -f [string]$trayZh.displayMode, [string]$trayEn.displayMode)
    $traySummaryModeItem.Text = ('{0} / {1}' -f [string]$trayZh.showSummary, [string]$trayEn.showSummary)
    $trayListModeItem.Text = ('{0} / {1}' -f [string]$trayZh.showTaskList, [string]$trayEn.showTaskList)
    $traySplitModeItem.Text = ('{0} / {1}' -f [string]$trayZh.splitAll, [string]$trayEn.splitAll)
    $trayMergeAllItem.Text = ('{0} / {1}' -f [string]$trayZh.mergeAll, [string]$trayEn.mergeAll)
    $traySummaryModeItem.Checked = [string]$config.multiTask.displayMode -eq 'summary'
    $trayListModeItem.Checked = [string]$config.multiTask.displayMode -eq 'list'
    $traySplitModeItem.Checked = [string]$config.multiTask.displayMode -eq 'split'
    $trayDisablePassthroughItem.Text = ('{0} / {1}' -f [string]$trayZh.disableMousePassthrough, [string]$trayEn.disableMousePassthrough)
    $trayDisablePassthroughItem.Enabled = [bool]$config.mousePassthrough
    $trayExitItem.Text = ('{0} HUD / {1} HUD' -f [string]$trayZh.exit, [string]$trayEn.exit)
    $trayIcon.Text = if ([bool]$config.mousePassthrough) { 'Codex Monitor HUD - click-through ON' } else { 'Codex Monitor HUD - monitoring' }
}

function Disable-HudMousePassthrough {
    if (-not [bool]$config.mousePassthrough) { return }
    $config.mousePassthrough = $false
    Save-HudConfig $paths $config
    Sync-ControlsFromConfig
    Apply-HudAppearance
    Update-ContextMenuText
}

function Set-WindowMousePassthrough {
    param([IntPtr]$Handle, $BaseStyle, [bool]$Enabled)
    if ($Handle -eq [IntPtr]::Zero) { return }
    $gwlExStyle = -20
    $wsExTransparent = 0x00000020
    $wsExNoActivate = 0x08000000
    $current = [HudNativeMethods]::GetWindowLong($Handle, $gwlExStyle)
    if ($null -eq $BaseStyle) { $BaseStyle = $current }
    if ($Enabled) {
        $next = $current -bor $wsExTransparent -bor $wsExNoActivate
    } else {
        $next = $current
        if (($BaseStyle -band $wsExTransparent) -eq 0) { $next = $next -band (-bnot $wsExTransparent) }
        if (($BaseStyle -band $wsExNoActivate) -eq 0) { $next = $next -band (-bnot $wsExNoActivate) }
    }
    if ($next -ne $current) { [void][HudNativeMethods]::SetWindowLong($Handle, $gwlExStyle, $next) }
}

function Set-HudMousePassthrough {
    param([bool]$Enabled)
    Set-WindowMousePassthrough $hudHandle $hudBaseExtendedStyle $Enabled
    foreach ($entry in @($splitWindows.Values)) {
        Set-WindowMousePassthrough $entry.Handle $entry.BaseStyle $Enabled
    }
}

function Add-HudAgentNotice {
    param($State)
    $noticeText = Get-HudAgentNoticeText $State
    if ([string]::IsNullOrWhiteSpace($noticeText)) { return }
    $card = New-Object Windows.Controls.Border
    $card.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(8,[double]$config.cornerRadius-8))
    $card.Padding = New-Object Windows.Thickness(10,6,10,6)
    $card.Margin = New-Object Windows.Thickness(7,0,0,0)
    $card.BorderThickness = New-Object Windows.Thickness(1)
    $card.BorderBrush = New-HudBrush ([string]$config.agentNotifications.color) '#FF7C3AED'
    $card.Background = New-HudRoleBrush '#167C3AED' '#167C3AED' 'decoration'
    $text = New-Object Windows.Controls.TextBlock
    $text.Text = ('✦ {0}' -f $noticeText)
    $text.TextWrapping = [Windows.TextWrapping]::Wrap
    $text.MaxWidth = 430
    $text.FontWeight = [Windows.FontWeights]::SemiBold
    $text.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FFF7FBFF' 'primary'
    $card.Child = $text
    [void]$metricsPanel.Children.Add($card)
}

function Process-HudAgentNotifications {
    $changed = $false
    if (-not (Test-Path -LiteralPath $notificationsRoot)) { return $false }
    foreach ($file in @(Get-ChildItem -LiteralPath $notificationsRoot -File -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc)) {
        if (-not [bool]$config.agentNotifications.enabled) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            continue
        }
        if ($file.Length -gt 8192) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue; continue }
        try {
            $notice = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
            if ([string]$notice.source -ne 'codex-mcp') { throw 'Unsupported notification source.' }
            $message = [regex]::Replace([string]$notice.message,'[\x00-\x1F\x7F]+',' ')
            $message = [regex]::Replace($message,'\s+',' ').Trim()
            if ($message.Length -gt 160) { $message = $message.Substring(0,160) }
            if ([string]::IsNullOrWhiteSpace($message)) { throw 'Empty notification.' }
            $target = $null
            $requestedNumber = 0
            if ($null -ne $notice.PSObject.Properties['task_number'] -and $null -ne $notice.task_number) { $requestedNumber = [int]$notice.task_number }
            $visibleTargets = @(Get-HudUserTaskStates)
            if ($requestedNumber -gt 0) { $target = $visibleTargets | Where-Object { [int]$_.Number -eq $requestedNumber } | Select-Object -First 1 }
            elseif ($visibleTargets.Count -gt 0) { $target = $visibleTargets | Sort-Object LastUsageAt,LastWriteTimeUtc -Descending | Select-Object -First 1 }
            if ($null -eq $target) {
                if (([DateTime]::UtcNow - $file.CreationTimeUtc).TotalSeconds -gt 60) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
                continue
            }
            $requestedRecipe = if ([string]$config.agentNotifications.permission -eq 'expressive' -and $null -ne $notice.PSObject.Properties['animation']) { $notice.animation } else { $null }
            $target.AgentNoticeText = $message
            $target.AgentNoticeRecipe = $requestedRecipe
            $target.AgentNoticeUntil = [DateTimeOffset]::Now.AddSeconds([int]$config.agentNotifications.durationSeconds)
            $script:attentionSequence++
            $target.AttentionRevision = $attentionSequence
            $target.AttentionReason = 'agent'
            $target.AttentionUntil = $target.AgentNoticeUntil
            if (-not [string]::IsNullOrWhiteSpace([string]$target.TerminalStatus)) { Reset-TerminalExitState $target }
            Write-HudDebug ('Agent notice accepted for task #{0}; expressive={1}' -f [int]$target.Number,([string]$config.agentNotifications.permission -eq 'expressive'))
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $changed = $true
        } catch {
            Write-HudDebug ('Agent notice rejected: ' + $_.Exception.Message)
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    return $changed
}

function Apply-HudAppearance {
    $script:locale = Get-HudLocale $paths ([string]$config.language)
    $hud.Topmost = [bool]$config.alwaysOnTop
    try { $hud.FontFamily = New-Object Windows.Media.FontFamily([string]$config.themeStyle.fontFamily) } catch { }
    Set-HudMousePassthrough ([bool]$config.mousePassthrough)
    $hud.Opacity = if ([string]$config.transparencyMode -eq 'uniform') { [double]$config.opacity } else { 1.0 }
    $hudShell.CornerRadius = New-Object Windows.CornerRadius([double]$config.cornerRadius)
    $summaryFlowActive = @(Get-HudUserTaskStates | Where-Object { $_.AttentionUntil -gt [DateTimeOffset]::Now -and ([string]$config.attention.summaryMode -eq 'flow' -or [string]$_.AttentionReason -eq 'agent') }).Count -gt 0
    if (-not $summaryFlowActive) {
        $hudShell.BorderBrush = New-HudRoleBrush ([string]$config.border) '#22FFFFFF' 'decoration'
        $hudShell.BorderThickness = New-Object Windows.Thickness([double]$config.themeStyle.borderWidth)
    }
    $hudShell.Background = New-HudSurfaceBrush
    $script:currentStatus = Get-HudStatus
    $statusColor = [string]$config.statusColors.$currentStatus
    $statusDot.Fill = New-HudBrush $statusColor '#FF8E8E93'
    $statusDot.Width = [double]$config.themeStyle.statusDotSize
    $statusDot.Height = [double]$config.themeStyle.statusDotSize
    $statusDot.ToolTip = Get-StatusBilingual $currentStatus
    $statusDot.Visibility = if ([bool]$config.showStatusDot) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    $metricsPanel.Orientation = if ([string]$config.layout -eq 'stacked') { [Windows.Controls.Orientation]::Vertical } else { [Windows.Controls.Orientation]::Horizontal }
    $hudShell.Padding = if ([string]$config.layout -eq 'stacked') { New-Object Windows.Thickness(16, 13, 16, 13) } else { New-Object Windows.Thickness(14, 10, 14, 10) }
}

function Render-Hud {
    Apply-HudAppearance
    $metricsPanel.Children.Clear()
    if ($paused -or $null -eq $snapshot) {
        Add-WaitingMetric
    } else {
        $metrics = @(Get-HudMetrics $snapshot $config $locale)
        if ($metrics.Count -eq 0) { Add-WaitingMetric } else {
            foreach ($metric in $metrics) { Add-HudMetric $metric }
        }
    }
    if ([string]$config.multiTask.displayMode -eq 'summary') {
        $summaryNotice = Get-HudUserTaskStates | Where-Object { $_.AgentNoticeUntil -gt [DateTimeOffset]::Now -and -not [string]::IsNullOrWhiteSpace([string]$_.AgentNoticeText) } | Sort-Object AttentionRevision -Descending | Select-Object -First 1
        if ($null -ne $summaryNotice) { Add-HudAgentNotice $summaryNotice }
    }
    $taskStates = @(Get-HudUserTaskStates)
    $taskCount = $taskStates.Count
    $taskPhaseSignature = @($taskStates | Sort-Object Number | ForEach-Object {
        $identity = if (-not [string]::IsNullOrWhiteSpace([string]$_.SessionId)) { [string]$_.SessionId } else { [string]$_.Path }
        ('{0}:{1}:{2}:{3}' -f [int]$_.Number,$identity,(Get-TaskStatus $_),[bool]$_.Detached)
    }) -join ';'
    $updateAnimationSignature = ('{0}|{1}|{2}|{3}' -f [string]$config.multiTask.displayMode,$taskCount,[string]$currentStatus,$taskPhaseSignature)
    $taskListToggleButton.Visibility = if ($taskCount -gt 0) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    $taskListToggleButton.Content = ('{0} {1}' -f $taskCount, $(if ([string]$config.multiTask.displayMode -eq 'list') { [char]0x25B4 } else { [char]0x25BE }))
    $taskListToggleButton.ToolTip = [string]$settingsLocale.activeTasks
    Render-TaskList
    foreach ($state in $taskStates) {
        $state.LastRenderedStatus = Get-TaskStatus $state
        if ($splitWindows.ContainsKey([string]$state.Path)) { Update-TaskBubble $state }
    }
    $mainAttention = $taskStates | Where-Object { $_.AttentionUntil -gt [DateTimeOffset]::Now } | Sort-Object AttentionRevision -Descending | Select-Object -First 1
    if ($null -ne $mainAttention -and [int]$mainAttention.AttentionRevision -gt $lastMainAttentionRevision) {
        $script:lastMainAttentionRevision = [int]$mainAttention.AttentionRevision
        if ([string]$config.multiTask.displayMode -eq 'summary') {
            Write-HudDebug ('Attention surface: summary {0} r{1} reason={2}' -f [string]$mainAttention.Workspace,[int]$mainAttention.AttentionRevision,[string]$mainAttention.AttentionReason)
            if ([string]$mainAttention.AttentionReason -eq 'agent') { Start-HudAgentAnimation $hudShell $mainAttention.AgentNoticeRecipe }
            else { Start-HudAttentionAnimation $statusDot $hudShell ([string]$config.attention.summaryMode) }
        }
    }
    $hud.UpdateLayout()
    if ([string]$config.position -ne 'custom') { Move-HudToConfiguredPosition }
    Position-TaskBubbles
    $shouldAnimateUpdate = -not $interactivePreview -and
        -not [string]::IsNullOrWhiteSpace([string]$lastUpdateAnimationSignature) -and
        [string]$lastUpdateAnimationSignature -ne $updateAnimationSignature -and
        $null -eq $mainAttention
    $script:lastUpdateAnimationSignature = $updateAnimationSignature
    if ([bool]$config.animateUpdates -and $shouldAnimateUpdate) {
        Write-HudDebug ('Update animation: ' + $updateAnimationSignature)
        $animation = New-Object Windows.Media.Animation.DoubleAnimation(0.96, 1.0, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(160))))
        $animation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $hudShell.BeginAnimation([Windows.UIElement]::OpacityProperty, $animation)
    }
}

function Export-HudPreview {
    param([Parameter(Mandatory = $true)][string]$Path)
    $script:config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $script:config.language = $PreviewLanguage
    $script:config.layout = $PreviewLayout
    $script:config.multiTask.displayMode = $PreviewHudMode
    $script:config.multiTask.listStyle = $PreviewListStyle
    $script:config.multiTask.listDensity = $PreviewListDensity
    if ($PreviewAttentionMode -ne 'none') {
        $script:config.attention.summaryMode = $PreviewAttentionMode
        $script:config.attention.listMode = $PreviewAttentionMode
        $script:config.attention.taskBubbleMode = $PreviewAttentionMode
    }
    $script:config.transparencyMode = $PreviewTransparencyMode
    if ($PreviewOpacity -gt 0) { $script:config.opacity = [Math]::Max(0.15, [Math]::Min(1.0, $PreviewOpacity)) }
    if ($PreviewFontSize -gt 0) { $script:config.fontSize = [Math]::Round($PreviewFontSize, 1) }
    $script:config.fields.weeklyRemaining = $true
    $script:locale = Get-HudLocale $paths ([string]$config.language)
    $script:settingsLocale = if ([string]$config.language -eq 'symbols') { Get-HudLocale $paths 'en' } else { $locale }
    $script:snapshot = [pscustomobject]@{
        Timestamp = [DateTimeOffset]::Now
        Input = [Int64]128742
        Cached = [Int64]119552
        Uncached = [Int64]9190
        Output = [Int64]1842
        Reasoning = [Int64]614
        CallTotal = [Int64]130584
        TaskTotal = [Int64]4298560
        ContextPercent = 49.8
        ContextWindow = [Int64]258400
        Model = 'gpt-5.6'
        WeeklyRemainingPercent = 60.0
        FiveHourRemainingPercent = 86.0
        ActiveTasks = 4
    }
    $script:sessionStates = @{}
    if ($PreviewHudMode -eq 'list') {
        $workspaces = @('api-gateway','desktop-client','release-checks','docs-refresh')
        $conversationTitles = if ($PreviewLanguage -eq 'zh-CN') {
            @('5L+u5aSN55m75b2V6LaF5pe2','5LyY5YyW5qGM6Z2i5Lqk5LqS','5qC45a+55Y+R5biD5riF5Y2V','5pu05paw5Y+M6K+t5paH5qGj') |
                ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
        } else { @('Fix login timeout','Polish desktop flow','Review release checklist','Update bilingual docs') }
        for ($index = 0; $index -lt $workspaces.Count; $index++) {
            $taskSnapshot = [pscustomobject]@{
                Timestamp = [DateTimeOffset]::Now.AddSeconds(-($index * 14))
                Input = [Int64](28000 + ($index * 4300))
                Cached = [Int64](21000 + ($index * 3500))
                Uncached = [Int64](7000 + ($index * 800))
                Output = [Int64](420 + ($index * 93))
                Reasoning = [Int64](120 + ($index * 31))
                CallTotal = [Int64](28420 + ($index * 4393))
                TaskTotal = [Int64](280000 + ($index * 72000))
                ContextPercent = 28.0 + ($index * 8)
                ContextWindow = [Int64]258400
                Model = if ($index -eq 2) { 'gpt-5.6-mini' } else { 'gpt-5.6' }
                Workspace = $workspaces[$index]
                ConversationLabel = $conversationTitles[$index]
            }
            $pathKey = 'preview-task-' + ($index + 1)
            $script:sessionStates[$pathKey] = [pscustomobject]@{
                Path = $pathKey
                Number = $index + 1
                StartedAt = [DateTimeOffset]::Now.AddMinutes(-42 + ($index * 7))
                Workspace = $workspaces[$index]
                ConversationLabel = $conversationTitles[$index]
                Snapshot = $taskSnapshot
                LastUsageAt = if ($index -lt 2) { [DateTimeOffset]::Now.AddSeconds(-$index) } elseif ($index -eq 2) { [DateTimeOffset]::Now.AddSeconds(-36) } else { [DateTimeOffset]::Now.AddMinutes(-5) }
                LastReadErrorAt = [DateTimeOffset]::MinValue
                LastRenderedStatus = ''
                TerminalStatus = ''
                TerminalAt = [DateTimeOffset]::MinValue
                TerminalSilent = $false
                TerminalExitStarted = $false
                TerminalExitCompleted = $false
                TerminalExitUntil = [DateTimeOffset]::MinValue
                TerminalExitRevision = 0
                HasObservedActivity = $true
                AttentionRevision = if ($PreviewAttentionMode -ne 'none') { $index + 1 } else { 0 }
                AttentionReason = ''
                AttentionUntil = if ($PreviewAttentionMode -ne 'none') { [DateTimeOffset]::Now.AddSeconds([int]$config.attention.durationSeconds) } else { [DateTimeOffset]::MinValue }
                LastListAttentionRevision = 0
                LastListExitRevision = 0
                AgentNoticeText = ''
                AgentNoticeUntil = [DateTimeOffset]::MinValue
                AgentNoticeRecipe = $null
                ActiveTurnId = ''
                PendingCompletionTurnId = ''
                PendingCompletionDueAt = [DateTimeOffset]::MinValue
                LastWriteTimeUtc = [DateTime]::UtcNow.AddSeconds(-($index * 14))
                Detached = $false
                BubbleWidth = 0.0
                BubbleHeight = 0.0
            }
        }
    }
    Render-Hud
    $content = $hud.Content
    $content.Measure((New-Object Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
    $size = $content.DesiredSize
    $content.Arrange((New-Object Windows.Rect(0, 0, $size.Width, $size.Height)))
    $content.UpdateLayout()
    $width = [Math]::Max(1, [int][Math]::Ceiling($size.Width))
    $height = [Math]::Max(1, [int][Math]::Ceiling($size.Height))
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($content)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Create)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

if (-not [string]::IsNullOrWhiteSpace($RenderPreview)) {
    try { Export-HudPreview $RenderPreview } finally { Release-HudMutex }
    exit 0
}

function Assert-HudThemeDefinition {
    param($Theme, [bool]$AllowAssets)
    if ($null -eq $Theme -or [string]$Theme.id -notmatch '^[a-z0-9][a-z0-9-]{1,47}$') { throw 'Theme id must use 2-48 lowercase letters, numbers, or hyphens.' }
    if ($null -eq $Theme.names -or $null -eq $Theme.settings) { throw 'Theme requires names and settings objects.' }
    $allowedSettings = @('background','foreground','muted','accent','border','cornerRadius','opacity','fontSize','layout','separator','transparencyMode','showStatusDot','animateUpdates','themeStyle','multiTask','attention','agentNotification','statusColors')
    foreach ($property in $Theme.settings.PSObject.Properties) {
        if ($allowedSettings -notcontains $property.Name) { throw "Unsupported theme setting: $($property.Name)" }
    }
    foreach ($key in @('background','foreground','muted','accent','border')) {
        if ($null -ne $Theme.settings.PSObject.Properties[$key]) { [void][Windows.Media.ColorConverter]::ConvertFromString([string]$Theme.settings.$key) }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['layout'] -and @('chips','compact','inline','outline','cards','stacked') -notcontains [string]$Theme.settings.layout) { throw 'Unsupported metric layout.' }
    if ($null -ne $Theme.settings.PSObject.Properties['transparencyMode'] -and @('uniform','layered','focus') -notcontains [string]$Theme.settings.transparencyMode) { throw 'Unsupported transparency mode.' }
    if ($null -ne $Theme.settings.PSObject.Properties['themeStyle']) {
        $style = $Theme.settings.themeStyle
        $allowed = @('surface','gradientStart','gradientEnd','gradientAngle','backgroundImage','imageOpacity','imageStretch','shadow','borderWidth','statusDotSize','fontFamily')
        foreach ($property in $style.PSObject.Properties) { if ($allowed -notcontains $property.Name) { throw "Unsupported themeStyle setting: $($property.Name)" } }
        if ($null -ne $style.PSObject.Properties['surface'] -and @('solid','gradient','image') -notcontains [string]$style.surface) { throw 'Unsupported surface style.' }
        foreach ($key in @('gradientStart','gradientEnd')) { if ($null -ne $style.PSObject.Properties[$key]) { [void][Windows.Media.ColorConverter]::ConvertFromString([string]$style.$key) } }
        if ($null -ne $style.PSObject.Properties['imageStretch'] -and @('uniform','uniformToFill','fill','none') -notcontains [string]$style.imageStretch) { throw 'Unsupported image stretch.' }
        if ($null -ne $style.PSObject.Properties['shadow'] -and @('none','soft','deep') -notcontains [string]$style.shadow) { throw 'Unsupported shadow style.' }
        if ($null -ne $style.PSObject.Properties['backgroundImage'] -and -not [string]::IsNullOrWhiteSpace([string]$style.backgroundImage)) {
            $asset = ([string]$style.backgroundImage).Replace('/','\')
            if (-not $AllowAssets) { throw 'Background images must be shipped in a .cmhud-theme.zip package.' }
            if ([IO.Path]::IsPathRooted($asset) -or $asset.Contains('..') -or @('.png','.jpg','.jpeg') -notcontains [IO.Path]::GetExtension($asset).ToLowerInvariant()) { throw 'Theme background image path is unsafe or unsupported.' }
        }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['multiTask']) {
        foreach ($property in $Theme.settings.multiTask.PSObject.Properties) { if (@('listStyle','listDensity','nameMode') -notcontains $property.Name) { throw "Unsupported multiTask skin setting: $($property.Name)" } }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['attention']) {
        foreach ($property in $Theme.settings.attention.PSObject.Properties) { if (@('summaryMode','listMode','taskBubbleMode','dotEnabled','dotPattern','dotBrightness','dotSpeed','dotBreathing') -notcontains $property.Name) { throw "Unsupported attention skin setting: $($property.Name)" } }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['agentNotification']) {
        $agentSkin = $Theme.settings.agentNotification
        foreach ($property in $agentSkin.PSObject.Properties) { if (@('mode','color','glowPreset','intensity') -notcontains $property.Name) { throw "Unsupported agent-notification skin setting: $($property.Name)" } }
        if ($null -ne $agentSkin.PSObject.Properties['mode'] -and @('halo','breathe','flow','focus') -notcontains [string]$agentSkin.mode) { throw 'Unsupported agent-notification mode.' }
        if ($null -ne $agentSkin.PSObject.Properties['glowPreset'] -and @('violet','aqua','amber','custom') -notcontains [string]$agentSkin.glowPreset) { throw 'Unsupported agent-notification glow preset.' }
        if ($null -ne $agentSkin.PSObject.Properties['intensity'] -and @('subtle','balanced','strong') -notcontains [string]$agentSkin.intensity) { throw 'Unsupported agent-notification intensity.' }
        if ($null -ne $agentSkin.PSObject.Properties['color']) { [void][Windows.Media.ColorConverter]::ConvertFromString([string]$agentSkin.color) }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['statusColors']) {
        foreach ($property in $Theme.settings.statusColors.PSObject.Properties) {
            if (@('active','listening','idle','paused','error','completed','aborted') -notcontains $property.Name) { throw "Unsupported status color: $($property.Name)" }
            [void][Windows.Media.ColorConverter]::ConvertFromString([string]$property.Value)
        }
    }
    return $Theme
}

function Apply-HudThemeDefinition {
    param($Theme)
    $defaults = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $config.themeStyle = $defaults.themeStyle
    foreach ($key in @('background','foreground','muted','accent','border','cornerRadius','opacity','fontSize','layout','separator','transparencyMode','showStatusDot','animateUpdates')) {
        if ($null -ne $Theme.settings.PSObject.Properties[$key] -and $null -ne $config.PSObject.Properties[$key]) { $config.$key = $Theme.settings.$key }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['themeStyle']) {
        foreach ($property in $Theme.settings.themeStyle.PSObject.Properties) {
            if ($property.Name -eq 'backgroundImage') { continue }
            if ($null -ne $config.themeStyle.PSObject.Properties[$property.Name]) { $config.themeStyle.($property.Name) = $property.Value }
        }
        $asset = if ($null -ne $Theme.settings.themeStyle.PSObject.Properties['backgroundImage']) { [string]$Theme.settings.themeStyle.backgroundImage } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($asset)) {
            $sourceRoot = Split-Path -Parent ([string]$Theme.SourcePath)
            $candidate = [IO.Path]::GetFullPath((Join-Path $sourceRoot $asset))
            if ($candidate.StartsWith(([IO.Path]::GetFullPath($sourceRoot) + '\'), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $candidate)) {
                $config.themeStyle.backgroundImage = $candidate
                $config.themeStyle.surface = 'image'
            }
        }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['multiTask']) {
        foreach ($key in @('listStyle','listDensity','nameMode')) { if ($null -ne $Theme.settings.multiTask.PSObject.Properties[$key]) { $config.multiTask.$key = $Theme.settings.multiTask.$key } }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['attention']) {
        foreach ($key in @('summaryMode','listMode','taskBubbleMode','dotEnabled','dotPattern','dotBrightness','dotSpeed','dotBreathing')) { if ($null -ne $Theme.settings.attention.PSObject.Properties[$key]) { $config.attention.$key = $Theme.settings.attention.$key } }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['agentNotification']) {
        foreach ($key in @('mode','color','glowPreset','intensity')) { if ($null -ne $Theme.settings.agentNotification.PSObject.Properties[$key]) { $config.agentNotifications.$key = $Theme.settings.agentNotification.$key } }
    }
    if ($null -ne $Theme.settings.PSObject.Properties['statusColors']) {
        foreach ($key in @('active','listening','idle','paused','error','completed','aborted')) { if ($null -ne $Theme.settings.statusColors.PSObject.Properties[$key]) { $config.statusColors.$key = $Theme.settings.statusColors.$key } }
        $config.statusPalette = 'custom'
    }
    $config.preset = [string]$Theme.id
}

function Import-HudThemeFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Theme file was not found.' }
        $userRoot = Join-Path $paths.StateRoot 'themes'
        New-Item -ItemType Directory -Force -Path $userRoot | Out-Null
        $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
        $theme = $null
        if ($extension -eq '.zip') {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [IO.Compression.ZipFile]::OpenRead($Path)
            try {
                $entries = @($zip.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) })
                if ($entries.Count -gt 16 -or ($entries | Measure-Object Length -Sum).Sum -gt 5MB) { throw 'Theme package exceeds 16 files or 5 MB.' }
                $manifest = $entries | Where-Object { [string]$_.FullName -ieq 'theme.json' } | Select-Object -First 1
                if ($null -eq $manifest) { throw 'Theme package requires theme.json at its root.' }
                $reader = New-Object IO.StreamReader($manifest.Open(), [Text.Encoding]::UTF8)
                try { $theme = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
                [void](Assert-HudThemeDefinition $theme $true)
                $destination = Join-Path $userRoot ([string]$theme.id)
                New-Item -ItemType Directory -Force -Path $destination | Out-Null
                $destinationFull = [IO.Path]::GetFullPath($destination) + '\'
                foreach ($entry in $entries) {
                    $relative = ([string]$entry.FullName).Replace('/','\')
                    $isManifest = $relative -ieq 'theme.json'
                    $isAsset = $relative.StartsWith('assets\',[StringComparison]::OrdinalIgnoreCase) -and @('.png','.jpg','.jpeg') -contains [IO.Path]::GetExtension($relative).ToLowerInvariant()
                    if (-not $isManifest -and -not $isAsset) { throw "Unsupported package entry: $relative" }
                    if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..') -or $relative.Contains(':') -or $entry.Length -gt 3MB) { throw "Unsafe or oversized package entry: $relative" }
                    $target = [IO.Path]::GetFullPath((Join-Path $destination $relative))
                    if (-not $target.StartsWith($destinationFull,[StringComparison]::OrdinalIgnoreCase)) { throw 'Theme package path escaped its install directory.' }
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                    $sourceStream = $entry.Open(); $targetStream = New-Object IO.FileStream($target,[IO.FileMode]::Create)
                    try { $sourceStream.CopyTo($targetStream) } finally { $targetStream.Dispose(); $sourceStream.Dispose() }
                }
            } finally { $zip.Dispose() }
        } elseif ($extension -eq '.json' -or $extension -eq '.cmhud-theme') {
            $theme = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
            [void](Assert-HudThemeDefinition $theme $false)
            $target = Join-Path $userRoot (([string]$theme.id) + '.json')
            $theme | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $target
        } else { throw 'Use .json, .cmhud-theme, or .cmhud-theme.zip.' }
        $script:themes = @(Get-HudThemes $pluginRoot)
        Build-ThemeButtons
        $installed = $themes | Where-Object { [string]$_.id -eq [string]$theme.id } | Select-Object -First 1
        if ($null -eq $installed) { throw 'Theme was copied but could not be loaded.' }
        Apply-HudThemeDefinition $installed
        Sync-ControlsFromConfig
        Save-HudConfig $paths $config
        Update-DisplaySnapshot
        $saveStatus.Text = ([string]$settingsLocale.themeImportSuccess -f (Get-ThemeDisplayName $installed))
        $saveStatus.ToolTip = [string]$installed.SourcePath
        return $true
    } catch {
        $saveStatus.Text = [string]$settingsLocale.themeImportFailed
        $saveStatus.ToolTip = $_.Exception.Message
        return $false
    }
}

function Show-HudThemeImportDialog {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = [string]$settingsLocale.themeImportFilter
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog($settings) -eq $true) { [void](Import-HudThemeFile $dialog.FileName) }
}

function Set-Preset {
    param([string]$Name)
    $theme = $themes | Where-Object { [string]$_.id -eq $Name } | Select-Object -First 1
    if ($null -eq $theme) { return }
    [void](Assert-HudThemeDefinition $theme ($theme.SourceKind -eq 'user'))
    Apply-HudThemeDefinition $theme
    Sync-ControlsFromConfig
    Save-HudConfig $paths $config
    Update-DisplaySnapshot
}

function Set-StatusPalette {
    param([string]$Name)
    if (-not $statusPalettes.Contains($Name)) { return }
    $palette = $statusPalettes[$Name]
    foreach ($key in $statusTextControls.Keys) { $config.statusColors.$key = [string]$palette[$key] }
    $config.statusPalette = $Name
    Sync-ControlsFromConfig
    Save-HudConfig $paths $config
    Update-DisplaySnapshot
}

function Sync-ControlsFromConfig {
    $script:syncingControls = $true
    try {
        Select-ComboTag $languageCombo ([string]$config.language)
        Select-ComboTag $layoutCombo ([string]$config.layout)
        Select-ComboTag $numberCombo ([string]$config.numberFormat)
        Select-ComboTag $positionCombo ([string]$config.position)
        Select-ComboTag $monitorScopeCombo ([string]$config.monitorScope)
        Select-ComboTag $activeWindowCombo ([string][int]$config.activeWindowMinutes)
        Select-ComboTag $taskRetentionCombo ([string][int]$config.statusTiming.terminalHoldSeconds)
        Select-ComboTag $terminalExitModeCombo ([string]$config.statusTiming.terminalExitMode)
        Select-ComboTag $displayModeCombo ([string]$config.multiTask.displayMode)
        Select-ComboTag $listStyleCombo ([string]$config.multiTask.listStyle)
        Select-ComboTag $listDensityCombo ([string]$config.multiTask.listDensity)
        Select-ComboTag $taskNameModeCombo ([string]$config.multiTask.nameMode)
        Select-ComboTag $maxSplitCombo ([string][int]$config.multiTask.maxSplitBubbles)
        Select-ComboTag $numberCooldownCombo ([string][int]$config.multiTask.numberCooldownSeconds)
        Select-ComboTag $summaryAttentionModeCombo ([string]$config.attention.summaryMode)
        Select-ComboTag $listAttentionModeCombo ([string]$config.attention.listMode)
        Select-ComboTag $taskBubbleAttentionModeCombo ([string]$config.attention.taskBubbleMode)
        Select-ComboTag $dotPatternCombo ([string]$config.attention.dotPattern)
        Select-ComboTag $dotBrightnessCombo ([string]$config.attention.dotBrightness)
        Select-ComboTag $dotSpeedCombo ([string]$config.attention.dotSpeed)
        Select-ComboTag $attentionDurationCombo ([string][int]$config.attention.durationSeconds)
        Select-ComboTag $agentNotificationPermissionCombo ([string]$config.agentNotifications.permission)
        Select-ComboTag $agentNotificationModeCombo ([string]$config.agentNotifications.mode)
        Select-ComboTag $agentNotificationGlowPresetCombo ([string]$config.agentNotifications.glowPreset)
        Select-ComboTag $agentNotificationIntensityCombo ([string]$config.agentNotifications.intensity)
        Select-ComboTag $agentNotificationDurationCombo ([string][int]$config.agentNotifications.durationSeconds)
        Select-ComboTag $transparencyModeCombo ([string]$config.transparencyMode)
        Apply-SettingsLanguage
        foreach ($key in $fieldControls.Keys) { $fieldControls[$key].IsChecked = [bool]$config.fields.$key }
        $fontSizeSlider.Value = [double]$config.fontSize
        $radiusSlider.Value = [double]$config.cornerRadius
        $opacitySlider.Value = [double]$config.opacity
        $alwaysOnTopCheck.IsChecked = [bool]$config.alwaysOnTop
        $mousePassthroughCheck.IsChecked = [bool]$config.mousePassthrough
        $statusDotCheck.IsChecked = [bool]$config.showStatusDot
        $animateCheck.IsChecked = [bool]$config.animateUpdates
        $autoSplitCheck.IsChecked = [bool]$config.multiTask.autoSplitNewTasks
        $attentionCompletedCheck.IsChecked = [bool]$config.attention.onCompleted
        $attentionErrorCheck.IsChecked = [bool]$config.attention.onAbortedOrError
        $attentionSettledCheck.IsChecked = [bool]$config.attention.onSettled
        $agentNotificationEnabledCheck.IsChecked = [bool]$config.agentNotifications.enabled
        $dotAttentionEnabledCheck.IsChecked = [bool]$config.attention.dotEnabled
        $dotBreathingCheck.IsChecked = [bool]$config.attention.dotBreathing
        foreach ($key in $listFieldControls.Keys) { $listFieldControls[$key].IsChecked = [bool]$config.multiTask.listFields.$key }
        foreach ($key in $bubbleFieldControls.Keys) { $bubbleFieldControls[$key].IsChecked = [bool]$config.multiTask.bubbleFields.$key }
        $pricingPathText.Text = [string]$config.pricing.path
        $pricingName = if ([string]$pricingCatalog.Kind -eq 'built-in') { [string]$settingsLocale.pricingBuiltIn } else { [IO.Path]::GetFileName([string]$pricingCatalog.Path) }
        $pricingStatusText.Text = if ([bool]$pricingCatalog.Loaded) { ([string]$settingsLocale.pricingLoaded).Replace('{0}',$pricingName) } else { ([string]$settingsLocale.pricingUnavailable).Replace('{0}',$pricingName) }
        $backgroundText.Text = [string]$config.background
        $foregroundText.Text = [string]$config.foreground
        $accentText.Text = [string]$config.accent
        $agentNotificationColorText.Text = [string]$config.agentNotifications.color
        foreach($key in $statusTextControls.Keys){$statusTextControls[$key].Text=[string]$config.statusColors.$key}
        $activeSecondsText.Text=[string][int]$config.statusTiming.activeSeconds
        $idleSecondsText.Text=[string][int]$config.statusTiming.idleSeconds
        $errorHoldSecondsText.Text=[string][int]$config.statusTiming.errorHoldSeconds
        $fontSizeValue.Text = ('{0:0.0}' -f [double]$config.fontSize)
        $radiusValue.Text = [string][int]$config.cornerRadius
        $opacityValue.Text = ('{0:P0}' -f [double]$config.opacity)
        Update-ColorSwatches
    } finally { $script:syncingControls = $false }
}

function Export-SettingsPreview {
    param([Parameter(Mandatory = $true)][string]$Path)
    $script:config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $script:config.language = $PreviewLanguage
    Build-ThemeButtons
    Sync-ControlsFromConfig
    $tabMap = @{ general='GeneralTab'; multi='MultiTaskTab'; metrics='MetricsTab'; appearance='AppearanceTab' }
    $settingsTabs.SelectedItem = $settingsTabControls[[string]$tabMap[$PreviewSettingsTab]]
    if ($PreviewSettingsAdvanced) {
        $settingsTabs.SelectedItem = $settingsTabControls['AppearanceTab']
        $advancedStatusExpander.IsExpanded = $true
    }
    $settingsShell.Effect = $null
    $settingsShell.Background = New-HudBrush '#FFFFFFFF'
    $content = $settings.Content
    $size = New-Object Windows.Size(720, 790)
    $content.Measure($size)
    $content.Arrange((New-Object Windows.Rect(0, 0, 720, 790)))
    $content.UpdateLayout()
    $settingsScrollViewer.ScrollToHome()
    if ($PreviewSettingsAdvanced) {
        $appearanceScrollViewer.ScrollToEnd()
    } elseif ($PreviewSettingsReminders) {
        $multiTaskScrollViewer.ScrollToVerticalOffset(470)
    } else { $settingsScrollViewer.ScrollToTop() }
    $content.UpdateLayout()
    [void]$content.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap(720, 790, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($content)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Create)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

if (-not [string]::IsNullOrWhiteSpace($RenderSettingsPreview)) {
    try { Export-SettingsPreview $RenderSettingsPreview } finally { Release-HudMutex }
    exit 0
}

function Apply-ControlsToConfig {
    param([switch]$StatusColorsChanged)
    if ($syncingControls) { return }
    $language = Get-ComboTag $languageCombo
    $layout = Get-ComboTag $layoutCombo
    $number = Get-ComboTag $numberCombo
    $position = Get-ComboTag $positionCombo
    $monitorScope = Get-ComboTag $monitorScopeCombo
    $activeWindow = Get-ComboTag $activeWindowCombo
    $taskRetention = Get-ComboTag $taskRetentionCombo
    $terminalExitMode = Get-ComboTag $terminalExitModeCombo
    $displayMode = Get-ComboTag $displayModeCombo
    $listStyle = Get-ComboTag $listStyleCombo
    $listDensity = Get-ComboTag $listDensityCombo
    $taskNameMode = Get-ComboTag $taskNameModeCombo
    $maxSplitBubbles = Get-ComboTag $maxSplitCombo
    $numberCooldown = Get-ComboTag $numberCooldownCombo
    $summaryAttentionMode = Get-ComboTag $summaryAttentionModeCombo
    $listAttentionMode = Get-ComboTag $listAttentionModeCombo
    $taskBubbleAttentionMode = Get-ComboTag $taskBubbleAttentionModeCombo
    $dotPattern = Get-ComboTag $dotPatternCombo
    $dotBrightness = Get-ComboTag $dotBrightnessCombo
    $dotSpeed = Get-ComboTag $dotSpeedCombo
    $attentionDuration = Get-ComboTag $attentionDurationCombo
    $agentNotificationPermission = Get-ComboTag $agentNotificationPermissionCombo
    $agentNotificationMode = Get-ComboTag $agentNotificationModeCombo
    $agentNotificationGlowPreset = Get-ComboTag $agentNotificationGlowPresetCombo
    $agentNotificationIntensity = Get-ComboTag $agentNotificationIntensityCombo
    $agentNotificationDuration = Get-ComboTag $agentNotificationDurationCombo
    $transparencyMode = Get-ComboTag $transparencyModeCombo
    $previousDisplayMode = [string]$config.multiTask.displayMode
    $previousMaxSplitBubbles = [int]$config.multiTask.maxSplitBubbles
    if ($language) { $config.language = $language }
    if ($layout) { $config.layout = $layout }
    if ($number) { $config.numberFormat = $number }
    if ($position) { $config.position = $position }
    if ($monitorScope) { $config.monitorScope = $monitorScope }
    if ($activeWindow) { $config.activeWindowMinutes = [int]$activeWindow }
    if ($taskRetention) { $config.statusTiming.terminalHoldSeconds = [int]$taskRetention }
    if ($terminalExitMode) { $config.statusTiming.terminalExitMode = $terminalExitMode }
    if ($displayMode) { $config.multiTask.displayMode = $displayMode }
    if ($listStyle) { $config.multiTask.listStyle = $listStyle }
    if ($listDensity) { $config.multiTask.listDensity = $listDensity }
    if ($taskNameMode) { $config.multiTask.nameMode = $taskNameMode }
    if ($maxSplitBubbles) { $config.multiTask.maxSplitBubbles = [int]$maxSplitBubbles }
    if ($numberCooldown) { $config.multiTask.numberCooldownSeconds = [int]$numberCooldown }
    if ($summaryAttentionMode) { $config.attention.summaryMode = $summaryAttentionMode }
    if ($listAttentionMode) { $config.attention.listMode = $listAttentionMode }
    if ($taskBubbleAttentionMode) { $config.attention.taskBubbleMode = $taskBubbleAttentionMode }
    if ($dotPattern) { $config.attention.dotPattern = $dotPattern }
    if ($dotBrightness) { $config.attention.dotBrightness = $dotBrightness }
    if ($dotSpeed) { $config.attention.dotSpeed = $dotSpeed }
    if ($attentionDuration) { $config.attention.durationSeconds = [int]$attentionDuration }
    if ($agentNotificationPermission) { $config.agentNotifications.permission = $agentNotificationPermission }
    if ($agentNotificationMode) { $config.agentNotifications.mode = $agentNotificationMode }
    if ($agentNotificationGlowPreset) {
        $config.agentNotifications.glowPreset = $agentNotificationGlowPreset
    }
    if ($agentNotificationIntensity) { $config.agentNotifications.intensity = $agentNotificationIntensity }
    if ($agentNotificationDuration) { $config.agentNotifications.durationSeconds = [int]$agentNotificationDuration }
    if ($transparencyMode) { $config.transparencyMode = $transparencyMode }
    Apply-SettingsLanguage
    foreach ($key in $fieldControls.Keys) { $config.fields.$key = [bool]$fieldControls[$key].IsChecked }
    $config.fontSize = [Math]::Round([double]$fontSizeSlider.Value, 1)
    $config.cornerRadius = [int]$radiusSlider.Value
    $config.opacity = [Math]::Round([double]$opacitySlider.Value, 2)
    $config.alwaysOnTop = [bool]$alwaysOnTopCheck.IsChecked
    $config.mousePassthrough = [bool]$mousePassthroughCheck.IsChecked
    $config.showStatusDot = [bool]$statusDotCheck.IsChecked
    $config.animateUpdates = [bool]$animateCheck.IsChecked
    $config.multiTask.autoSplitNewTasks = [bool]$autoSplitCheck.IsChecked
    $config.attention.onCompleted = [bool]$attentionCompletedCheck.IsChecked
    $config.attention.onAbortedOrError = [bool]$attentionErrorCheck.IsChecked
    $config.attention.onSettled = [bool]$attentionSettledCheck.IsChecked
    $config.agentNotifications.enabled = [bool]$agentNotificationEnabledCheck.IsChecked
    $config.attention.dotEnabled = [bool]$dotAttentionEnabledCheck.IsChecked
    $config.attention.dotBreathing = [bool]$dotBreathingCheck.IsChecked
    foreach ($key in $listFieldControls.Keys) { $config.multiTask.listFields.$key = [bool]$listFieldControls[$key].IsChecked }
    foreach ($key in $bubbleFieldControls.Keys) { $config.multiTask.bubbleFields.$key = [bool]$bubbleFieldControls[$key].IsChecked }
    $config.pricing.path = [string]$pricingPathText.Text.Trim()
    $script:pricingCatalog = Get-HudPricingCatalog $pluginRoot ([string]$config.pricing.path)
    $pricingName = if ([string]$pricingCatalog.Kind -eq 'built-in') { [string]$settingsLocale.pricingBuiltIn } else { [IO.Path]::GetFileName([string]$pricingCatalog.Path) }
    $pricingStatusText.Text = if ([bool]$pricingCatalog.Loaded) { ([string]$settingsLocale.pricingLoaded).Replace('{0}',$pricingName) } else { ([string]$settingsLocale.pricingUnavailable).Replace('{0}',$pricingName) }
    foreach ($pair in @(@('background',$backgroundText.Text), @('foreground',$foregroundText.Text), @('accent',$accentText.Text))) {
        try { [void](New-HudBrush ([string]$pair[1])); $config.($pair[0]) = [string]$pair[1] } catch { }
    }
    try {
        [void][Windows.Media.ColorConverter]::ConvertFromString([string]$agentNotificationColorText.Text)
        $presetColors = @{ violet='#FF7C3AED'; aqua='#FF00A7C4'; amber='#FFFF9F0A' }
        if ($presetColors.ContainsKey([string]$config.agentNotifications.glowPreset) -and [string]$presetColors[[string]$config.agentNotifications.glowPreset] -ne [string]$agentNotificationColorText.Text) { $config.agentNotifications.glowPreset = 'custom' }
        $config.agentNotifications.color = [string]$agentNotificationColorText.Text
    } catch { }
    foreach($key in $statusTextControls.Keys){
        try{[void][Windows.Media.ColorConverter]::ConvertFromString([string]$statusTextControls[$key].Text);$config.statusColors.$key=[string]$statusTextControls[$key].Text}catch{}
    }
    if ($StatusColorsChanged) { $config.statusPalette = 'custom' }
    foreach($pair in @(@('activeSeconds',$activeSecondsText.Text,1,60),@('idleSeconds',$idleSecondsText.Text,10,3600),@('errorHoldSeconds',$errorHoldSecondsText.Text,1,300))){
        $value=0
        if([int]::TryParse([string]$pair[1],[ref]$value)){$config.statusTiming.($pair[0])=[Math]::Max([int]$pair[2],[Math]::Min([int]$pair[3],$value))}
    }
    $fontSizeValue.Text = ('{0:0.0}' -f [double]$config.fontSize)
    $radiusValue.Text = [string][int]$config.cornerRadius
    $opacityValue.Text = ('{0:P0}' -f [double]$config.opacity)
    Update-ColorSwatches
    $config.preset = 'custom'
    if ($previousDisplayMode -ne [string]$config.multiTask.displayMode -or $previousMaxSplitBubbles -ne [int]$config.multiTask.maxSplitBubbles) {
        if ([string]$config.multiTask.displayMode -eq 'summary') {
            foreach ($path in @($splitWindows.Keys)) { Close-TaskBubble ([string]$path) }
        } elseif ([string]$config.multiTask.displayMode -eq 'list') {
            if ($previousDisplayMode -eq 'split') { foreach ($path in @($splitWindows.Keys)) { Close-TaskBubble ([string]$path) } }
        } else {
            $eligible = @(Get-HudUserTaskStates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First ([int]$config.multiTask.maxSplitBubbles))
            $eligiblePaths = @{}
            foreach ($state in $eligible) { $eligiblePaths[[string]$state.Path] = $true; Show-TaskBubble $state }
            foreach ($path in @($splitWindows.Keys)) { if (-not $eligiblePaths.ContainsKey([string]$path)) { Close-TaskBubble ([string]$path) } }
        }
    }
    Save-HudConfig $paths $config
    Update-DisplaySnapshot
    $saveStatus.Text = ('{0}  {1}' -f [string]$settingsLocale.savedAt, (Get-Date).ToString('HH:mm:ss'))
}

function Show-HudSettings {
    Sync-ControlsFromConfig
    if (-not $settings.IsVisible) { $settings.Show() }
    $settings.Activate() | Out-Null
}

function Stop-HudApplication {
    $script:closingApp = $true
    foreach ($path in @($splitWindows.Keys)) { Close-TaskBubble ([string]$path) }
    try { $colorPicker.Close() } catch { }
    try { $settings.Close() } catch { }
    try { $hud.Close() } catch { Write-HudDebug ('HUD close warning: ' + $_.Exception.Message) }
}

function Test-HudInternalSessionFile {
    param([System.IO.FileInfo]$File)
    return [bool](Get-HudSessionIdentity $File).IsInternalSession
}

function Get-HudSessionIdentity {
    param([System.IO.FileInfo]$File)
    $identity = [pscustomobject]@{
        MetadataFound = $false
        SessionId = ''
        Workspace = ''
        IsInternalSession = $false
    }
    try {
        # Codex can write operational records before session_meta. Keep this
        # bounded, but use the same window for the session ID and subagent
        # classification so a late header never creates a titleless or
        # temporarily visible internal task.
        foreach ($line in @(Get-Content -LiteralPath $File.FullName -Encoding UTF8 -TotalCount 64 -ErrorAction Stop)) {
            try { $record = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ([string]$record.type -ne 'session_meta') { continue }
            $identity.MetadataFound = $true
            if ($null -ne $record.payload) {
                foreach ($key in @('id','session_id')) {
                    if ($null -ne $record.payload.PSObject.Properties[$key] -and -not [string]::IsNullOrWhiteSpace([string]$record.payload.$key)) {
                        $identity.SessionId = [string]$record.payload.$key
                        break
                    }
                }
                if ($null -ne $record.payload.PSObject.Properties['cwd']) {
                    try {
                        $cwd = [string]$record.payload.cwd
                        if (-not [string]::IsNullOrWhiteSpace($cwd)) {
                            $trimmed = $cwd.TrimEnd([char[]]@('\','/'))
                            $identity.Workspace = [IO.Path]::GetFileName($trimmed)
                            if ([string]::IsNullOrWhiteSpace([string]$identity.Workspace)) { $identity.Workspace = $trimmed }
                        }
                    } catch { $identity.Workspace = '' }
                }
                if ($null -ne $record.payload.PSObject.Properties['source']) {
                    $source = $record.payload.source
                    $identity.IsInternalSession = ($null -ne $source -and $null -ne $source.PSObject -and $null -ne $source.PSObject.Properties['subagent'])
                }
            }
            break
        }
    } catch { }
    return $identity
}

function Get-HudSessionId {
    param([System.IO.FileInfo]$File)
    return [string](Get-HudSessionIdentity $File).SessionId
}

function Refresh-HudSessionIndex {
    if (-not (Test-Path -LiteralPath $sessionIndexPath -PathType Leaf)) { return $false }
    try { $indexFile = Get-Item -LiteralPath $sessionIndexPath -ErrorAction Stop } catch { return $false }
    if ($indexFile.LastWriteTimeUtc -le $sessionIndexLastWriteUtc) { return $false }
    $nextMap = @{}
    try {
        foreach ($line in Get-Content -LiteralPath $sessionIndexPath -Encoding UTF8 -ErrorAction Stop) {
            try { $entry = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            $id = if ($null -ne $entry.PSObject.Properties['id']) { [string]$entry.id } else { '' }
            $title = if ($null -ne $entry.PSObject.Properties['thread_name']) { [string]$entry.thread_name } else { '' }
            $title = [regex]::Replace($title,'\s+',' ').Trim()
            if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($title)) { continue }
            if ($title.Length -gt 52) { $title = $title.Substring(0,52).TrimEnd() + [char]0x2026 }
            $nextMap[$id] = $title
        }
    } catch { return $false }
    $script:sessionTitleMap = $nextMap
    $script:sessionIndexLastWriteUtc = $indexFile.LastWriteTimeUtc
    $changed = $false
    foreach ($state in @($sessionStates.Values)) {
        $nextTitle = if (-not [string]::IsNullOrWhiteSpace([string]$state.SessionId) -and $sessionTitleMap.ContainsKey([string]$state.SessionId)) { [string]$sessionTitleMap[[string]$state.SessionId] } else { '' }
        if ([string]$state.ConversationLabel -ne $nextTitle) { $state.ConversationLabel = $nextTitle; $changed = $true }
    }
    return $changed
}

function Initialize-SessionFile {
    param([System.IO.FileInfo]$File)
    if ($sessionStates.ContainsKey($File.FullName)) { return $false }
    $initialSnapshot = Get-LatestHudSnapshot $File
    $identity = Get-HudSessionIdentity $File
    $sessionId = [string]$identity.SessionId
    $sessionStates[$File.FullName] = [pscustomobject]@{
        Path = $File.FullName
        Number = Get-NextTaskNumber
        StartedAt = [DateTimeOffset]$File.CreationTime
        Offset = [Int64]$File.Length
        PendingText = ''
        Model = if ($null -ne $initialSnapshot) { [string]$initialSnapshot.Model } else { '' }
        Workspace = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['Workspace'] -and -not [string]::IsNullOrWhiteSpace([string]$initialSnapshot.Workspace)) { [string]$initialSnapshot.Workspace } else { [string]$identity.Workspace }
        Snapshot = $initialSnapshot
        AllowanceTimestamp = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['AllowanceTimestamp']) { $initialSnapshot.AllowanceTimestamp } else { $null }
        WeeklyRemainingPercent = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['WeeklyRemainingPercent']) { $initialSnapshot.WeeklyRemainingPercent } else { $null }
        FiveHourRemainingPercent = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['FiveHourRemainingPercent']) { $initialSnapshot.FiveHourRemainingPercent } else { $null }
        LastWriteTimeUtc = $File.LastWriteTimeUtc
        LastUsageAt = if ($null -ne $initialSnapshot) { [DateTimeOffset]$initialSnapshot.Timestamp } else { [DateTimeOffset]::MinValue }
        LastReadErrorAt = [DateTimeOffset]::MinValue
        LastRenderedStatus = ''
        TerminalStatus = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['TerminalStatus']) { [string]$initialSnapshot.TerminalStatus } else { '' }
        TerminalAt = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['TerminalTimestamp'] -and $null -ne $initialSnapshot.TerminalTimestamp) { [DateTimeOffset]$initialSnapshot.TerminalTimestamp } else { [DateTimeOffset]::MinValue }
        TerminalSilent = ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['TerminalSilent'] -and [bool]$initialSnapshot.TerminalSilent)
        TerminalExitStarted = $false
        TerminalExitCompleted = $false
        TerminalExitUntil = [DateTimeOffset]::MinValue
        TerminalExitRevision = 0
        HasObservedActivity = $false
        AttentionRevision = 0
        AttentionReason = ''
        AttentionUntil = [DateTimeOffset]::MinValue
        LastListAttentionRevision = 0
        LastListExitRevision = 0
        AgentNoticeText = ''
        AgentNoticeUntil = [DateTimeOffset]::MinValue
        AgentNoticeRecipe = $null
        ActiveTurnId = ''
        PendingCompletionTurnId = ''
        PendingCompletionDueAt = [DateTimeOffset]::MinValue
        Detached = $false
        BubbleWidth = 0.0
        BubbleHeight = 0.0
        IsInternalSession = [bool]$identity.IsInternalSession
        IdentityMetadataFound = [bool]$identity.MetadataFound
        SessionId = $sessionId
        ConversationLabel = if (-not [string]::IsNullOrWhiteSpace($sessionId) -and $sessionTitleMap.ContainsKey($sessionId)) { [string]$sessionTitleMap[$sessionId] } else { '' }
        Dismissed = $false
    }
    Write-HudDebug ('Session identity loaded: {0}; metadata={1}; officialTitle={2}' -f [string]$sessionStates[$File.FullName].Workspace,[bool]$identity.MetadataFound,(-not [string]::IsNullOrWhiteSpace([string]$sessionStates[$File.FullName].ConversationLabel)))
    return $true
}

function Refresh-HudSessionIdentity {
    param([Parameter(Mandatory = $true)]$State)
    if ($null -ne $State.PSObject.Properties['IdentityMetadataFound'] -and [bool]$State.IdentityMetadataFound) { return $false }
    $file = Get-Item -LiteralPath ([string]$State.Path) -ErrorAction SilentlyContinue
    if ($null -eq $file) { return $false }
    $identity = Get-HudSessionIdentity $file
    if (-not [bool]$identity.MetadataFound) { return $false }
    $State.IdentityMetadataFound = $true
    $State.IsInternalSession = [bool]$identity.IsInternalSession
    $State.SessionId = [string]$identity.SessionId
    if ([string]::IsNullOrWhiteSpace([string]$State.Workspace) -and -not [string]::IsNullOrWhiteSpace([string]$identity.Workspace)) { $State.Workspace = [string]$identity.Workspace }
    $nextTitle = if (-not [string]::IsNullOrWhiteSpace([string]$State.SessionId) -and $sessionTitleMap.ContainsKey([string]$State.SessionId)) { [string]$sessionTitleMap[[string]$State.SessionId] } else { '' }
    $State.ConversationLabel = $nextTitle
    Write-HudDebug ('Session identity resolved: {0}; internal={1}; officialTitle={2}' -f [string]$State.Workspace,[bool]$State.IsInternalSession,(-not [string]::IsNullOrWhiteSpace($nextTitle)))
    return $true
}

function Set-HudSessionIdentityFromRecord {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Record)
    if ([string]$Record.type -ne 'session_meta') { return $false }
    $State.IdentityMetadataFound = $true
    $State.SessionId = ''
    $State.IsInternalSession = $false
    if ($null -ne $Record.payload) {
        foreach ($key in @('id','session_id')) {
            if ($null -ne $Record.payload.PSObject.Properties[$key] -and -not [string]::IsNullOrWhiteSpace([string]$Record.payload.$key)) {
                $State.SessionId = [string]$Record.payload.$key
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$State.Workspace) -and $null -ne $Record.payload.PSObject.Properties['cwd']) {
            try {
                $cwd = [string]$Record.payload.cwd
                if (-not [string]::IsNullOrWhiteSpace($cwd)) {
                    $trimmed = $cwd.TrimEnd([char[]]@('\','/'))
                    $State.Workspace = [IO.Path]::GetFileName($trimmed)
                    if ([string]::IsNullOrWhiteSpace([string]$State.Workspace)) { $State.Workspace = $trimmed }
                }
            } catch { }
        }
        if ($null -ne $Record.payload.PSObject.Properties['source']) {
            $source = $Record.payload.source
            $State.IsInternalSession = ($null -ne $source -and $null -ne $source.PSObject -and $null -ne $source.PSObject.Properties['subagent'])
        }
    }
    $State.ConversationLabel = if (-not [string]::IsNullOrWhiteSpace([string]$State.SessionId) -and $sessionTitleMap.ContainsKey([string]$State.SessionId)) { [string]$sessionTitleMap[[string]$State.SessionId] } else { '' }
    Write-HudDebug ('Session identity resolved: {0}; internal={1}; officialTitle={2}' -f [string]$State.Workspace,[bool]$State.IsInternalSession,(-not [string]::IsNullOrWhiteSpace([string]$State.ConversationLabel)))
    return $true
}

function Read-AppendedSessionData {
    param([Parameter(Mandatory = $true)]$State)
    if ([string]::IsNullOrWhiteSpace([string]$State.Path) -or -not (Test-Path -LiteralPath $State.Path)) { return $false }
    try {
        $identityChanged = Refresh-HudSessionIdentity $State
        $file = Get-Item -LiteralPath $State.Path
        $State.LastWriteTimeUtc = $file.LastWriteTimeUtc
        if ($file.Length -lt $State.Offset) {
            $State.Offset = [Int64]0
            $State.PendingText = ''
            $State.Model = ''
            $State.Workspace = ''
        }
        if ($file.Length -eq $State.Offset) { return $identityChanged }
        $stream = New-Object IO.FileStream($State.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            [void]$stream.Seek($State.Offset, [IO.SeekOrigin]::Begin)
            $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $State.Offset = [Int64]$stream.Position
        } finally { $stream.Dispose() }

        $split = Split-HudJsonLines ([string]$State.PendingText) $text
        $State.PendingText = [string]$split.PendingText
        $updated = $identityChanged
        foreach ($line in @($split.CompleteLines)) {
            try {
                $rawRecord = $line | ConvertFrom-Json -ErrorAction Stop
                if (Set-HudSessionIdentityFromRecord $State $rawRecord) { $updated = $true }
            } catch { }
            $item = Convert-HudRecord $line
            if ($null -eq $item) { continue }
            if ($item.Kind -eq 'context') {
                $State.Model = [string]$item.Model
                if ($null -ne $item.PSObject.Properties['Workspace']) { $State.Workspace = [string]$item.Workspace }
            }
            if ($item.Kind -eq 'started') {
                if ($State.PendingCompletionDueAt -ne [DateTimeOffset]::MinValue) { Write-HudDebug ('Pending completion canceled: ' + [string]$State.Workspace) }
                $State.ActiveTurnId = [string]$item.TurnId
                Clear-PendingTaskCompletion $State
                $State.TerminalStatus = ''
                $State.TerminalAt = [DateTimeOffset]::MinValue
                $State.TerminalSilent = $false
                Reset-TerminalExitState $State
                $State.Dismissed = $false
                $State.LastUsageAt = [DateTimeOffset]::Now
                $State.HasObservedActivity = $true
                $updated = $true
            } elseif ($item.Kind -eq 'completed') {
                if ([string]::IsNullOrWhiteSpace([string]$State.ActiveTurnId) -or [string]$item.TurnId -eq [string]$State.ActiveTurnId) {
                    $State.PendingCompletionTurnId = [string]$item.TurnId
                    $State.PendingCompletionDueAt = [DateTimeOffset]::Now.AddSeconds([int]$config.attention.completionGraceSeconds)
                    if ([int]$config.attention.completionGraceSeconds -eq 0) { [void](Confirm-PendingTaskCompletion $State) }
                }
                $updated = $true
            } elseif ($item.Kind -eq 'completed_silent') {
                Clear-PendingTaskCompletion $State
                $State.TerminalStatus = 'completed'
                $State.TerminalAt = [DateTimeOffset]$item.Timestamp
                $State.TerminalSilent = $true
                Reset-TerminalExitState $State
                Write-HudDebug ('Silent completion retained: ' + [string]$State.Workspace)
                $updated = $true
            } elseif ($item.Kind -eq 'aborted') {
                Clear-PendingTaskCompletion $State
                $State.TerminalStatus = 'aborted'
                $State.TerminalAt = [DateTimeOffset]$item.Timestamp
                $State.TerminalSilent = $false
                Reset-TerminalExitState $State
                Set-TaskAttention $State 'aborted'
                $updated = $true
            }
            if ($item.Kind -eq 'usage' -or $item.Kind -eq 'allowance') {
                $hasAllowance = ($null -ne $item.PSObject.Properties['WeeklyRemainingPercent'] -and $null -ne $item.WeeklyRemainingPercent) -or
                    ($null -ne $item.PSObject.Properties['FiveHourRemainingPercent'] -and $null -ne $item.FiveHourRemainingPercent)
                if ($hasAllowance) {
                    $State.AllowanceTimestamp = $item.AllowanceTimestamp
                    $State.WeeklyRemainingPercent = $item.WeeklyRemainingPercent
                    $State.FiveHourRemainingPercent = $item.FiveHourRemainingPercent
                    if ($null -ne $State.Snapshot) {
                        $State.Snapshot.AllowanceTimestamp = $State.AllowanceTimestamp
                        $State.Snapshot.WeeklyRemainingPercent = $State.WeeklyRemainingPercent
                        $State.Snapshot.FiveHourRemainingPercent = $State.FiveHourRemainingPercent
                    }
                    $updated = $true
                }
            }
            if ($item.Kind -eq 'usage') {
                $item.Model = [string]$State.Model
                $item | Add-Member -NotePropertyName Workspace -NotePropertyValue ([string]$State.Workspace) -Force
                if ($null -ne $State.AllowanceTimestamp) {
                    $item.AllowanceTimestamp = $State.AllowanceTimestamp
                    $item.WeeklyRemainingPercent = $State.WeeklyRemainingPercent
                    $item.FiveHourRemainingPercent = $State.FiveHourRemainingPercent
                }
                $State.Snapshot = $item
                $State.LastUsageAt = [DateTimeOffset]::Now
                $State.LastReadErrorAt = [DateTimeOffset]::MinValue
                $State.HasObservedActivity = $true
                $script:lastUsageAt = [DateTimeOffset]::Now
                $updated = $true
            }
        }
        return $updated
    } catch {
        $State.LastReadErrorAt = [DateTimeOffset]::Now
        $script:lastReadErrorAt = [DateTimeOffset]::Now
        Write-HudDebug ('Session read failed: ' + $_.Exception.Message)
        return $false
    }
}

function Write-HudTaskRegistry {
    try {
        $tasks = @(Get-HudUserTaskStates | Sort-Object Number | ForEach-Object {
            [ordered]@{
                task_number = [int]$_.Number
                workspace = [string]$_.Workspace
                status = [string](Get-TaskStatus $_)
                updated_at = ([DateTimeOffset]$_.LastUsageAt).ToString('O')
            }
        })
        $registry = [ordered]@{ version=1; generated_at=[DateTimeOffset]::Now.ToString('O'); tasks=$tasks }
        [IO.File]::WriteAllText((Join-Path $paths.StateRoot 'task-registry.json'),($registry | ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    } catch { Write-HudDebug ('Task registry update failed: ' + $_.Exception.Message) }
}

function Update-DisplaySnapshot {
    $visibleStates = @(Get-HudUserTaskStates)
    $visiblePaths = @{}
    foreach ($state in $visibleStates) { $visiblePaths[[string]$state.Path] = $true }
    foreach ($path in @($splitWindows.Keys)) {
        if (-not $visiblePaths.ContainsKey([string]$path)) { Close-TaskBubble ([string]$path) }
    }
    Write-HudTaskRegistry
    $snapshots = @($visibleStates | ForEach-Object { $_.Snapshot } | Where-Object { $null -ne $_ })
    if ($snapshots.Count -eq 0) { $script:snapshot = $null; Render-Hud; Update-ContextMenuText; return }
    foreach ($taskSnapshot in $snapshots) {
        $estimate = Get-HudCostEstimate $taskSnapshot $pricingCatalog
        $taskSnapshot | Add-Member -NotePropertyName EstimatedCostUsd -NotePropertyValue $(if($null -ne $estimate){[double]$estimate.CostUsd}else{$null}) -Force
        $taskSnapshot | Add-Member -NotePropertyName PricingModel -NotePropertyValue $(if($null -ne $estimate){[string]$estimate.PricedAs}else{''}) -Force
    }
    if ([string]$config.monitorScope -eq 'aggregate') {
        $script:snapshot = Merge-HudSnapshots $snapshots $locale
    } else {
        $latest = $snapshots | Sort-Object Timestamp -Descending | Select-Object -First 1
        $script:snapshot = $latest.PSObject.Copy()
        $rateSource = Get-LatestHudAllowanceSnapshot $snapshots
        if ($null -ne $rateSource) {
            $snapshot.AllowanceTimestamp = $rateSource.AllowanceTimestamp
            $snapshot.WeeklyRemainingPercent = $rateSource.WeeklyRemainingPercent
            $snapshot.FiveHourRemainingPercent = $rateSource.FiveHourRemainingPercent
        }
        if ($null -eq $snapshot.PSObject.Properties['ActiveTasks']) { $snapshot | Add-Member -NotePropertyName ActiveTasks -NotePropertyValue $snapshots.Count }
        else { $snapshot.ActiveTasks = $snapshots.Count }
    }
    Render-Hud
    Update-ContextMenuText
}

function Refresh-ActiveSessions {
    $isInitialScan = -not $initialSessionScanComplete
    $indexChanged = Refresh-HudSessionIndex
    $files = @(Get-ActiveHudSessionFiles $paths.SessionsRoot ([int]$config.activeWindowMinutes))
    $activePaths = @{}
    $changed = [bool]$indexChanged
    foreach ($file in $files) {
        $activePaths[$file.FullName] = $true
        $initialized = Initialize-SessionFile $file
        $state = $sessionStates[$file.FullName]
        if (Refresh-HudSessionIdentity $state) { $changed = $true }
        if ($initialized) {
            $changed = $true
            if ([string]$config.multiTask.displayMode -eq 'split' -and ($isInitialScan -or [bool]$config.multiTask.autoSplitNewTasks)) {
                $newState = $state
                if ((Test-HudUserTaskState $newState) -and $splitWindows.Count -lt [int]$config.multiTask.maxSplitBubbles) { Show-TaskBubble $newState }
            }
        }
    }
    foreach ($path in @($sessionStates.Keys)) {
        if (-not $activePaths.ContainsKey($path)) {
            $state = $sessionStates[$path]
            Close-TaskBubble ([string]$path)
            Release-TaskNumber ([int]$state.Number)
            $sessionStates.Remove($path)
            $changed = $true
        }
    }
    $script:initialSessionScanComplete = $true
    return $changed
}

if (-not [string]::IsNullOrWhiteSpace($ImportThemeFile)) {
    Build-ThemeButtons
    if (-not (Import-HudThemeFile $ImportThemeFile)) { throw ([string]$saveStatus.ToolTip) }
    Write-Output ('Theme installed: ' + [string]$ImportThemeFile)
    Release-HudMutex
    exit 0
}

Build-ThemeButtons

$sliderPreviewTimer = New-Object Windows.Threading.DispatcherTimer
$sliderPreviewTimer.Interval = [TimeSpan]::FromMilliseconds(55)
$sliderPreviewTimer.Add_Tick({
    $sliderPreviewTimer.Stop()
    $script:interactivePreview = $true
    try { Update-DisplaySnapshot } finally { $script:interactivePreview = $false }
})
$sliderSaveTimer = New-Object Windows.Threading.DispatcherTimer
$sliderSaveTimer.Interval = [TimeSpan]::FromMilliseconds(320)
$sliderSaveTimer.Add_Tick({
    $sliderSaveTimer.Stop()
    Save-HudConfig $paths $config
    $saveStatus.Text = ('{0}  {1}' -f [string]$settingsLocale.savedAt, (Get-Date).ToString('HH:mm:ss'))
})

function Apply-SliderPreview {
    param([string]$Property)
    if($syncingControls){return}
    switch($Property){
        'fontSize' {
            $config.fontSize=[Math]::Round([double]$fontSizeSlider.Value,1)
            $fontSizeValue.Text=('{0:0.0}' -f [double]$config.fontSize)
        }
        'cornerRadius' {
            $config.cornerRadius=[int][Math]::Round([double]$radiusSlider.Value)
            $radiusValue.Text=[string][int]$config.cornerRadius
        }
        'opacity' {
            $config.opacity=[Math]::Round([double]$opacitySlider.Value,2)
            $opacityValue.Text=('{0:P0}' -f [double]$config.opacity)
        }
    }
    $config.preset='custom'
    $sliderPreviewTimer.Stop();$sliderPreviewTimer.Start()
    $sliderSaveTimer.Stop();$sliderSaveTimer.Start()
}

$liveControls = @(
    $languageCombo,$layoutCombo,$numberCombo,$positionCombo,$monitorScopeCombo,$activeWindowCombo,$taskRetentionCombo,$terminalExitModeCombo,
    $displayModeCombo,$listStyleCombo,$listDensityCombo,$taskNameModeCombo,$maxSplitCombo,$numberCooldownCombo,
    $summaryAttentionModeCombo,$listAttentionModeCombo,$taskBubbleAttentionModeCombo,$dotPatternCombo,$dotBrightnessCombo,$dotSpeedCombo,$attentionDurationCombo,$transparencyModeCombo,
    $agentNotificationPermissionCombo,$agentNotificationModeCombo,$agentNotificationIntensityCombo,$agentNotificationDurationCombo,
    $alwaysOnTopCheck,$mousePassthroughCheck,$statusDotCheck,$animateCheck,$autoSplitCheck,
    $attentionCompletedCheck,$attentionErrorCheck,$attentionSettledCheck,$dotAttentionEnabledCheck,$dotBreathingCheck,$agentNotificationEnabledCheck
) + @($fieldControls.Values) + @($listFieldControls.Values) + @($bubbleFieldControls.Values)
foreach ($control in $liveControls) {
    if ($control -is [Windows.Controls.ComboBox]) { $control.Add_SelectionChanged({ Apply-ControlsToConfig }) }
    else { $control.Add_Click({ Apply-ControlsToConfig }) }
}
$agentNotificationGlowPresetCombo.Add_SelectionChanged({
    if($syncingControls){return}
    $preset=Get-ComboTag $agentNotificationGlowPresetCombo
    $presetColors=@{violet='#FF7C3AED';aqua='#FF00A7C4';amber='#FFFF9F0A'}
    if($presetColors.ContainsKey([string]$preset)){$agentNotificationColorText.Text=[string]$presetColors[[string]$preset]}
    Apply-ControlsToConfig
})
$fontSizeSlider.Add_ValueChanged({ Apply-SliderPreview 'fontSize' })
$radiusSlider.Add_ValueChanged({ Apply-SliderPreview 'cornerRadius' })
$opacitySlider.Add_ValueChanged({ Apply-SliderPreview 'opacity' })
foreach ($textBox in @($backgroundText,$foregroundText,$accentText,$agentNotificationColorText,$activeSecondsText,$idleSecondsText,$errorHoldSecondsText,$pricingPathText)) { $textBox.Add_LostFocus({ Apply-ControlsToConfig }) }
foreach ($textBox in @($statusTextControls.Values)) { $textBox.Add_LostFocus({ Apply-ControlsToConfig -StatusColorsChanged }) }

foreach($pair in @(@($backgroundColorButton,$backgroundText),@($foregroundColorButton,$foregroundText),@($accentColorButton,$accentText),@($agentNotificationColorButton,$agentNotificationColorText))){
    $pair[0].Tag=$pair[1]
    $pair[0].Add_Click([Windows.RoutedEventHandler]{param($sender,$eventArgs);Show-ColorPicker $sender.Tag $sender})
}
foreach($key in $statusColorButtons.Keys){
    $statusColorButtons[$key].Tag=$statusTextControls[$key]
    $statusColorButtons[$key].Add_Click([Windows.RoutedEventHandler]{param($sender,$eventArgs);Show-ColorPicker $sender.Tag $sender})
}
foreach($key in $statusPaletteButtons.Keys){
    $statusPaletteButtons[$key].Tag = $key
    $statusPaletteButtons[$key].Add_Click([Windows.RoutedEventHandler]{param($sender,$eventArgs);Set-StatusPalette ([string]$sender.Tag)})
}

$titleBar.Add_MouseLeftButtonDown({ if ($_.ButtonState -eq [Windows.Input.MouseButtonState]::Pressed) { $settings.DragMove() } })
$themeImportButton.Add_Click({ Show-HudThemeImportDialog })
$themeDragOver = [Windows.DragEventHandler]{ param($sender,$eventArgs)
    $eventArgs.Effects = [Windows.DragDropEffects]::None
    if ($eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
        $files = @($eventArgs.Data.GetData([Windows.DataFormats]::FileDrop))
        if ($files.Count -eq 1 -and @('.json','.cmhud-theme','.zip') -contains [IO.Path]::GetExtension([string]$files[0]).ToLowerInvariant()) { $eventArgs.Effects = [Windows.DragDropEffects]::Copy }
    }
    $eventArgs.Handled = $true
}
$themeDrop = [Windows.DragEventHandler]{ param($sender,$eventArgs)
    if ($eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
        $files = @($eventArgs.Data.GetData([Windows.DataFormats]::FileDrop))
        if ($files.Count -eq 1) { [void](Import-HudThemeFile ([string]$files[0])) }
    }
    $themeWorkshopDropZone.Background = New-HudBrush '#080A84FF'
    $themeWorkshopDropZone.BorderBrush = New-HudBrush '#280A84FF'
    $eventArgs.Handled = $true
}
$themeWorkshopDropZone.Add_DragEnter({ $themeWorkshopDropZone.Background=New-HudBrush '#180A84FF';$themeWorkshopDropZone.BorderBrush=New-HudBrush '#700A84FF' })
$themeWorkshopDropZone.Add_DragLeave({ $themeWorkshopDropZone.Background=New-HudBrush '#080A84FF';$themeWorkshopDropZone.BorderBrush=New-HudBrush '#280A84FF' })
$themeWorkshopDropZone.Add_DragOver($themeDragOver)
$themeWorkshopDropZone.Add_Drop($themeDrop)
$settings.AllowDrop = $true
$settings.Add_DragOver($themeDragOver)
$settings.Add_Drop($themeDrop)
$closeSettingsButton.Add_Click({ Save-HudConfig $paths $config; $settings.Hide() })
$saveButton.Add_Click({ Apply-ControlsToConfig; $settings.Hide() })
$resetButton.Add_Click({
    $script:config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $script:pricingCatalog = Get-HudPricingCatalog $pluginRoot ([string]$config.pricing.path)
    Sync-ControlsFromConfig
    Save-HudConfig $paths $config
    Update-DisplaySnapshot
})
$settings.Add_Closing({
    if (-not $closingApp) { $_.Cancel = $true; Save-HudConfig $paths $config; $settings.Hide() }
})

$taskListToggleButton.Add_Click({
    if ([string]$config.multiTask.displayMode -eq 'list') { Set-MultiTaskDisplayMode 'summary' }
    else { Set-MultiTaskDisplayMode 'list' }
    $_.Handled = $true
})

$hud.Add_MouseLeftButtonDown({
    if ($_.ClickCount -ge 2) { Show-HudSettings; return }
    if ($_.ButtonState -eq [Windows.Input.MouseButtonState]::Pressed) {
        try {
            $hud.DragMove()
            $config.position = 'custom'
            $config.customLeft = $hud.Left
            $config.customTop = $hud.Top
            Save-HudConfig $paths $config
            Position-TaskBubbles
        } catch { }
    }
})

$contextMenu = New-Object Windows.Controls.ContextMenu
$statusItem = New-Object Windows.Controls.MenuItem
$settingsItem = New-Object Windows.Controls.MenuItem
$passthroughItem = New-Object Windows.Controls.MenuItem
$pauseItem = New-Object Windows.Controls.MenuItem
$positionItem = New-Object Windows.Controls.MenuItem
$viewModeItem = New-Object Windows.Controls.MenuItem
$summaryModeItem = New-Object Windows.Controls.MenuItem
$listModeItem = New-Object Windows.Controls.MenuItem
$splitModeItem = New-Object Windows.Controls.MenuItem
$mergeAllItem = New-Object Windows.Controls.MenuItem
$summaryModeItem.IsCheckable = $true
$listModeItem.IsCheckable = $true
$splitModeItem.IsCheckable = $true
[void]$viewModeItem.Items.Add($summaryModeItem)
[void]$viewModeItem.Items.Add($listModeItem)
[void]$viewModeItem.Items.Add($splitModeItem)
[void]$viewModeItem.Items.Add((New-Object Windows.Controls.Separator))
[void]$viewModeItem.Items.Add($mergeAllItem)
$exitItem = New-Object Windows.Controls.MenuItem

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIconPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\codex-monitor-hud.ico'
if (Test-Path -LiteralPath $trayIconPath) {
    $sourceTrayIcon = New-Object System.Drawing.Icon($trayIconPath)
    try { $trayIcon.Icon = $sourceTrayIcon.Clone() } finally { $sourceTrayIcon.Dispose() }
} else { $trayIcon.Icon = [System.Drawing.SystemIcons]::Application }
$trayIcon.Visible = $true
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayStatusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayStatusItem.Enabled = $false
$trayOpenSettingsItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayViewModeItem = New-Object System.Windows.Forms.ToolStripMenuItem
$traySummaryModeItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayListModeItem = New-Object System.Windows.Forms.ToolStripMenuItem
$traySplitModeItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayMergeAllItem = New-Object System.Windows.Forms.ToolStripMenuItem
[void]$trayViewModeItem.DropDownItems.Add($traySummaryModeItem)
[void]$trayViewModeItem.DropDownItems.Add($trayListModeItem)
[void]$trayViewModeItem.DropDownItems.Add($traySplitModeItem)
[void]$trayViewModeItem.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayViewModeItem.DropDownItems.Add($trayMergeAllItem)
$trayDisablePassthroughItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayExitItem = New-Object System.Windows.Forms.ToolStripMenuItem
[void]$trayMenu.Items.Add($trayStatusItem)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayMenu.Items.Add($trayOpenSettingsItem)
[void]$trayMenu.Items.Add($trayViewModeItem)
[void]$trayMenu.Items.Add($trayDisablePassthroughItem)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayMenu.Items.Add($trayExitItem)
$trayIcon.ContextMenuStrip = $trayMenu
$trayOpenSettingsItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Show-HudSettings }) })
$traySummaryModeItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Set-MultiTaskDisplayMode 'summary' }) })
$trayListModeItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Set-MultiTaskDisplayMode 'list' }) })
$traySplitModeItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Split-AllTaskBubbles }) })
$trayMergeAllItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Merge-AllTaskBubbles }) })
$trayDisablePassthroughItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Disable-HudMousePassthrough }) })
$trayExitItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Stop-HudApplication }) })
$trayIcon.Add_DoubleClick({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Show-HudSettings }) })
$statusItem.IsEnabled = $false
[void]$contextMenu.Items.Add($statusItem)
[void]$contextMenu.Items.Add((New-Object Windows.Controls.Separator))
[void]$contextMenu.Items.Add($settingsItem)
[void]$contextMenu.Items.Add($passthroughItem)
[void]$contextMenu.Items.Add($pauseItem)
[void]$contextMenu.Items.Add($positionItem)
[void]$contextMenu.Items.Add($viewModeItem)
[void]$contextMenu.Items.Add((New-Object Windows.Controls.Separator))
[void]$contextMenu.Items.Add($exitItem)
$hud.ContextMenu = $contextMenu
Update-ContextMenuText
$settingsItem.Add_Click({ Show-HudSettings })
$passthroughItem.Add_Click({
    $enablingPassthrough = $false
    if ([bool]$config.mousePassthrough) {
        Disable-HudMousePassthrough
        return
    } else {
        $answer = [Windows.MessageBox]::Show([string]$settingsLocale.mousePassthroughConfirm, [string]$settingsLocale.mousePassthroughTitle, [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Warning)
        if ($answer -ne [Windows.MessageBoxResult]::Yes) { return }
        $config.mousePassthrough = $true
        $enablingPassthrough = $true
    }
    Save-HudConfig $paths $config
    Sync-ControlsFromConfig
    if ($enablingPassthrough) { Show-HudSettings }
    Apply-HudAppearance
    Update-ContextMenuText
})
$pauseItem.Add_Click({
    $script:paused = -not $paused
    Update-ContextMenuText
    Render-Hud
})
$positionItem.Add_Click({ if ([string]$config.position -eq 'custom') { $config.position = 'top-right' }; Move-HudToConfiguredPosition; Position-TaskBubbles; Save-HudConfig $paths $config })
$summaryModeItem.Add_Click({ Set-MultiTaskDisplayMode 'summary' })
$listModeItem.Add_Click({ Set-MultiTaskDisplayMode 'list' })
$splitModeItem.Add_Click({ Split-AllTaskBubbles })
$mergeAllItem.Add_Click({ Merge-AllTaskBubbles })
$exitItem.Add_Click({ Stop-HudApplication })

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(800)
$timer.Add_Tick({
    if (((Get-Date) - $lastHudHeartbeat).TotalSeconds -ge 2) {
        $script:lastHudHeartbeat = Get-Date
        try { [IO.File]::WriteAllText($hudHeartbeat, [DateTime]::UtcNow.ToString('O')) } catch { }
    }
    if ($Managed) {
        $activeHosts = @()
        if (Test-Path -LiteralPath $hostsRoot) {
            $cutoff = [DateTime]::UtcNow.AddSeconds(-8)
            foreach ($hostFile in Get-ChildItem -LiteralPath $hostsRoot -File -Filter '*.heartbeat' -ErrorAction SilentlyContinue) {
                if ($hostFile.LastWriteTimeUtc -ge $cutoff) { $activeHosts += $hostFile }
                else { Remove-Item -LiteralPath $hostFile.FullName -Force -ErrorAction SilentlyContinue }
            }
        }
        $legacyParentAlive = $ParentPid -gt 0 -and $null -ne (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)
        if ($activeHosts.Count -eq 0 -and -not $legacyParentAlive) {
            Stop-HudApplication; return
        }
    }
    if (Test-Path -LiteralPath $openSignal) { Remove-Item -LiteralPath $openSignal -Force -ErrorAction SilentlyContinue; Show-HudSettings }
    if (Test-Path -LiteralPath $showSignal) { Remove-Item -LiteralPath $showSignal -Force -ErrorAction SilentlyContinue; $hud.Show() }
    if (Test-Path -LiteralPath $hideSignal) { Remove-Item -LiteralPath $hideSignal -Force -ErrorAction SilentlyContinue; $hud.Hide() }
    if (Test-Path -LiteralPath $pauseSignal) {
        Remove-Item -LiteralPath $pauseSignal -Force -ErrorAction SilentlyContinue
        $script:paused = -not $paused
        Update-ContextMenuText
        Render-Hud
    }
    if (Test-Path -LiteralPath $passthroughOffSignal) {
        Remove-Item -LiteralPath $passthroughOffSignal -Force -ErrorAction SilentlyContinue
        Disable-HudMousePassthrough
    }
    if (Test-Path -LiteralPath $exitSignal) { Remove-Item -LiteralPath $exitSignal -Force -ErrorAction SilentlyContinue; Stop-HudApplication; return }
    $changed = Process-HudAgentNotifications
    foreach ($state in @($sessionStates.Values)) {
        if ($state.AgentNoticeUntil -ne [DateTimeOffset]::MinValue -and $state.AgentNoticeUntil -le [DateTimeOffset]::Now) {
            $state.AgentNoticeText = ''
            $state.AgentNoticeUntil = [DateTimeOffset]::MinValue
            $state.AgentNoticeRecipe = $null
            if ([string]$state.AttentionReason -eq 'agent') { $state.AttentionUntil = [DateTimeOffset]::MinValue }
            $changed = $true
        }
    }
    if ($paused) { if ($changed) { Update-DisplaySnapshot }; return }
    if (((Get-Date) - $lastFolderScan).TotalSeconds -ge 1.5) {
        $script:lastFolderScan = Get-Date
        if (Refresh-ActiveSessions) { $changed = $true }
    }
    foreach ($state in @($sessionStates.Values)) {
        if (Read-AppendedSessionData $state) { $changed = $true }
        if (Confirm-PendingTaskCompletion $state) { $changed = $true }
        if (Update-TerminalExitState $state) { $changed = $true }
        $taskStatus = Update-TaskStatusTransition $state
        if ([string]$state.LastRenderedStatus -ne $taskStatus) { $changed = $true }
    }
    if ($changed) { Update-DisplaySnapshot }
    else {
        $nextStatus = Get-HudStatus
        if ($nextStatus -ne $currentStatus) { Render-Hud; Update-ContextMenuText }
    }
})

$hud.Add_SourceInitialized({
    $script:hudHandle = (New-Object Windows.Interop.WindowInteropHelper($hud)).Handle
    if ($hudHandle -ne [IntPtr]::Zero) {
        $script:hudBaseExtendedStyle = [HudNativeMethods]::GetWindowLong($hudHandle, -20)
        Set-HudMousePassthrough ([bool]$config.mousePassthrough)
    }
})

$hud.Add_Loaded({
    try {
        Write-HudDebug 'HUD Loaded event started.'
        Sync-ControlsFromConfig
        Render-Hud
        [void](Refresh-ActiveSessions)
        Update-DisplaySnapshot
        Move-HudToConfiguredPosition
        if ($OpenSettings) { Show-HudSettings }
        $timer.Start()
        Write-HudDebug 'HUD Loaded event completed.'
    } catch {
        Write-HudDebug ('HUD Loaded error: ' + ($_ | Out-String))
        throw
    }
})
$hud.Add_Closed({
    $timer.Stop()
    $script:closingApp = $true
    foreach ($path in @($splitWindows.Keys)) { Close-TaskBubble ([string]$path) }
    try { $trayIcon.Visible = $false; $trayIcon.Dispose() } catch { }
    Remove-Item -LiteralPath $hudHeartbeat -Force -ErrorAction SilentlyContinue
    try { $colorPicker.Close() } catch { }
    try { $settings.Close() } catch { }
    Release-HudMutex
})

$application = [Windows.Application]::new()
$application.Add_DispatcherUnhandledException({
    Write-HudDebug ('Dispatcher error: ' + ($_.Exception | Out-String))
    if ($closingApp) { $_.Handled = $true }
})
Write-HudDebug 'Starting WPF application loop.'
$application.Run($hud) | Out-Null
