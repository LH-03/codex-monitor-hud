param(
    [switch]$Managed,
    [int]$ParentPid = 0,
    [switch]$OpenSettings,
    [switch]$SettingsHost,
    [switch]$SelfTest,
    [string]$SelfTestSessionsRoot = '',
    [switch]$DebugLog,
    [string]$InstanceId = '',
    [string]$RenderPreview,
    [string]$RenderSettingsPreview,
    [string]$RenderColorPickerPreview,
    [string]$ImportThemeFile,
    [switch]$PreviewSettingsAdvanced,
    [switch]$PreviewSettingsReminders,
    [ValidateSet('general','sources','multi','behavior','metrics','appearance')][string]$PreviewSettingsTab = 'general',
    [ValidateSet('zh-CN','en','symbols')][string]$PreviewLanguage = 'zh-CN',
    [ValidateSet('chips','compact','inline','outline','cards','stacked')][string]$PreviewLayout = 'chips',
    [ValidateSet('summary','list')][string]$PreviewHudMode = 'summary',
    [ValidateSet('rows','cards','rail')][string]$PreviewListStyle = 'rows',
    [ValidateSet('compact','balanced','relaxed')][string]$PreviewListDensity = 'compact',
    [ValidateSet('hover','always','hidden')][string]$PreviewTaskNameMode = 'always',
    [ValidateSet('none','off','halo','breathe','flow','focus')][string]$PreviewAttentionMode = 'none',
    [ValidateSet('none','overall','horizontal','vertical')][string]$PreviewQuietLayout = 'none',
    [ValidateSet('dot','bar')][string]$PreviewQuietTaskStyle = 'dot',
    [ValidateSet('uniform','layered','focus')][string]$PreviewTransparencyMode = 'uniform',
    # -1 means "leave the selected/default opacity alone"; 0 is a valid
    # explicit preview value for a fully transparent HUD.
    [double]$PreviewOpacity = -1,
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
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetProcessWorkingSetSize(IntPtr process, IntPtr minimum, IntPtr maximum);
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
if ($SelfTest -and -not [string]::IsNullOrWhiteSpace($SelfTestSessionsRoot)) {
    $paths.SessionsRoot = [IO.Path]::GetFullPath($SelfTestSessionsRoot)
}
$debugPath = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_MONITOR_HUD_DEBUG_PATH)) {
    [IO.Path]::GetFullPath($env:CODEX_MONITOR_HUD_DEBUG_PATH)
} else {
    Join-Path $pluginRoot '.test-output\runtime.log'
}

function Write-HudDebug {
    param([string]$Message)
    if (-not $DebugLog) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $debugPath) | Out-Null
    ('{0:O} {1}' -f [DateTime]::Now, $Message) | Add-Content -Encoding UTF8 -LiteralPath $debugPath
}
$openSignal = Join-Path $paths.StateRoot 'open-settings.signal'
$reloadSettingsSignal = Join-Path $paths.StateRoot 'reload-settings.signal'
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
    $mutexSuffix = if ($SettingsHost) { '-settings' } elseif ([string]::IsNullOrWhiteSpace($InstanceId)) { '' } else { '-' + ([regex]::Replace($InstanceId, '[^A-Za-z0-9_.-]', '_')) }
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
    $level = [Math]::Max(0.0,[Math]::Min(1.0,[double]$config.opacity))
    if ([string]$config.transparencyMode -eq 'layered') {
        switch ($Role) {
            'background' { return 0.18 + (0.55 * $level) }
            'primary' { return 1.0 }
            'secondary' { return 0.54 + (0.25 * $level) }
            'decoration' { return 0.28 + (0.27 * $level) }
            default { return 1.0 }
        }
    }
    $status = Get-HudStatus
    $hasAttention = @(Get-HudUserTaskStates | Where-Object { $_.AttentionUntil -gt [DateTimeOffset]::Now }).Count -gt 0
    $focused = $hasAttention -or @('active','completed','aborted','error') -contains $status
    $listening = $status -eq 'listening'
    switch ($Role) {
        'background' { if ($focused) { return 0.62 + (0.30 * $level) }; if ($listening) { return 0.36 + (0.25 * $level) }; return 0.14 + (0.22 * $level) }
        'primary' { if ($focused) { return 1.0 }; if ($listening) { return 0.94 }; return 0.84 }
        'secondary' { if ($focused) { return 0.84 }; if ($listening) { return 0.68 }; return 0.52 }
        'decoration' { if ($focused) { return 0.70 }; if ($listening) { return 0.48 }; return 0.30 }
        default { return 1.0 }
    }
}

function New-HudRoleBrush {
    param([string]$Value, [string]$Fallback = '#FFFFFFFF', [ValidateSet('background','primary','secondary','decoration','status')][string]$Role = 'primary')
    $brush = New-HudBrush $Value $Fallback
    if ([string]$config.transparencyMode -eq 'uniform') {
        if ($Role -eq 'background' -and $brush -is [Windows.Media.SolidColorBrush]) {
            $color = $brush.Color
            $color.A = [byte]255
            return New-Object Windows.Media.SolidColorBrush($color)
        }
        return $brush
    }
    if ($Role -eq 'status' -or $brush -isnot [Windows.Media.SolidColorBrush]) { return $brush }
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
            $brush.Opacity = if ([string]$config.transparencyMode -eq 'uniform') { 1.0 } else { [double]$config.themeStyle.imageOpacity }
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
            if ([string]$config.transparencyMode -eq 'uniform') { $start.A = [byte]255; $end.A = [byte]255 }
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
$hudLocaleCache = @{
    'zh-CN' = Get-HudLocale $paths 'zh-CN'
    'en' = Get-HudLocale $paths 'en'
    'symbols' = Get-HudLocale $paths 'symbols'
}
function Get-RuntimeHudLocale {
    param([string]$Language)
    if ($hudLocaleCache.ContainsKey($Language)) { return $hudLocaleCache[$Language] }
    return $hudLocaleCache['en']
}
$locale = Get-RuntimeHudLocale ([string]$config.language)
$settingsLocale = if ([string]$config.language -eq 'symbols') { Get-RuntimeHudLocale 'en' } else { $locale }
$snapshot = $null
$sessionStates = @{}
$defaultProfileRoot = Split-Path -Parent $paths.SessionsRoot
$profileHome = Split-Path -Parent $defaultProfileRoot
$sessionProfiles = @(
    [pscustomobject]@{
        Id = 'codex'; Label = 'Codex'; SessionsRoot = [string]$paths.SessionsRoot
        SessionIndexPath = Join-Path $defaultProfileRoot 'session_index.jsonl'
        StateDatabasePath = Join-Path $defaultProfileRoot 'state_5.sqlite'
        DefaultClientSurface = 'unknown'; DefaultProvider = ''
    }
)
if (-not $SelfTest -and -not [string]::IsNullOrWhiteSpace($profileHome)) {
    $deepSeekRoot = Join-Path $profileHome '.codex-deepseek'
    $sessionProfiles += [pscustomobject]@{
        Id = 'deepseek'; Label = 'DeepSeek'; SessionsRoot = Join-Path $deepSeekRoot 'sessions'
        SessionIndexPath = Join-Path $deepSeekRoot 'session_index.jsonl'
        StateDatabasePath = Join-Path $deepSeekRoot 'state_5.sqlite'
        DefaultClientSurface = 'cli'; DefaultProvider = 'deepseek'
    }
}
$sessionTitleMaps = @{}
$sessionIndexLastWriteUtc = @{}
foreach ($profile in $sessionProfiles) {
    $sessionTitleMaps[[string]$profile.Id] = @{}
    $sessionIndexLastWriteUtc[[string]$profile.Id] = [DateTime]::MinValue
}
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
$isMainIndicatorCollapsed = $false
$contextMetricContainer = $null
$lastUpdateAnimationSignature = ''
$lastQuietIndicatorSignature = ''
$lastContextMenuSignature = ''
$lastHudAppearanceSignature = ''
$lastHudMetricsStructureSignature = ''
$hudMetricControls = @{}
$summaryNoticeVisible = $false
$lastTaskListRenderSignature = ''
$lastMaterialUpdateAt = [DateTimeOffset]::Now
$lastFullGcAt = [DateTimeOffset]::MinValue
$lastWorkingSetTrimAt = [DateTimeOffset]::MinValue
$memoryTrimPending = $true
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
    codexMicro = [ordered]@{ active='#FF9CD5FE'; listening='#FFFFD0B8'; idle='#FFFFFFFF'; paused='#FFFFD0B8'; error='#FFFF7373'; completed='#FF9BF396'; aborted='#FFFF7373' }
}

$hud = Load-XamlWindow (Join-Path $PSScriptRoot 'HudWindow.xaml')
Set-HudWindowIcon $hud
Write-HudDebug 'HUD XAML loaded.'
$hudShell = Find-Control $hud 'HudShell'
$hudContentPanel = Find-Control $hud 'HudContentPanel'
$statusDot = Find-Control $hud 'StatusDot'
$metricsPanel = Find-Control $hud 'MetricsPanel'
$taskListToggleButton = Find-Control $hud 'TaskListToggleButton'
$taskListDivider = Find-Control $hud 'TaskListDivider'
$taskListScroller = Find-Control $hud 'TaskListScroller'
$taskListPanel = Find-Control $hud 'TaskListPanel'
$quietIndicatorPanel = Find-Control $hud 'QuietIndicatorPanel'
$quietOverallHost = Find-Control $hud 'QuietOverallHost'
$quietOverallRing = Find-Control $hud 'QuietOverallRing'
$quietOverallDot = Find-Control $hud 'QuietOverallDot'
$quietIndicatorSeparator = Find-Control $hud 'QuietIndicatorSeparator'
$quietTaskIndicators = Find-Control $hud 'QuietTaskIndicators'

$loadSettingsUi = $SettingsHost -or -not [string]::IsNullOrWhiteSpace($RenderSettingsPreview) -or -not [string]::IsNullOrWhiteSpace($RenderColorPickerPreview) -or -not [string]::IsNullOrWhiteSpace($ImportThemeFile)
if ($loadSettingsUi) {
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
$behaviorScrollViewer = Find-Control $settings 'BehaviorScrollViewer'
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
$openTaskOnDoubleClickCheck = Find-Control $settings 'OpenTaskOnDoubleClickCheck'
$idleIndicatorEnabledCheck = Find-Control $settings 'IdleIndicatorEnabledCheck'
$idleIndicatorDelayCombo = Find-Control $settings 'IdleIndicatorDelayCombo'
$idleIndicatorLayoutCombo = Find-Control $settings 'IdleIndicatorLayoutCombo'
$idleIndicatorTaskStyleCombo = Find-Control $settings 'IdleIndicatorTaskStyleCombo'
$idleIndicatorBubblesCheck = Find-Control $settings 'IdleIndicatorBubblesCheck'
$contextMetricVisibleCheck = Find-Control $settings 'ContextMetricVisibleCheck'
$contextAlertsEnabledCheck = Find-Control $settings 'ContextAlertsEnabledCheck'
$contextThreshold1Text = Find-Control $settings 'ContextThreshold1Text'
$contextThreshold2Text = Find-Control $settings 'ContextThreshold2Text'
$contextThreshold3Text = Find-Control $settings 'ContextThreshold3Text'
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
    codexMicro = Find-Control $settings 'StatusPaletteCodexMicro'
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
    SourcesTab = Find-Control $settings 'SourcesTab'
    MultiTaskTab = Find-Control $settings 'MultiTaskTab'
    BehaviorTab = Find-Control $settings 'BehaviorTab'
    MetricsTab = Find-Control $settings 'MetricsTab'
    AppearanceTab = Find-Control $settings 'AppearanceTab'
}
$sourceDesktopCheck = Find-Control $settings 'SourceDesktopCheck'
$sourceVsCodeCheck = Find-Control $settings 'SourceVsCodeCheck'
$sourceDefaultCliCheck = Find-Control $settings 'SourceDefaultCliCheck'
$sourceDeepSeekCliCheck = Find-Control $settings 'SourceDeepSeekCliCheck'
$listDetailCombo = Find-Control $settings 'ListDetailCombo'
$bubbleFieldControls = [ordered]@{
    model = Find-Control $settings 'BubbleFieldModel'
    callTotal = Find-Control $settings 'BubbleFieldCallTotal'
    cacheHitRate = Find-Control $settings 'BubbleFieldCacheHitRate'
    taskTotal = Find-Control $settings 'BubbleFieldTaskTotal'
    estimatedCost = Find-Control $settings 'BubbleFieldEstimatedCost'
    updated = Find-Control $settings 'BubbleFieldUpdated'
}

$fieldControls = [ordered]@{}
foreach ($key in @('Input','Cached','CacheHitRate','Uncached','Output','Reasoning','CallTotal','TaskTotal','Context','Model','Updated','ActiveTasks','WeeklyRemaining','FiveHourRemaining','EstimatedCost')) {
    $control = Find-Control $settings ('Field' + $key)
    $fieldControls[[string]$control.Tag] = $control
}

$settingsTextControls = @{}
foreach ($name in @(
    'SettingsSubtitle','PresetsTitle','PresetsHint','ThemeWorkshopTitle','ThemeWorkshopHint','LanguageLayoutTitle','DisplayLanguageLabel','BubbleStyleLabel','SessionSourcesTitle','SessionSourcesHint','SessionSourcesPrivacy','SourceDesktopOptionText','SourceVsCodeOptionText','SourceDefaultCliOptionText','SourceDeepSeekCliOptionText',
    'NumberFormatLabel','PositionLabel','MonitorScopeLabel','ActiveWindowLabel','TaskRetentionLabel','TerminalExitModeLabel','TerminalExitHint','MetricsTitle','MetricsHint','PricingSourceTitle','PricingSourceHint','PricingPathLabel',
    'AppearanceTitle','FontSizeLabel','RadiusLabel','OpacityLabel','BackgroundColorLabel','ForegroundColorLabel','AccentColorLabel',
    'MousePassthroughHint','StatusPalettesTitle','StatusPalettesHint','StatusPaletteCodexMicroSource','MultiTaskTitle','MultiTaskExplanation',
    'DisplayModeLabel','TaskNameModeLabel','MaxSplitLabel','NumberCooldownLabel','ListFieldsTitle','ListDetailHint','TaskBubbleFieldsTitle','TaskBubbleResizeHint',
    'ListDensityLabel',
    'ListStyleLabel','AgentNotificationTitle','AgentNotificationHint','AgentNotificationPermissionLabel','AgentNotificationModeLabel','AgentNotificationGlowPresetLabel','AgentNotificationIntensityLabel','AgentNotificationDurationLabel','AgentNotificationColorLabel',
    'AttentionTitle','AttentionHint','AttentionTriggersTitle','AttentionSurfacesTitle','SummaryAttentionModeLabel','ListAttentionModeLabel','TaskBubbleAttentionModeLabel','AttentionDurationLabel',
    'DotAttentionTitle','DotAttentionHint','DotPatternLabel','DotBrightnessLabel','DotSpeedLabel',
    'TransparencyModeLabel','TransparencyHint','BehaviorTitle','BehaviorHint','TaskNavigationTitle','TaskNavigationHint',
    'IdleIndicatorTitle','IdleIndicatorHint','IdleIndicatorDelayLabel','IdleIndicatorLayoutLabel','IdleIndicatorTaskStyleLabel','ContextAlertsTitle','ContextAlertsHint','ContextThresholdsLabel',
    'ContextThreshold1Hint','ContextThreshold2Hint','ContextThreshold3Hint'
)) { $settingsTextControls[$name] = Find-Control $settings $name }

$settingsContentControls = @{}
foreach ($name in @(
    'PresetFrost','PresetMidnight','PresetAurora','PresetGraphite','PresetMinimal',
        'LanguageZhItem','LanguageEnItem','LanguageSymbolsItem','LayoutChipsItem','LayoutCompactItem','LayoutInlineItem','LayoutOutlineItem','LayoutCardsItem','LayoutStackedItem',
    'NumberExactItem','NumberCompactItem','NumberAutoItem','PositionCustomItem','PositionTopRightItem','PositionTopCenterItem','PositionTopLeftItem',
    'PositionBottomRightItem','PositionBottomCenterItem','PositionBottomLeftItem','MonitorLatestItem','MonitorAggregateItem',
    'ActiveWindow5Item','ActiveWindow15Item','ActiveWindow30Item','ActiveWindow60Item','Retention0Item','Retention30Item','Retention60Item','Retention120Item','Retention300Item','Retention600Item','Retention1800Item',
    'TerminalExitFadeItem','TerminalExitGentleItem','TerminalExitFocusItem','TerminalExitBeaconItem',
    'StatusPaletteDefault','StatusPaletteIntuitive','StatusPaletteColorblind','StatusPaletteCalm','StatusPaletteCodexMicro',
    'ModeSummaryItem','ModeListItem','ModeSplitItem','NameAlwaysItem','NameHiddenItem',
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
    'TransparencyUniformItem','TransparencyLayeredItem','TransparencyFocusItem',
    'IdleIndicator5Item','IdleIndicator15Item','IdleIndicator30Item','IdleIndicator60Item',
    'IdleIndicatorOverallItem','IdleIndicatorHorizontalItem','IdleIndicatorVerticalItem','IdleIndicatorTaskDotItem','IdleIndicatorTaskBarItem'
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
} else {
    $settings = $null
    $colorPicker = $null
}

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
    $zh = Get-RuntimeHudLocale 'zh-CN'
    $en = Get-RuntimeHudLocale 'en'
    if ([string]$config.language -eq 'en') { return ('{0} ({1})' -f [string]$en.$Key, [string]$zh.$Key) }
    if ([string]$config.language -eq 'symbols') { return ('{0} ({1} / {2})' -f [string]$locale.$Key, [string]$zh.$Key, [string]$en.$Key) }
    return ('{0} ({1})' -f [string]$zh.$Key, [string]$en.$Key)
}

function Apply-SettingsLanguage {
    $script:locale = Get-RuntimeHudLocale ([string]$config.language)
    $script:settingsLocale = if ([string]$config.language -eq 'symbols') { Get-RuntimeHudLocale 'en' } else { $locale }
    $map = @{
        SettingsSubtitle='settingsSubtitle'; PresetsTitle='presetsTitle'; PresetsHint='presetsHint'; ThemeWorkshopTitle='themeWorkshopTitle'; ThemeWorkshopHint='themeWorkshopHint';
        LanguageLayoutTitle='languageLayoutTitle'; DisplayLanguageLabel='displayLanguage'; BubbleStyleLabel='bubbleStyle';
        SessionSourcesTitle='sessionSourcesTitle'; SessionSourcesHint='sessionSourcesHint'; SessionSourcesPrivacy='sessionSourcesPrivacy'; SourceDesktopOptionText='sourceDesktopOption'; SourceVsCodeOptionText='sourceVsCodeOption'; SourceDefaultCliOptionText='sourceDefaultCliOption'; SourceDeepSeekCliOptionText='sourceDeepSeekCliOption';
        NumberFormatLabel='numberFormat'; PositionLabel='position'; MonitorScopeLabel='monitorScope'; ActiveWindowLabel='activeWindow'; TaskRetentionLabel='taskRetention'; TerminalExitModeLabel='terminalExitMode'; TerminalExitHint='terminalExitHint';
        MetricsTitle='metricsTitle'; MetricsHint='metricsHint'; PricingSourceTitle='pricingSourceTitle'; PricingSourceHint='pricingSourceHint'; PricingPathLabel='pricingPathLabel'; AppearanceTitle='appearanceTitle'; FontSizeLabel='fontSize';
        RadiusLabel='cornerRadius'; OpacityLabel='opacity'; BackgroundColorLabel='backgroundColor';
        ForegroundColorLabel='foregroundColor'; AccentColorLabel='accentColor'; MousePassthroughHint='mousePassthroughHint';
        StatusPalettesTitle='statusPalettesTitle'; StatusPalettesHint='statusPalettesHint'; StatusPaletteCodexMicroSource='statusPaletteCodexMicroSource';
        MultiTaskTitle='multiTaskTitle'; MultiTaskExplanation='multiTaskExplanation'; DisplayModeLabel='displayMode';
        ListStyleLabel='listStyle'; ListDensityLabel='listDensity'; TaskNameModeLabel='taskNameMode'; MaxSplitLabel='maxSplitBubbles'; NumberCooldownLabel='numberCooldown';
        ListFieldsTitle='listFieldsTitle'; ListDetailHint='listDetailHint'; TaskBubbleFieldsTitle='taskBubbleFieldsTitle'; TaskBubbleResizeHint='taskBubbleResizeHint';
        AgentNotificationTitle='agentNotificationTitle'; AgentNotificationHint='agentNotificationHint'; AgentNotificationPermissionLabel='agentNotificationPermission';
        AgentNotificationModeLabel='agentNotificationMode'; AgentNotificationGlowPresetLabel='agentNotificationGlowPreset'; AgentNotificationIntensityLabel='agentNotificationIntensity';
        AgentNotificationDurationLabel='agentNotificationDuration'; AgentNotificationColorLabel='agentNotificationColor';
        AttentionTitle='attentionTitle'; AttentionHint='attentionHint'; AttentionTriggersTitle='attentionTriggersTitle'; AttentionSurfacesTitle='attentionSurfacesTitle';
        SummaryAttentionModeLabel='attentionSummaryMode'; ListAttentionModeLabel='attentionListMode'; TaskBubbleAttentionModeLabel='attentionTaskBubbleMode'; AttentionDurationLabel='attentionDuration';
        DotAttentionTitle='dotAttentionTitle'; DotAttentionHint='dotAttentionHint'; DotPatternLabel='dotPattern'; DotBrightnessLabel='dotBrightness'; DotSpeedLabel='dotSpeed';
        TransparencyModeLabel='transparencyMode'; TransparencyHint='transparencyHint';
        BehaviorTitle='behaviorTitle'; BehaviorHint='behaviorHint'; TaskNavigationTitle='taskNavigationTitle'; TaskNavigationHint='taskNavigationHint';
        IdleIndicatorTitle='idleIndicatorTitle'; IdleIndicatorHint='idleIndicatorHint'; IdleIndicatorDelayLabel='idleIndicatorDelay'; IdleIndicatorLayoutLabel='idleIndicatorLayout'; IdleIndicatorTaskStyleLabel='idleIndicatorTaskStyle';
        ContextAlertsTitle='contextAlertsTitle'; ContextAlertsHint='contextAlertsHint'; ContextThresholdsLabel='contextThresholds';
        ContextThreshold1Hint='contextThresholdEarly'; ContextThreshold2Hint='contextThresholdWatch'; ContextThreshold3Hint='contextThresholdCritical'
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
        StatusPaletteColorblind='statusPaletteColorblind'; StatusPaletteCalm='statusPaletteCalm'; StatusPaletteCodexMicro='statusPaletteCodexMicro';
        ModeSummaryItem='modeSummary'; ModeListItem='modeList'; ModeSplitItem='modeSplit';
        ListRowsItem='listRows'; ListCardsItem='listCards'; ListRailItem='listRail';
        ListDensityCompactItem='listDensityCompact'; ListDensityBalancedItem='listDensityBalanced'; ListDensityRelaxedItem='listDensityRelaxed';
        NameAlwaysItem='nameAlways'; NameHiddenItem='nameHidden';
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
        TransparencyUniformItem='transparencyUniform'; TransparencyLayeredItem='transparencyLayered'; TransparencyFocusItem='transparencyFocus';
        IdleIndicator5Item='minutes5'; IdleIndicator15Item='minutes15'; IdleIndicator30Item='minutes30'; IdleIndicator60Item='minutes60';
        IdleIndicatorOverallItem='idleIndicatorOverall'; IdleIndicatorHorizontalItem='idleIndicatorHorizontal'; IdleIndicatorVerticalItem='idleIndicatorVertical';
        IdleIndicatorTaskDotItem='idleIndicatorTaskDot'; IdleIndicatorTaskBarItem='idleIndicatorTaskBar'
    }
    foreach ($name in $contentMap.Keys) { $settingsContentControls[$name].Content = [string]$settingsLocale.($contentMap[$name]) }
    $zhLocale = Get-RuntimeHudLocale 'zh-CN'
    $enLocale = Get-RuntimeHudLocale 'en'
    $settingsTextControls['DisplayLanguageLabel'].Text = ('{0} / {1}' -f [string]$zhLocale.displayLanguage, [string]$enLocale.displayLanguage)
    $settingsContentControls['LanguageZhItem'].Content = ('{0} ({1})' -f [string]$zhLocale.languageZh, [string]$enLocale.languageZh)
    $settingsContentControls['LanguageEnItem'].Content = ('{0} ({1})' -f [string]$enLocale.languageEn, [string]$zhLocale.languageEn)
    $settingsContentControls['LanguageSymbolsItem'].Content = ('{0} ({1})' -f [string]$zhLocale.languageSymbols, [string]$enLocale.languageSymbols)
    Update-ThemeButtonLabels

    $english = Get-RuntimeHudLocale 'en'
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
    $openTaskOnDoubleClickCheck.Content = [string]$settingsLocale.openTaskOnDoubleClick
    $idleIndicatorEnabledCheck.Content = [string]$settingsLocale.idleIndicatorEnabled
    $idleIndicatorBubblesCheck.Content = [string]$settingsLocale.idleIndicatorBubbles
    $contextMetricVisibleCheck.Content = [string]$settingsLocale.contextMetricVisible
    $contextAlertsEnabledCheck.Content = [string]$settingsLocale.contextAlertsEnabled
    $settings.FindName('ListDetailCompactItem').Content = [string]$settingsLocale.listDetailCompact
    $settings.FindName('ListDetailBalancedItem').Content = [string]$settingsLocale.listDetailBalanced
    $settings.FindName('ListDetailDetailedItem').Content = [string]$settingsLocale.listDetailDetailed
    $settings.FindName('ListDetailDetailedItem').ToolTip = [string]$settingsLocale.cacheHitRateTooltip
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
    $bubbleFieldControls['estimatedCost'].ToolTip = [string]$settingsLocale.estimatedCostTooltip
    $fieldControls['cacheHitRate'].ToolTip = [string]$settingsLocale.cacheHitRateTooltip
    $bubbleFieldControls['cacheHitRate'].ToolTip = [string]$settingsLocale.cacheHitRateTooltip
    $pricingPathText.ToolTip = [string]$settingsLocale.pricingPathTooltip
    foreach ($key in $bubbleFieldControls.Keys) { $bubbleFieldControls[$key].Content = [string]$settingsLocale.$key }
    $settingsTabControls['GeneralTab'].Header = [string]$settingsLocale.generalTab
    $settingsTabControls['SourcesTab'].Header = [string]$settingsLocale.sourcesTab
    $settingsTabControls['MultiTaskTab'].Header = [string]$settingsLocale.multiTaskTab
    $settingsTabControls['BehaviorTab'].Header = [string]$settingsLocale.behaviorTab
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
    $pickerLocale = if ($Language -eq 'en') { Get-RuntimeHudLocale 'en' } else { Get-RuntimeHudLocale 'zh-CN' }
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

if ($loadSettingsUi) {
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
    $colorPicker.Add_Closing({if(-not$SettingsHost-and-not$closingApp){$_.Cancel=$true;$colorPicker.Hide()}})
}

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
    $screen = [pscustomobject]@{
        Left = [Windows.SystemParameters]::VirtualScreenLeft
        Top = [Windows.SystemParameters]::VirtualScreenTop
        Width = [Windows.SystemParameters]::VirtualScreenWidth
        Height = [Windows.SystemParameters]::VirtualScreenHeight
        Right = [Windows.SystemParameters]::VirtualScreenLeft + [Windows.SystemParameters]::VirtualScreenWidth
        Bottom = [Windows.SystemParameters]::VirtualScreenTop + [Windows.SystemParameters]::VirtualScreenHeight
    }
    $hud.MaxWidth = [Math]::Max(480,$screen.Width + 36)
    $hud.UpdateLayout()
    $inset = 18.0
    $minLeft = $screen.Left - $inset
    $minTop = $screen.Top - $inset
    $maxLeft = [Math]::Max($minLeft,$screen.Right - $hud.ActualWidth + $inset)
    $maxTop = [Math]::Max($minTop,$screen.Bottom - $hud.ActualHeight + $inset)
    $left = $maxLeft
    $top = $minTop
    switch ([string]$config.position) {
        'top-left' { $left = $minLeft; $top = $minTop }
        'top-center' { $left = $screen.Left + (($screen.Width - $hud.ActualWidth) / 2); $top = $minTop }
        'top-right' { $left = $maxLeft; $top = $minTop }
        'bottom-left' { $left = $minLeft; $top = $maxTop }
        'bottom-center' { $left = $screen.Left + (($screen.Width - $hud.ActualWidth) / 2); $top = $maxTop }
        'bottom-right' { $left = $maxLeft; $top = $maxTop }
        'custom' {
            if ($null -ne $config.customLeft) { $left = [double]$config.customLeft - $inset }
            if ($null -ne $config.customTop) { $top = [double]$config.customTop - $inset }
        }
    }
    $hud.Left = [Math]::Max($minLeft, [Math]::Min($left, $maxLeft))
    $hud.Top = [Math]::Max($minTop, [Math]::Min($top, $maxTop))
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
    return $text
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
    if ([string]$Metric.Key -eq 'context') { $script:contextMetricContainer = $container }
    [void]$metricsPanel.Children.Add($container)
    return [pscustomobject]@{ Label=$label; Value=$value; Container=$container }
}

function Get-NextTaskNumber {
    return Get-HudTaskNumber $taskNumberPool
}

function Release-TaskNumber {
    param([int]$Number)
    Add-HudReleasedTaskNumber $taskNumberPool $Number ([int]$config.multiTask.numberCooldownSeconds)
}

function Get-TaskSourceLabel {
    param($State)
    $client = if ($null -ne $State.PSObject.Properties['ClientSurface']) { [string]$State.ClientSurface } else { 'unknown' }
    $provider = if ($null -ne $State.PSObject.Properties['ModelProvider']) { [string]$State.ModelProvider } else { '' }
    $profile = if ($null -ne $State.PSObject.Properties['ProfileId']) { [string]$State.ProfileId } else { 'codex' }
    if ($client -eq 'desktop') { return [string]$settingsLocale.sourceDesktop }
    if ($client -eq 'vscode') { return [string]$settingsLocale.sourceVsCode }
    if ($client -eq 'cli' -or $profile -eq 'deepseek') {
        if ($provider -eq 'deepseek' -or $profile -eq 'deepseek') { return [string]$settingsLocale.sourceCliDeepSeek }
        if ([string]::IsNullOrWhiteSpace($provider) -or $provider -eq 'openai') { return [string]$settingsLocale.sourceCliOpenAI }
        $shortProvider = $provider.Trim()
        if ($shortProvider.Length -gt 18) { $shortProvider = $shortProvider.Substring(0,18) }
        return ('{0} {1} {2}' -f [string]$settingsLocale.sourceCli,[char]0x00B7,$shortProvider)
    }
    return [string]$settingsLocale.sourceUnknown
}

function Get-TaskSourceColor {
    param($State)
    $client = if ($null -ne $State.PSObject.Properties['ClientSurface']) { [string]$State.ClientSurface } else { 'unknown' }
    $provider = if ($null -ne $State.PSObject.Properties['ModelProvider']) { [string]$State.ModelProvider } else { '' }
    $profile = if ($null -ne $State.PSObject.Properties['ProfileId']) { [string]$State.ProfileId } else { 'codex' }
    if ($client -eq 'desktop') { return [string]$config.accent }
    if ($client -eq 'vscode') { return '#FF007ACC' }
    if ($provider -eq 'deepseek' -or $profile -eq 'deepseek') { return '#FF00A7B5' }
    if ($client -eq 'cli') { return '#FF8B5CF6' }
    return [string]$config.muted
}

function Get-TaskSourceGeometry {
    param($State)
    $client = if ($null -ne $State.PSObject.Properties['ClientSurface']) { [string]$State.ClientSurface } else { 'unknown' }
    $provider = if ($null -ne $State.PSObject.Properties['ModelProvider']) { [string]$State.ModelProvider } else { '' }
    $profile = if ($null -ne $State.PSObject.Properties['ProfileId']) { [string]$State.ProfileId } else { 'codex' }
    if ($client -eq 'desktop') { return 'M1.4,2.1 L12.6,2.1 Q13,2.1 13,2.5 L13,11.5 Q13,11.9 12.6,11.9 L1.4,11.9 Q1,11.9 1,11.5 L1,2.5 Q1,2.1 1.4,2.1 Z M1.4,4.8 L12.6,4.8 M3,3.45 L3.08,3.45 M4.75,3.45 L4.83,3.45' }
    if ($client -eq 'vscode') { return 'M11.52,0.29 A0.98,0.98 0 0 0 10.82,0.33 L4.21,3.33 L1.5,1.29 A1,1 0 0 0 0,2.09 L0,13.91 A1,1 0 0 0 1.5,14.71 L4.21,12.68 L10.82,15.67 A0.98,0.98 0 0 0 11.52,15.71 L15,14.11 A1,1 0 0 0 15.6,13 L15.6,3 A1,1 0 0 0 15,2.09 Z M11,11.26 L5.73,8 L11,4.74 Z' }
    if ($provider -eq 'deepseek' -or $profile -eq 'deepseek') { return 'M1.4,2.1 L12.6,2.1 Q13,2.1 13,2.5 L13,11.5 Q13,11.9 12.6,11.9 L1.4,11.9 Q1,11.9 1,11.5 L1,2.5 Q1,2.1 1.4,2.1 Z M2.8,8.4 C4.1,5.7 5.55,10.4 7.05,7.65 C8.15,5.65 9.3,7.25 11.2,5.75' }
    return 'M1.4,2.1 L12.6,2.1 Q13,2.1 13,2.5 L13,11.5 Q13,11.9 12.6,11.9 L1.4,11.9 Q1,11.9 1,11.5 L1,2.5 Q1,2.1 1.4,2.1 Z M3,5.15 L5.85,7.15 L3,9.15 M7.15,9.15 L10.65,9.15'
}

function New-HudTaskSourceBadge {
    param($State, [double]$CornerRadius = 7, $Margin = $null)
    $colorText = Get-TaskSourceColor $State
    $label = Get-TaskSourceLabel $State
    $icon = New-Object Windows.Shapes.Path
    $icon.Data = [Windows.Media.Geometry]::Parse((Get-TaskSourceGeometry $State))
    $icon.Stroke = New-HudRoleBrush $colorText '#FF64748B' 'primary'
    $icon.StrokeThickness = 1.45
    $icon.StrokeStartLineCap = [Windows.Media.PenLineCap]::Round
    $icon.StrokeEndLineCap = [Windows.Media.PenLineCap]::Round
    $icon.StrokeLineJoin = [Windows.Media.PenLineJoin]::Round
    if ([string]$State.ClientSurface -eq 'vscode') { $icon.Fill = $icon.Stroke }
    if ([string]$State.ClientSurface -eq 'vscode') { $icon.StrokeThickness = 0.45 }
    $viewbox = New-Object Windows.Controls.Viewbox
    $viewbox.Width = 14; $viewbox.Height = 14; $viewbox.Child = $icon
    $badge = New-Object Windows.Controls.Border
    $badge.CornerRadius = New-Object Windows.CornerRadius($CornerRadius)
    $badge.Padding = New-Object Windows.Thickness(4,3,4,3)
    $badge.Margin = if ($null -ne $Margin) { $Margin } else { New-Object Windows.Thickness(0,1,6,1) }
    $baseColor = [Windows.Media.ColorConverter]::ConvertFromString($colorText)
    $fill = $baseColor; $fill.A = 24
    $stroke = $baseColor; $stroke.A = 72
    $badge.Background = New-Object Windows.Media.SolidColorBrush($fill)
    $badge.BorderBrush = New-Object Windows.Media.SolidColorBrush($stroke)
    $badge.BorderThickness = New-Object Windows.Thickness(1)
    $badge.ToolTip = $label
    $badge.Child = $viewbox
    return $badge
}

function Test-HudDesktopTask {
    param($State)
    return $null -ne $State -and $null -ne $State.PSObject.Properties['ClientSurface'] -and [string]$State.ClientSurface -eq 'desktop'
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

function Get-TaskListSubtitle {
    param($State, [switch]$IncludeConversationTitle)
    $time = ([DateTimeOffset]$State.StartedAt).ToLocalTime().ToString('HH:mm')
    $label = if ($null -ne $State.PSObject.Properties['ConversationLabel']) { [string]$State.ConversationLabel } else { '' }
    if (-not $IncludeConversationTitle -or [string]$config.multiTask.nameMode -eq 'hidden' -or [string]::IsNullOrWhiteSpace($label)) { return $time }
    return ('{0} {1} {2}' -f $label,[char]0x00B7,$time)
}

function Test-HudUserTaskState {
    param($State)
    if ($null -eq $State) { return $false }
    # Do not render a task until its identity header is available. This keeps a
    # just-created auto-review/subagent file out of the UI instead of showing
    # it briefly as a separate user conversation.
    if ($null -ne $State.PSObject.Properties['IdentityMetadataFound'] -and -not [bool]$State.IdentityMetadataFound) { return $false }
    if ($null -ne $State.PSObject.Properties['IsInternalSession'] -and [bool]$State.IsInternalSession) { return $false }
    if ($null -ne $State.PSObject.Properties['Dismissed'] -and [bool]$State.Dismissed) { return $false }
    $profile = if ($null -ne $State.PSObject.Properties['ProfileId']) { [string]$State.ProfileId } else { 'codex' }
    $client = if ($null -ne $State.PSObject.Properties['ClientSurface']) { [string]$State.ClientSurface } else { 'unknown' }
    if ($profile -eq 'deepseek') {
        if (-not [bool]$config.sessionSources.deepSeekCli) { return $false }
    } elseif (($client -eq 'desktop' -and -not [bool]$config.sessionSources.desktop) -or
              ($client -eq 'vscode' -and -not [bool]$config.sessionSources.vscode) -or
              ($client -eq 'cli' -and -not [bool]$config.sessionSources.defaultCli) -or
              ($client -eq 'unknown' -and -not ([bool]$config.sessionSources.desktop -or [bool]$config.sessionSources.vscode -or [bool]$config.sessionSources.defaultCli))) {
        return $false
    }
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
    if ($null -ne $State.PSObject.Properties['RuntimeActivityAt'] -and
        $State.RuntimeActivityAt -ne [DateTimeOffset]::MinValue -and
        ([DateTimeOffset]::Now - [DateTimeOffset]$State.RuntimeActivityAt).TotalMinutes -le 3) { return 'active' }
    if (($null -ne $State.PSObject.Properties['IsReadBlocked'] -and [bool]$State.IsReadBlocked) -or
        ($null -ne $State.PSObject.Properties['IdentityProvisional'] -and [bool]$State.IdentityProvisional) -or
        ($null -ne $State.PSObject.Properties['NeedsSnapshotHydration'] -and [bool]$State.NeedsSnapshotHydration)) { return 'listening' }
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
    $statusLocale = if ([string]$config.language -eq 'symbols') { $locale } else { $settingsLocale }
    return [string]$statusLocale.$key
}

function Open-HudTaskInCodex {
    param($State)
    if (-not [bool]$config.behavior.openTaskOnDoubleClick -or $null -eq $State) { return $false }
    if (-not (Test-HudDesktopTask $State)) {
        Write-HudDebug ('Desktop deep link skipped for {0}/{1} task #{2}.' -f [string]$State.ClientSurface,[string]$State.ModelProvider,[int]$State.Number)
        return $false
    }
    $threadId = [string]$State.SessionId
    $deepLink = Get-HudTaskDeepLink $threadId
    if ([string]::IsNullOrWhiteSpace([string]$deepLink)) { return $false }
    try {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $deepLink
        $startInfo.UseShellExecute = $true
        [void][Diagnostics.Process]::Start($startInfo)
        Write-HudDebug ('Opened Codex task: ' + $threadId)
        return $true
    } catch {
        Write-HudDebug ('Codex task deep link failed: ' + $_.Exception.Message)
        return $false
    }
}

function Open-HudTaskByPath {
    param([string]$Path)
    if (-not $sessionStates.ContainsKey($Path)) { return $false }
    return Open-HudTaskInCodex $sessionStates[$Path]
}

function Update-HudContextAlertState {
    param($State)
    if ($null -eq $State -or $null -eq $State.Snapshot) { return $false }
    if (-not [bool]$config.behavior.contextAlerts.enabled -or -not [bool]$config.fields.context) { return $false }
    $nextLevel = Get-HudContextAlertLevel ([double]$State.Snapshot.ContextPercent) $config.behavior.contextAlerts.thresholds
    $previousLevel = [int]$State.ContextAlertLevel
    $State.ContextAlertLevel = $nextLevel
    if ($nextLevel -le $previousLevel) { return $false }
    $State.ContextAlertPercent = [Math]::Round([double]$State.Snapshot.ContextPercent,1)
    $State.ContextAlertUntil = [DateTimeOffset]::Now.AddSeconds([int]$config.attention.durationSeconds)
    $script:attentionSequence++
    $State.AttentionRevision = $script:attentionSequence
    $State.AttentionReason = 'context'
    $State.AttentionUntil = $State.ContextAlertUntil
    Write-HudDebug ('Context alert: {0} {1}% level={2} r{3}' -f [string]$State.Workspace,[double]$State.ContextAlertPercent,$nextLevel,[int]$State.AttentionRevision)
    return $true
}

function Reset-HudContextAlertRuntime {
    foreach ($state in @($sessionStates.Values)) {
        $state.ContextAlertLevel = 0
        $state.ContextAlertPercent = 0.0
        $state.ContextAlertUntil = [DateTimeOffset]::MinValue
        if ([string]$state.AttentionReason -eq 'context') {
            $state.AttentionReason = ''
            $state.AttentionUntil = [DateTimeOffset]::MinValue
        }
    }
    Stop-HudContextAlertAnimation $contextMetricContainer
    foreach ($entry in @($splitWindows.Values)) { Stop-HudContextAlertAnimation $entry.ContextMetric }
}

function Get-HudContextAlertText {
    param($State)
    if ($null -eq $State -or $State.ContextAlertUntil -le [DateTimeOffset]::Now) { return '' }
    return ('{0} {1:0.#}%' -f [string]$settingsLocale.contextAlertBadge,[double]$State.ContextAlertPercent)
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
    $State.PendingCompletionAt = [DateTimeOffset]::MinValue
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
    # A numbered quiet row/column is a memory aid. Keep terminal tasks visible
    # in their completed/aborted color until the user wakes the HUD, then resume
    # the configured terminal departure timer on the expanded surface.
    if ([bool]$script:isMainIndicatorCollapsed -and (Test-HudQuietLayoutShowsTasks)) { return $false }
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
    $continuationThreshold = ([DateTimeOffset]$State.PendingCompletionAt).AddSeconds([Math]::Max(2,[int]$config.attention.completionGraceSeconds))
    if ($State.PendingCompletionAt -ne [DateTimeOffset]::MinValue -and
        $State.RuntimeActivityAt -gt $continuationThreshold) {
        Clear-PendingTaskCompletion $State
        return $true
    }
    $State.TerminalStatus = 'completed'
    $State.TerminalAt = if ($State.PendingCompletionAt -ne [DateTimeOffset]::MinValue) { [DateTimeOffset]$State.PendingCompletionAt } else { [DateTimeOffset]::Now }
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

function Get-HudContextAlertVisualSpec {
    param([int]$Level)
    switch ($Level) {
        1 { return [pscustomobject]@{ Color='#FF0A84FF'; Glow=0.42; Blur=14.0; Scale=1.012; CycleMs=760 } }
        2 { return [pscustomobject]@{ Color='#FFFF9F0A'; Glow=0.74; Blur=28.0; Scale=1.028; CycleMs=580 } }
        default { return [pscustomobject]@{ Color='#FFFF453A'; Glow=1.00; Blur=42.0; Scale=1.050; CycleMs=420 } }
    }
}

function Start-HudContextAlertAnimation {
    param($Target, [int]$Level)
    if ($null -eq $Target) { return }
    $spec = Get-HudContextAlertVisualSpec $Level
    $profile = Get-HudEffectProfile ([string]$spec.Color) ([double]$spec.Glow) ([double]$spec.Blur)
    $cycles = [Math]::Max(2,[Math]::Ceiling(([int]$config.attention.durationSeconds * 1000.0) / [double]$spec.CycleMs))
    $repeat = New-Object Windows.Media.Animation.RepeatBehavior([double]$cycles)
    $effect = New-Object Windows.Media.Effects.DropShadowEffect
    try { $effect.Color = [Windows.Media.ColorConverter]::ConvertFromString([string]$profile.Color) } catch { $effect.Color = [Windows.Media.Colors]::DodgerBlue }
    $effect.ShadowDepth = 0; $effect.BlurRadius = [double]$profile.Blur; $effect.Opacity = 0
    $Target.Effect = $effect
    $glow = New-Object Windows.Media.Animation.DoubleAnimation([double]$profile.MinimumOpacity,[double]$profile.PeakOpacity,(New-Object Windows.Duration([TimeSpan]::FromMilliseconds([int]$spec.CycleMs / 2))))
    $glow.AutoReverse = $true; $glow.RepeatBehavior = $repeat; $glow.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
    $effect.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty,$glow)
    $Target.RenderTransformOrigin = New-Object Windows.Point(0.5,0.5)
    $scale = New-Object Windows.Media.ScaleTransform(1.0,1.0)
    $Target.RenderTransform = $scale
    foreach ($property in @([Windows.Media.ScaleTransform]::ScaleXProperty,[Windows.Media.ScaleTransform]::ScaleYProperty)) {
        $pulse = New-Object Windows.Media.Animation.DoubleAnimation(1.0,[double]$spec.Scale,(New-Object Windows.Duration([TimeSpan]::FromMilliseconds([int]$spec.CycleMs / 2))))
        $pulse.AutoReverse = $true; $pulse.RepeatBehavior = $repeat; $pulse.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $scale.BeginAnimation($property,$pulse)
    }
    Write-HudDebug ('Context visual alert: level={0}' -f $Level)
}

function Stop-HudContextAlertAnimation {
    param($Target)
    if ($null -eq $Target) { return }
    try { if ($null -ne $Target.Effect) { $Target.Effect.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty,$null) } } catch { }
    $Target.Effect = $null
    $Target.RenderTransform = [Windows.Media.Transform]::Identity
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
    $metricLocale = if ([string]$config.language -eq 'symbols') { $locale } else { $settingsLocale }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((Get-TaskStatusText (Get-TaskStatus $State)))
    if ([bool]$fields.model -and -not [string]::IsNullOrWhiteSpace([string]$State.Snapshot.Model)) { [void]$parts.Add([string]$State.Snapshot.Model) }
    if ([bool]$fields.callTotal) { [void]$parts.Add(('{0} {1}' -f [string]$metricLocale.callTotal, (Format-HudNumber ([Int64]$State.Snapshot.CallTotal) ([string]$config.numberFormat)))) }
    if ([bool]$fields.cacheHitRate) { [void]$parts.Add(('{0} {1}' -f [string]$metricLocale.cacheHitRate, (Format-HudCacheHitRate ([Int64]$State.Snapshot.Input) ([Int64]$State.Snapshot.Cached)))) }
    if ([bool]$fields.taskTotal) { [void]$parts.Add(('{0} {1}' -f [string]$metricLocale.taskTotal, (Format-HudNumber ([Int64]$State.Snapshot.TaskTotal) ([string]$config.numberFormat)))) }
    if ([bool]$fields.estimatedCost) {
        $taskCost = if ($null -ne $State.Snapshot.PSObject.Properties['EstimatedCostUsd']) { $State.Snapshot.EstimatedCostUsd } else { $null }
        [void]$parts.Add(('{0} {1}' -f [string]$metricLocale.estimatedCost, (Format-HudCost $taskCost)))
    }
    if ([bool]$fields.updated) { [void]$parts.Add($State.Snapshot.Timestamp.ToString('HH:mm:ss')) }
    $metricsText = ($parts -join (' {0} ' -f [char]0x00B7))
    $noticeText = Get-HudAgentNoticeText $State
    $showNoticeHere = -not [string]::IsNullOrWhiteSpace($noticeText) -and ($Surface -eq 'bubble' -or ([string]$config.multiTask.displayMode -eq 'list' -and -not [bool]$State.Detached))
    if ($showNoticeHere) { return ('✦ {0}  ·  {1}' -f $noticeText,$metricsText) }
    return $metricsText
}

function Get-TaskListMetricsText {
    param($State)
    if ($null -eq $State.Snapshot) { return [string]$settingsLocale.waiting }
    $snapshot = $State.Snapshot
    $metricLocale = if ([string]$config.language -eq 'symbols') { $locale } else { $settingsLocale }
    $detail = [string]$config.multiTask.listDetail
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((Get-TaskStatusText (Get-TaskStatus $State)))
    if (-not [string]::IsNullOrWhiteSpace([string]$snapshot.Model)) { [void]$parts.Add([string]$snapshot.Model) }
    [void]$parts.Add(('{0} {1}' -f [string]$metricLocale.cacheHitRate,(Format-HudCacheHitRate ([Int64]$snapshot.Input) ([Int64]$snapshot.Cached))))
    if ($detail -in @('balanced','detailed')) {
        [void]$parts.Add(('{0} {1}' -f [string]$metricLocale.callTotal,(Format-HudNumber ([Int64]$snapshot.CallTotal) ([string]$config.numberFormat))))
    }
    if ($detail -eq 'detailed') {
        $diagnostics = New-Object System.Collections.ArrayList
        foreach ($entry in @(
            @([string]$metricLocale.input,(Format-HudNumber ([Int64]$snapshot.Input) ([string]$config.numberFormat))),
            @([string]$metricLocale.cached,(Format-HudNumber ([Int64]$snapshot.Cached) ([string]$config.numberFormat))),
            @([string]$metricLocale.uncached,(Format-HudNumber ([Int64]$snapshot.Uncached) ([string]$config.numberFormat))),
            @([string]$metricLocale.output,(Format-HudNumber ([Int64]$snapshot.Output) ([string]$config.numberFormat))),
            @([string]$metricLocale.taskTotal,(Format-HudNumber ([Int64]$snapshot.TaskTotal) ([string]$config.numberFormat))),
            @([string]$metricLocale.contextWindow,$(if ([Int64]$snapshot.ContextWindow -gt 0) { Format-HudNumber ([Int64]$snapshot.ContextWindow) ([string]$config.numberFormat) } else { '--' })),
            @([string]$metricLocale.updated,$snapshot.Timestamp.ToString('HH:mm:ss'))
        )) { [void]$diagnostics.Add(('{0} {1}' -f $entry[0],$entry[1])) }
        return (($parts -join (' {0} ' -f [char]0x00B7)) + [Environment]::NewLine + ($diagnostics -join (' {0} ' -f [char]0x00B7)))
    }
    return ($parts -join (' {0} ' -f [char]0x00B7))
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
    $sourceColor = Get-TaskSourceColor $State
    $entry.SourceIcon.Data = [Windows.Media.Geometry]::Parse((Get-TaskSourceGeometry $State))
    $entry.SourceIcon.Stroke = New-HudRoleBrush $sourceColor '#FF64748B' 'primary'
    $sourceBase = [Windows.Media.ColorConverter]::ConvertFromString($sourceColor)
    $sourceFill = $sourceBase; $sourceFill.A = 24
    $sourceStroke = $sourceBase; $sourceStroke.A = 72
    $entry.SourceBadge.Background = New-Object Windows.Media.SolidColorBrush($sourceFill)
    $entry.SourceBadge.BorderBrush = New-Object Windows.Media.SolidColorBrush($sourceStroke)
    $entry.SourceBadge.ToolTip = Get-TaskSourceLabel $State
    $entry.Name.Text = Get-TaskDisplayName $State
    $entry.Name.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary'
    $entry.ContextMetric.Visibility = if ([bool]$config.fields.context) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    $entry.ContextText.Text = if ($null -ne $State.Snapshot) { ('{0} {1}' -f [string]$settingsLocale.context,$(if ([Int64]$State.Snapshot.ContextWindow -gt 0) { Format-HudPercent ([double]$State.Snapshot.ContextPercent) } else { '--' })) } else { [string]$settingsLocale.waiting }
    $entry.ContextText.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary'
    $entry.ContextMetric.BorderBrush = New-HudRoleBrush '#330A84FF' '#330A84FF' 'decoration'
    $entry.ContextMetric.Background = New-HudRoleBrush '#0D0A84FF' '#0D0A84FF' 'decoration'
    if (-not [bool]$config.fields.context -or [string]$State.AttentionReason -ne 'context' -or $State.ContextAlertUntil -le [DateTimeOffset]::Now) { Stop-HudContextAlertAnimation $entry.ContextMetric }
    $entry.Metrics.Text = Get-TaskMetricsText $State -Surface bubble
    $entry.Metrics.Foreground = New-HudRoleBrush ([string]$config.muted) '#FF667085' 'secondary'
    try {
        $themeFont = New-Object Windows.Media.FontFamily([string]$config.themeStyle.fontFamily)
        $entry.Number.FontFamily = $themeFont; $entry.SourceText.FontFamily = $themeFont; $entry.Name.FontFamily = $themeFont; $entry.Metrics.FontFamily = $themeFont
    } catch { }
    $entry.Merge.ToolTip = [string]$settingsLocale.mergeTask
    $entry.Dismiss.ToolTip = [string]$settingsLocale.closeTaskBubble
    $entry.Resize.ToolTip = [string]$settingsLocale.resizeTaskBubble
    $entry.Shell.ToolTip = if ([bool]$config.behavior.openTaskOnDoubleClick -and (Test-HudDesktopTask $State)) { [string]$settingsLocale.openTaskTooltip } else { $null }
    if ([int]$State.AttentionRevision -gt [int]$entry.LastAttentionRevision -and $State.AttentionUntil -gt [DateTimeOffset]::Now) {
        $entry.LastAttentionRevision = [int]$State.AttentionRevision
        Write-HudDebug ('Attention surface: bubble {0} r{1} reason={2}' -f [string]$State.Workspace,[int]$State.AttentionRevision,[string]$State.AttentionReason)
        if ([string]$State.AttentionReason -eq 'agent') { Start-HudAgentAnimation $entry.Shell $State.AgentNoticeRecipe }
        elseif ([string]$State.AttentionReason -eq 'context') { Start-HudContextAlertAnimation $entry.ContextMetric ([int]$State.ContextAlertLevel) }
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
    $mainInset = 18.0
    $bubbleInset = 16.0
    $mainShellLeft = $hud.Left + $mainInset
    $mainShellRight = $hud.Left + $hud.ActualWidth - $mainInset
    $mainShellTop = $hud.Top + $mainInset
    $mainShellBottom = $hud.Top + $hud.ActualHeight - $mainInset
    $cursorY = if ($isBottom) { $mainShellTop - $gap } else { $mainShellBottom + $gap }
    $columnOffset = 0.0
    $columnWidth = 0.0
    foreach ($entry in $entries) {
        $entry.Window.UpdateLayout()
        $width = if ([bool]$entry.IsIndicatorCollapsed) { [Math]::Max(1,$entry.Window.ActualWidth) } else { [Math]::Max(220,$entry.Window.ActualWidth) }
        $height = if ([bool]$entry.IsIndicatorCollapsed) { [Math]::Max(1,$entry.Window.ActualHeight) } else { [Math]::Max(54,$entry.Window.ActualHeight) }
        $columnWidth = [Math]::Max($columnWidth, $width)
        if ($isBottom) {
            $top = $cursorY - $height + $bubbleInset
            if ($top -lt ($work.Top - $bubbleInset)) {
                $columnOffset += ($columnWidth + $gap)
                $columnWidth = $width
                $cursorY = $work.Bottom
                $top = $cursorY - $height + $bubbleInset
            }
            $cursorY = $top + $bubbleInset - $gap
        } else {
            $top = $cursorY - $bubbleInset
            if (($top + $height) -gt ($work.Bottom + $bubbleInset)) {
                $columnOffset += ($columnWidth + $gap)
                $columnWidth = $width
                $cursorY = $work.Top
                $top = $cursorY - $bubbleInset
            }
            $cursorY = $top + $height - $bubbleInset + $gap
        }
        $left = if ($isLeft) { $mainShellLeft - $bubbleInset + $columnOffset } else { $mainShellRight - $width + $bubbleInset - $columnOffset }
        $entry.Window.Left = [Math]::Max($work.Left - $bubbleInset, [Math]::Min($left, $work.Right - $width + $bubbleInset))
        $entry.Window.Top = [Math]::Max($work.Top - $bubbleInset, [Math]::Min($top, $work.Bottom - $height + $bubbleInset))
    }
}

function Test-HudStateQuiet {
    param($State, [bool]$AllowTerminal = $false)
    if ($null -eq $State) { return $false }
    $status = Get-TaskStatus $State
    if ($AllowTerminal -and @('completed','aborted') -contains $status) { return $true }
    if ($status -ne 'idle') { return $false }
    if ($State.AttentionUntil -gt [DateTimeOffset]::Now -or $State.AgentNoticeUntil -gt [DateTimeOffset]::Now -or $State.ContextAlertUntil -gt [DateTimeOffset]::Now) { return $false }
    $reference = if ($State.LastUsageAt -ne [DateTimeOffset]::MinValue) { [DateTimeOffset]$State.LastUsageAt } elseif ($null -ne $State.Snapshot) { [DateTimeOffset]$State.Snapshot.Timestamp } else { [DateTimeOffset]::Now }
    return (([DateTimeOffset]::Now - $reference).TotalMinutes -ge [double]$config.behavior.idleIndicator.afterMinutes)
}

function Test-HudQuietLayoutShowsTasks {
    return @('horizontal','vertical') -contains [string]$config.behavior.idleIndicator.layout
}

function New-HudQuietTaskIndicator {
    param($State, [string]$Style, [string]$Layout)
    $status = Get-TaskStatus $State
    $color = [string]$config.statusColors.$status
    $item = New-Object Windows.Controls.StackPanel
    $item.Orientation = [Windows.Controls.Orientation]::Horizontal
    $item.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $item.Margin = if ($Layout -eq 'vertical') { New-Object Windows.Thickness(1,3,1,3) } else { New-Object Windows.Thickness(3,0,4,0) }
    $item.ToolTip = ('{0}  {1}' -f (Get-TaskDisplayName $State -IncludeNumber),(Get-TaskStatusText $status))

    if ($Style -eq 'bar') {
        $shape = New-Object Windows.Controls.Border
        $shape.Width = 4
        $shape.Height = 18
        $shape.CornerRadius = New-Object Windows.CornerRadius(2)
        $shape.Background = New-HudBrush $color '#FF8E8E93'
        $shape.BorderBrush = New-HudBrush '#66000000' '#66000000'
        $shape.BorderThickness = New-Object Windows.Thickness(0.9)
    } else {
        $shape = New-Object Windows.Shapes.Ellipse
        $taskDotSize = [Math]::Max(7.0,[double]$config.themeStyle.statusDotSize * 0.82)
        $shape.Width = $taskDotSize
        $shape.Height = $taskDotSize
        $shape.Fill = New-HudBrush $color '#FF8E8E93'
        $shape.Stroke = New-HudBrush '#66000000' '#66000000'
        $shape.StrokeThickness = 0.9
    }
    $shape.VerticalAlignment = [Windows.VerticalAlignment]::Center
    [void]$item.Children.Add($shape)

    $number = New-Object Windows.Controls.TextBlock
    $number.Text = ('#{0}' -f [int]$State.Number)
    $number.Margin = New-Object Windows.Thickness(5,0,0,0)
    $number.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $number.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Microsoft YaHei UI')
    $number.FontSize = [Math]::Max(10,[double]$config.fontSize - 2)
    $number.FontWeight = [Windows.FontWeights]::SemiBold
    $number.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary'
    [void]$item.Children.Add($number)
    return $item
}

function Render-HudQuietIndicators {
    $layout = [string]$config.behavior.idleIndicator.layout
    $style = [string]$config.behavior.idleIndicator.taskStyle
    $states = @(Get-HudUserTaskStates | Sort-Object Number)
    $status = Get-HudStatus
    $stateSignature = @($states | ForEach-Object { '{0}:{1}' -f [int]$_.Number,(Get-TaskStatus $_) }) -join ','
    $colorSignature = @('active','listening','idle','paused','error','completed','aborted' | ForEach-Object { [string]$config.statusColors.$_ }) -join ','
    $signature = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $layout,$style,$status,$stateSignature,$colorSignature,[string]$config.background,[string]$config.foreground,[double]$config.themeStyle.statusDotSize
    if ([string]$script:lastQuietIndicatorSignature -eq $signature) { return }
    $script:lastQuietIndicatorSignature = $signature
    Write-HudDebug ('Quiet task indicators: layout={0} style={1} tasks={2} statuses={3}' -f $layout,$style,$states.Count,$stateSignature)
    $color = [string]$config.statusColors.$status
    $overallDotSize = [Math]::Max(12.0,[double]$config.themeStyle.statusDotSize * 1.45)
    $quietOverallDot.Width = $overallDotSize
    $quietOverallDot.Height = $overallDotSize
    $quietOverallDot.Fill = New-HudBrush $color '#FF8E8E93'
    $quietOverallDot.ToolTip = Get-StatusBilingual $status
    $quietOverallRing.Width = $overallDotSize + 5
    $quietOverallRing.Height = $overallDotSize + 5
    $quietOverallRing.Stroke = New-HudBrush $color '#FF8E8E93'
    $quietOverallHost.Width = $overallDotSize + 6
    $quietOverallHost.Height = $overallDotSize + 6
    $quietIndicatorSeparator.Background = New-HudBrush '#32000000' '#32000000'
    $quietTaskIndicators.Children.Clear()

    $showTasks = (Test-HudQuietLayoutShowsTasks) -and $states.Count -gt 0
    $quietIndicatorSeparator.Visibility = if ($showTasks) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    $quietTaskIndicators.Visibility = $quietIndicatorSeparator.Visibility
    if (-not $showTasks) {
        $quietIndicatorPanel.Orientation = [Windows.Controls.Orientation]::Horizontal
        return
    }

    $isVertical = $layout -eq 'vertical'
    $quietIndicatorPanel.Orientation = if ($isVertical) { [Windows.Controls.Orientation]::Vertical } else { [Windows.Controls.Orientation]::Horizontal }
    $quietTaskIndicators.Orientation = $quietIndicatorPanel.Orientation
    if ($isVertical) {
        $quietIndicatorSeparator.Width = 30
        $quietIndicatorSeparator.Height = 1
        $quietIndicatorSeparator.Margin = New-Object Windows.Thickness(0,8,0,6)
        $quietIndicatorSeparator.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    } else {
        $quietIndicatorSeparator.Width = 1
        $quietIndicatorSeparator.Height = 20
        $quietIndicatorSeparator.Margin = New-Object Windows.Thickness(11,0,8,0)
        $quietIndicatorSeparator.VerticalAlignment = [Windows.VerticalAlignment]::Center
    }
    $visibleLimit = 12
    foreach ($state in @($states | Select-Object -First $visibleLimit)) {
        [void]$quietTaskIndicators.Children.Add((New-HudQuietTaskIndicator $state $style $layout))
    }
    if ($states.Count -gt $visibleLimit) {
        $overflow = New-Object Windows.Controls.TextBlock
        $overflow.Text = ('+{0}' -f ($states.Count - $visibleLimit))
        $overflow.Margin = if ($isVertical) { New-Object Windows.Thickness(6,3,0,2) } else { New-Object Windows.Thickness(5,0,1,0) }
        $overflow.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $overflow.FontWeight = [Windows.FontWeights]::SemiBold
        $overflow.Foreground = New-HudRoleBrush ([string]$config.muted) '#FF667085' 'secondary'
        $overflow.ToolTip = [string]$settingsLocale.activeTasks
        [void]$quietTaskIndicators.Children.Add($overflow)
    }
}

function Set-HudIndicatorCollapsed {
    param([bool]$Collapsed)
    $changed = $script:isMainIndicatorCollapsed -ne $Collapsed
    if (-not $changed) {
        if ($Collapsed) {
            $previousSignature = [string]$script:lastQuietIndicatorSignature
            Render-HudQuietIndicators
            if ([string]$script:lastQuietIndicatorSignature -ne $previousSignature) {
                $hud.UpdateLayout()
                if ([string]$config.position -ne 'custom') { Move-HudToConfiguredPosition }
            }
        }
        return
    }
    $script:isMainIndicatorCollapsed = $Collapsed
    if ($changed) { Write-HudDebug ('Main quiet indicator: ' + $(if($Collapsed){'collapsed'}else{'expanded'})) }
    if ($Collapsed) {
        Render-HudQuietIndicators
        $hudContentPanel.Visibility = [Windows.Visibility]::Collapsed
        $quietIndicatorPanel.Visibility = [Windows.Visibility]::Visible
        $hudShell.Padding = if ([string]$config.behavior.idleIndicator.layout -eq 'vertical') { New-Object Windows.Thickness(9,10,9,9) } else { New-Object Windows.Thickness(10,9,10,9) }
        $hudShell.CornerRadius = New-Object Windows.CornerRadius(16)
    } else {
        $quietIndicatorPanel.Visibility = [Windows.Visibility]::Collapsed
        $hudContentPanel.Visibility = [Windows.Visibility]::Visible
        $statusDot.Margin = New-Object Windows.Thickness(0,0,12,0)
        $script:lastHudAppearanceSignature = ''
        [void](Apply-HudAppearance)
        $taskListToggleButton.Visibility = if (@(Get-HudUserTaskStates).Count -gt 0) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
        $script:lastTaskListRenderSignature = ''
        Render-TaskList
    }
    $hud.UpdateLayout()
    if ([string]$config.position -ne 'custom') { Move-HudToConfiguredPosition }
}

function Set-TaskBubbleIndicatorCollapsed {
    param($Entry, $State, [bool]$Collapsed)
    if ($null -eq $Entry -or [bool]$Entry.IsIndicatorCollapsed -eq $Collapsed) { return }
    $Entry.IsIndicatorCollapsed = $Collapsed
    Write-HudDebug ('Task quiet indicator: #{0} {1}' -f [int]$Entry.TaskNumber,$(if($Collapsed){'collapsed'}else{'expanded'}))
    $visibility = if ($Collapsed) { [Windows.Visibility]::Collapsed } else { [Windows.Visibility]::Visible }
    $Entry.Content.Visibility = $visibility
    $Entry.Merge.Visibility = $visibility
    $Entry.Dismiss.Visibility = $visibility
    $Entry.Resize.Visibility = $visibility
    if ($Collapsed) {
        $Entry.Dot.Margin = New-Object Windows.Thickness(0)
        $Entry.Shell.Padding = New-Object Windows.Thickness(10)
        $Entry.Window.Width = [double]::NaN
        $Entry.Window.Height = [double]::NaN
        $Entry.Window.SizeToContent = [Windows.SizeToContent]::WidthAndHeight
    } else {
        $Entry.Dot.Margin = New-Object Windows.Thickness(0,0,9,0)
        $Entry.Shell.Padding = New-Object Windows.Thickness(12,9,12,9)
        if ($null -ne $State -and [double]$State.BubbleWidth -gt 0 -and [double]$State.BubbleHeight -gt 0) {
            $Entry.Window.SizeToContent = [Windows.SizeToContent]::Manual
            $Entry.Window.Width = [double]$State.BubbleWidth
            $Entry.Window.Height = [double]$State.BubbleHeight
        } else {
            $Entry.Window.Width = [double]::NaN
            $Entry.Window.Height = [double]::NaN
            $Entry.Window.SizeToContent = [Windows.SizeToContent]::WidthAndHeight
        }
    }
    $Entry.Window.UpdateLayout()
}

function Update-HudIdleIndicatorMode {
    $states = @(Get-HudUserTaskStates)
    $keepTerminalTaskLights = [bool]$script:isMainIndicatorCollapsed -and (Test-HudQuietLayoutShowsTasks)
    $mainShouldCollapse = [bool]$config.behavior.idleIndicator.enabled -and $states.Count -gt 0 -and -not $hud.IsMouseOver -and @($states | Where-Object { -not (Test-HudStateQuiet $_ $keepTerminalTaskLights) }).Count -eq 0
    Set-HudIndicatorCollapsed $mainShouldCollapse
    foreach ($entry in @($splitWindows.Values)) {
        if (-not $sessionStates.ContainsKey([string]$entry.Path)) { continue }
        $state = $sessionStates[[string]$entry.Path]
        $keepBubbleTerminalLight = (Test-HudQuietLayoutShowsTasks) -and [bool]$entry.IsIndicatorCollapsed
        $bubbleShouldCollapse = [bool]$config.behavior.idleIndicator.enabled -and [bool]$config.behavior.idleIndicator.includeTaskBubbles -and -not $entry.Window.IsMouseOver -and (Test-HudStateQuiet $state $keepBubbleTerminalLight)
        Set-TaskBubbleIndicatorCollapsed $entry $state $bubbleShouldCollapse
    }
    Position-TaskBubbles
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
        SourceBadge = Find-Control $window 'TaskBubbleSourceBadge'
        SourceIcon = Find-Control $window 'TaskBubbleSourceIcon'
        Name = Find-Control $window 'TaskBubbleName'
        ContextMetric = Find-Control $window 'TaskBubbleContextMetric'
        ContextText = Find-Control $window 'TaskBubbleContextText'
        Metrics = Find-Control $window 'TaskBubbleMetrics'
        Content = Find-Control $window 'TaskBubbleContent'
        Merge = Find-Control $window 'TaskBubbleMergeButton'
        Dismiss = Find-Control $window 'TaskBubbleDismissButton'
        Resize = Find-Control $window 'TaskBubbleResizeThumb'
        Handle = [IntPtr]::Zero
        BaseStyle = $null
        InternalClosing = $false
        LastAttentionRevision = 0
        LastExitRevision = 0
        IsIndicatorCollapsed = $false
    }
    $script:splitWindows[$path] = $entry
    $entryRecord = $entry
    $taskPath = $path
    $splitWindowMap = $script:splitWindows
    $sessionStateMap = $sessionStates
    $window.Add_SourceInitialized(({ $entryRecord.Handle=(New-Object Windows.Interop.WindowInteropHelper($entryRecord.Window)).Handle;if($entryRecord.Handle-ne[IntPtr]::Zero){$entryRecord.BaseStyle=[HudNativeMethods]::GetWindowLong($entryRecord.Handle,-20);Set-WindowMousePassthrough $entryRecord.Handle $entryRecord.BaseStyle ([bool]$config.mousePassthrough)} }).GetNewClosure())
    $entry.Merge.Add_Click(({ Set-SessionDetached $taskPath $false }).GetNewClosure())
    $entry.Dismiss.Add_Click(({ Set-SessionDetached $taskPath $false }).GetNewClosure())
    $window.Add_MouseLeftButtonDown(({ param($sender,$eventArgs)
        if ($eventArgs.ClickCount -ge 2 -and (Open-HudTaskByPath $taskPath)) { $eventArgs.Handled = $true }
    }).GetNewClosure())
    $window.Add_MouseEnter(({ if ($entryRecord.IsIndicatorCollapsed -and $sessionStateMap.ContainsKey($taskPath)) { Set-TaskBubbleIndicatorCollapsed $entryRecord $sessionStateMap[$taskPath] $false; Position-TaskBubbles } }).GetNewClosure())
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
    $density = Get-TaskListDensityMetrics
    $states = @(Get-HudUserTaskStates | Sort-Object Number)
    $visible = ([string]$config.multiTask.displayMode -eq 'list')
    if ($isMainIndicatorCollapsed) { return }
    $signatureNow = [DateTimeOffset]::Now
    $stateSignature = if ($visible) { @($states | ForEach-Object {
        $state = $_
        $snapshotContext = if ($null -ne $state.Snapshot) { [double]$state.Snapshot.ContextPercent } else { -1.0 }
        $identity = if (-not [string]::IsNullOrWhiteSpace([string]$state.SessionId)) { [string]$state.SessionId } else { [string]$state.Path }
        '{0}:{1}:{2}:{3}:{4}:{5}:{6}:{7}:{8}:{9}:{10}:{11}:{12}:{13}:{14}:{15}' -f $identity,[int]$state.Number,(Get-TaskStatus $state),[bool]$state.Detached,(Get-TaskProjectName $state),(Get-TaskListSubtitle $state -IncludeConversationTitle),$snapshotContext,(Get-TaskListMetricsText $state),[int]$state.AttentionRevision,[int]$state.TerminalExitRevision,[string]$state.AgentNoticeText,($state.AttentionUntil-gt$signatureNow),($state.ContextAlertUntil-gt$signatureNow),[string]$state.ProfileId,[string]$state.ClientSurface,[string]$state.ModelProvider
    }) -join ';' } else { '' }
    $renderSignature = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $visible,[string]$config.multiTask.listStyle,[string]$config.multiTask.listDensity,[string]$config.multiTask.listDetail,[string]$config.multiTask.nameMode,[bool]$config.fields.context,[string]$script:lastHudAppearanceSignature,$stateSignature
    if ([string]$script:lastTaskListRenderSignature -eq $renderSignature) { return }
    $script:lastTaskListRenderSignature = $renderSignature
    $taskListPanel.Children.Clear()
    $taskListScroller.Visibility = if ($visible -and $states.Count -gt 0) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    $taskListDivider.Visibility = $taskListScroller.Visibility
    if (-not $visible) { return }
    foreach ($state in $states) {
        $path = [string]$state.Path
        $row = New-Object Windows.Controls.Grid
        $row.Margin = $density.RowMargin
        $row.Background = New-HudRoleBrush '#08000000' '#08000000' 'decoration'
        $gridLengthConverter = New-Object Windows.GridLengthConverter
        foreach($width in @('Auto','Auto','Auto','Auto','*','Auto','Auto')) {
            $column = New-Object Windows.Controls.ColumnDefinition
            $column.Width = $gridLengthConverter.ConvertFromString($width)
            $row.ColumnDefinitions.Add($column)
        }
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width=7;$dot.Height=7;$dot.Margin=$density.DotMargin;$dot.VerticalAlignment='Center';$dot.Fill=New-HudBrush ([string]$config.statusColors.(Get-TaskStatus $state)) '#FF8E8E93'
        [Windows.Controls.Grid]::SetColumn($dot,0);[void]$row.Children.Add($dot)
        $sourceBadge = New-HudTaskSourceBadge $state ([double]$density.BadgeRadius) (New-Object Windows.Thickness(0,1,6,1))
        [Windows.Controls.Grid]::SetColumn($sourceBadge,1);[void]$row.Children.Add($sourceBadge)
        $badge=New-Object Windows.Controls.Border;$badge.CornerRadius=New-Object Windows.CornerRadius([double]$density.BadgeRadius);$badge.Background=New-HudBrush '#120A84FF';$badge.Padding=$density.BadgePadding;$badge.Margin=$density.BadgeMargin;$badge.ToolTip=Get-TaskDisplayName $state -IncludeNumber
        $badgeText=New-Object Windows.Controls.TextBlock;$badgeText.Text=('#{0}'-f[int]$state.Number);$badgeText.FontWeight='SemiBold';$badgeText.Foreground=New-HudRoleBrush ([string]$config.accent) '#FF0A84FF' 'primary';$badge.Child=$badgeText
        [Windows.Controls.Grid]::SetColumn($badge,2);[void]$row.Children.Add($badge)
        $projectName = Get-TaskProjectName $state
        $fullName = Get-TaskDisplayName $state
        $collapsedSubtitle = Get-TaskListSubtitle $state
        $expandedSubtitle = Get-TaskListSubtitle $state -IncludeConversationTitle
        $identityHost=New-Object Windows.Controls.StackPanel;$identityHost.Orientation=[Windows.Controls.Orientation]::Vertical;$identityHost.VerticalAlignment='Center';$identityHost.Margin=New-Object Windows.Thickness(0,2,12,2);$identityHost.MaxWidth=280;$identityHost.ToolTip=$fullName
        $name=New-Object Windows.Controls.TextBlock;$name.Text=$projectName;$name.FontWeight=[Windows.FontWeights]::SemiBold;$name.TextTrimming=[Windows.TextTrimming]::CharacterEllipsis;$name.Foreground=New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary'
        $subtitle=New-Object Windows.Controls.TextBlock;$subtitle.Text=if([string]$config.multiTask.nameMode-eq'hidden'){$collapsedSubtitle}else{$expandedSubtitle};$subtitle.Margin=New-Object Windows.Thickness(0,1,0,0);$subtitle.FontSize=[Math]::Max(9,[double]$config.fontSize-3);$subtitle.TextTrimming=[Windows.TextTrimming]::CharacterEllipsis;$subtitle.Foreground=New-HudRoleBrush ([string]$config.muted) '#FF667085' 'secondary'
        [void]$identityHost.Children.Add($name);[void]$identityHost.Children.Add($subtitle)
        [Windows.Controls.Grid]::SetColumn($identityHost,3);[void]$row.Children.Add($identityHost)
        $metricsHost=New-Object Windows.Controls.Grid;$metricsHost.VerticalAlignment='Center'
        $contextColumn=New-Object Windows.Controls.ColumnDefinition;$contextColumn.Width=$gridLengthConverter.ConvertFromString('Auto');[void]$metricsHost.ColumnDefinitions.Add($contextColumn)
        $metricColumn=New-Object Windows.Controls.ColumnDefinition;$metricColumn.Width=$gridLengthConverter.ConvertFromString('*');[void]$metricsHost.ColumnDefinitions.Add($metricColumn)
        $contextMetric=New-Object Windows.Controls.Border;$contextMetric.CornerRadius=New-Object Windows.CornerRadius(7);$contextMetric.Padding=New-Object Windows.Thickness(6,2,6,2);$contextMetric.Margin=New-Object Windows.Thickness(0,0,7,0);$contextMetric.BorderThickness=New-Object Windows.Thickness(1);$contextMetric.BorderBrush=New-HudRoleBrush '#330A84FF' '#330A84FF' 'decoration';$contextMetric.Background=New-HudRoleBrush '#0D0A84FF' '#0D0A84FF' 'decoration'
        $contextText=New-Object Windows.Controls.TextBlock;$contextText.Text=if($null-ne$state.Snapshot){('{0} {1}' -f [string]$settingsLocale.context,$(if([Int64]$state.Snapshot.ContextWindow-gt 0){Format-HudPercent ([double]$state.Snapshot.ContextPercent)}else{'--'}))}else{[string]$settingsLocale.waiting};$contextText.FontWeight='SemiBold';$contextText.Foreground=New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary';$contextMetric.Child=$contextText
        $contextMetric.ToolTip=if($null-ne$state.Snapshot-and[Int64]$state.Snapshot.ContextWindow-gt 0){('{0} {1}'-f[string]$settingsLocale.contextWindow,(Format-HudNumber ([Int64]$state.Snapshot.ContextWindow) 'auto'))}else{[string]$settingsLocale.contextUnavailable}
        [Windows.Controls.Grid]::SetColumn($contextMetric,0);[void]$metricsHost.Children.Add($contextMetric)
        $metrics=New-Object Windows.Controls.TextBlock;$metrics.Text=Get-TaskListMetricsText $state;$metrics.VerticalAlignment='Center';$metrics.Foreground=New-HudRoleBrush ([string]$config.muted) '#FF667085' 'secondary';$metrics.TextTrimming='CharacterEllipsis';$metrics.ToolTip=$metrics.Text
        [Windows.Controls.Grid]::SetColumn($metrics,1);[void]$metricsHost.Children.Add($metrics)
        [Windows.Controls.Grid]::SetColumn($metricsHost,4);[void]$row.Children.Add($metricsHost)
        $action=New-Object Windows.Controls.Button;$action.Content=New-HudTaskActionIcon ([bool]$state.Detached);$action.Style=$hud.FindResource('HudIconButton');$action.Width=[double]$density.ActionSize;$action.Height=[double]$density.ActionSize;$action.Tag=$path;$action.Margin=$density.ActionMargin;$action.ToolTip=if([bool]$state.Detached){[string]$settingsLocale.mergeTask}else{[string]$settingsLocale.detachTask}
        $action.Add_Click(({ Set-SessionDetached $path (-not [bool]$sessionStates[$path].Detached) }).GetNewClosure())
        [Windows.Controls.Grid]::SetColumn($action,5);[void]$row.Children.Add($action)
        $dismiss=New-Object Windows.Controls.Button;$dismiss.Content=New-HudDismissIcon;$dismiss.Style=$hud.FindResource('HudIconButton');$dismiss.Width=[double]$density.ActionSize;$dismiss.Height=[double]$density.ActionSize;$dismiss.Tag=$path;$dismiss.Margin=New-Object Windows.Thickness(1,0,2,0);$dismiss.ToolTip=[string]$settingsLocale.dismissTask
        $dismiss.Add_Click(({ Dismiss-HudTask $path }).GetNewClosure())
        [Windows.Controls.Grid]::SetColumn($dismiss,6);[void]$row.Children.Add($dismiss)
        $detailedLayout = ([string]$config.multiTask.listDetail -eq 'detailed')
        if ($detailedLayout) {
            $row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
            $row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
            foreach($control in @($dot,$sourceBadge,$badge,$action,$dismiss)){[Windows.Controls.Grid]::SetRowSpan($control,2)}
            [Windows.Controls.Grid]::SetRow($metricsHost,1);[Windows.Controls.Grid]::SetColumn($metricsHost,3);[Windows.Controls.Grid]::SetColumnSpan($metricsHost,2)
            $metricsHost.Margin=$density.MetricsMargin;$metrics.TextWrapping=[Windows.TextWrapping]::Wrap;$metrics.TextTrimming=[Windows.TextTrimming]::None
        }
        $listItem = $row
        switch ([string]$config.multiTask.listStyle) {
            'cards' {
                $row.Background = [Windows.Media.Brushes]::Transparent
                if(-not$detailedLayout){
                    $row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition));$row.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition));[Windows.Controls.Grid]::SetRowSpan($dot,2);[Windows.Controls.Grid]::SetRow($metricsHost,1);[Windows.Controls.Grid]::SetColumn($metricsHost,1);[Windows.Controls.Grid]::SetColumnSpan($metricsHost,4);$metricsHost.Margin=$density.MetricsMargin;$metrics.TextWrapping=[Windows.TextWrapping]::Wrap
                }
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
        $attentionSurface.ToolTip = if ([bool]$config.behavior.openTaskOnDoubleClick -and (Test-HudDesktopTask $state)) { [string]$settingsLocale.openTaskTooltip } else { $null }
        $attentionSurface.Add_MouseLeftButtonDown(({ param($sender,$eventArgs)
            if ($eventArgs.ClickCount -ge 2 -and (Open-HudTaskByPath $path)) { $eventArgs.Handled = $true }
        }).GetNewClosure())
        [void]$taskListPanel.Children.Add($attentionSurface)
        if ([int]$state.AttentionRevision -gt [int]$state.LastListAttentionRevision) {
            $state.LastListAttentionRevision = [int]$state.AttentionRevision
            if (-not [bool]$state.Detached -and $state.AttentionUntil -gt [DateTimeOffset]::Now) {
                Write-HudDebug ('Attention surface: list {0} r{1} reason={2}' -f [string]$state.Workspace,[int]$state.AttentionRevision,[string]$state.AttentionReason)
                if ([string]$state.AttentionReason -eq 'agent') { Start-HudAgentAnimation $attentionSurface $state.AgentNoticeRecipe }
                elseif ([string]$state.AttentionReason -eq 'context') { Start-HudContextAlertAnimation $contextMetric ([int]$state.ContextAlertLevel) }
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
    $zh = Get-RuntimeHudLocale 'zh-CN'
    $en = Get-RuntimeHudLocale 'en'
    return ('{0} ({1})' -f [string]$zh.$key, [string]$en.$key)
}

function Update-ContextMenuText {
    param([switch]$Force)
    $status = Get-HudStatus
    $signature = '{0}|{1}|{2}|{3}|{4}' -f [string]$config.language,[bool]$config.mousePassthrough,[bool]$paused,[string]$config.multiTask.displayMode,$status
    if (-not $Force -and [string]$script:lastContextMenuSignature -eq $signature) { return }
    $script:lastContextMenuSignature = $signature
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
        $zh = Get-RuntimeHudLocale 'zh-CN'
        $en = Get-RuntimeHudLocale 'en'
        $statusVariable.Value.Header = ('{0} / {1}: {2}' -f [string]$zh.statusLabel, [string]$en.statusLabel, (Get-StatusBilingual $status))
    }
    Update-HudTrayMenu $status
}

function Update-HudTrayMenu {
    param([string]$Status = (Get-HudStatus))
    if ($null -eq $trayIcon) { return }
    $trayZh = Get-RuntimeHudLocale 'zh-CN'
    $trayEn = Get-RuntimeHudLocale 'en'
    $trayStatusItem.Text = ('{0} / {1}: {2}' -f [string]$trayZh.statusLabel, [string]$trayEn.statusLabel, (Get-StatusBilingual $Status))
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

function Add-HudContextAlert {
    param($State)
    $alertText = Get-HudContextAlertText $State
    if ([string]::IsNullOrWhiteSpace($alertText)) { return }
    $colors = @('#FF0A84FF','#FFFF9F0A','#FFFF453A')
    $color = $colors[[Math]::Max(0,[Math]::Min(2,[int]$State.ContextAlertLevel-1))]
    $card = New-Object Windows.Controls.Border
    $card.CornerRadius = New-Object Windows.CornerRadius([Math]::Max(8,[double]$config.cornerRadius-8))
    $card.Padding = New-Object Windows.Thickness(10,6,10,6)
    $card.Margin = New-Object Windows.Thickness(7,0,0,0)
    $card.BorderThickness = New-Object Windows.Thickness(1)
    $card.BorderBrush = New-HudBrush $color '#FFFF9F0A'
    $card.Background = New-HudRoleBrush '#12FF9F0A' '#12FF9F0A' 'decoration'
    $text = New-Object Windows.Controls.TextBlock
    $text.Text = $alertText
    $text.FontWeight = [Windows.FontWeights]::SemiBold
    $text.Foreground = New-HudRoleBrush ([string]$config.foreground) '#FF111827' 'primary'
    $card.Child = $text
    [void]$metricsPanel.Children.Add($card)
}

function Process-HudAgentNotifications {
    $changed = $false
    if (-not [IO.Directory]::Exists($notificationsRoot)) { return $false }
    $noticeFiles = @([IO.Directory]::EnumerateFiles($notificationsRoot,'*.json',[IO.SearchOption]::TopDirectoryOnly) | ForEach-Object { [IO.FileInfo]::new($_) } | Sort-Object CreationTimeUtc)
    foreach ($file in $noticeFiles) {
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

function Render-HudMetrics {
    $metrics = @()
    if (-not $paused -and $null -ne $snapshot) { $metrics = @(Get-HudMetrics $snapshot $config $locale) }
    if ($metrics.Count -gt 0) {
        $sourceStates = @(Get-HudUserTaskStates)
        $sourceGroups = @($sourceStates | Group-Object { Get-TaskSourceLabel $_ } | Sort-Object -Property @{Expression='Count';Descending=$true}, @{Expression='Name';Descending=$false})
        $hasCli = @($sourceStates | Where-Object { [string]$_.ClientSurface -eq 'cli' -or [string]$_.ProfileId -eq 'deepseek' }).Count -gt 0
        if ($sourceGroups.Count -gt 1 -or $hasCli) {
            $sourceSummary = @($sourceGroups | ForEach-Object { '{0} {1}' -f [string]$_.Name,[int]$_.Count }) -join (' {0} ' -f [char]0x00B7)
            foreach ($metric in @($metrics | Where-Object { [string]$_.Key -eq 'activeTasks' })) {
                $metric.Value = ('{0} {1} {2}' -f [string]$metric.Value,[char]0x00B7,$sourceSummary)
            }
        }
    }
    $isWaiting = $paused -or $null -eq $snapshot -or $metrics.Count -eq 0
    if ($isWaiting) {
        $waitingText = if ($paused) { [string]$locale.paused } elseif ($initialSessionScanComplete -and @(Get-HudUserTaskStates).Count -eq 0) { [string]$locale.noActiveTasks } else { [string]$locale.waiting }
        $structureSignature = 'waiting|{0}|{1}|{2}|{3}' -f [string]$config.language,[string]$config.layout,[double]$config.fontSize,[string]$script:lastHudAppearanceSignature
        if ([string]$script:lastHudMetricsStructureSignature -eq $structureSignature -and $hudMetricControls.ContainsKey('__waiting')) {
            $hudMetricControls['__waiting'].Text = $waitingText
            return $false
        }
        $metricsPanel.Children.Clear()
        $script:hudMetricControls = @{}
        $script:contextMetricContainer = $null
        $script:hudMetricControls['__waiting'] = Add-WaitingMetric
        $script:lastHudMetricsStructureSignature = $structureSignature
        return $true
    }

    $metricIdentity = @($metrics | ForEach-Object { '{0}:{1}' -f [string]$_.Key,[string]$_.Label }) -join ';'
    $structureSignature = 'metrics|{0}|{1}|{2}|{3}|{4}' -f [string]$config.language,[string]$config.layout,[double]$config.fontSize,$metricIdentity,[string]$script:lastHudAppearanceSignature
    if ([string]$script:lastHudMetricsStructureSignature -eq $structureSignature) {
        $complete = $true
        foreach ($metric in $metrics) {
            if (-not $hudMetricControls.ContainsKey([string]$metric.Key)) { $complete=$false;break }
            $entry = $hudMetricControls[[string]$metric.Key]
            $entry.Label.Text = [string]$metric.Label
            $entry.Value.Text = [string]$metric.Value
        }
        if ($complete) { return $false }
    }

    $metricsPanel.Children.Clear()
    $script:hudMetricControls = @{}
    $script:contextMetricContainer = $null
    foreach ($metric in $metrics) { $script:hudMetricControls[[string]$metric.Key] = Add-HudMetric $metric }
    $script:lastHudMetricsStructureSignature = $structureSignature
    return $true
}

function Apply-HudAppearance {
    $nextStatus = Get-HudStatus
    $summaryFlowActive = @(Get-HudUserTaskStates | Where-Object { $_.AttentionUntil -gt [DateTimeOffset]::Now -and ([string]$config.attention.summaryMode -eq 'flow' -or [string]$_.AttentionReason -eq 'agent') }).Count -gt 0
    $themeStyleSignature = @($config.themeStyle.PSObject.Properties | Sort-Object Name | ForEach-Object { '{0}={1}' -f [string]$_.Name,[string]$_.Value }) -join ','
    $appearanceSignature = @(
        [string]$config.language,[string]$config.preset,[string]$config.layout,[string]$config.background,[string]$config.foreground,[string]$config.muted,[string]$config.border,[string]$config.accent,
        [double]$config.fontSize,[int]$config.cornerRadius,[double]$config.opacity,[string]$config.transparencyMode,[bool]$config.alwaysOnTop,[bool]$config.mousePassthrough,[bool]$config.showStatusDot,
        $themeStyleSignature,$nextStatus,[string]$config.statusColors.$nextStatus,$summaryFlowActive
    ) -join '|'
    $script:currentStatus = $nextStatus
    if ([string]$script:lastHudAppearanceSignature -eq $appearanceSignature) { return }
    $script:lastHudAppearanceSignature = $appearanceSignature
    $hud.Topmost = [bool]$config.alwaysOnTop
    try { $hud.FontFamily = New-Object Windows.Media.FontFamily([string]$config.themeStyle.fontFamily) } catch { }
    Set-HudMousePassthrough ([bool]$config.mousePassthrough)
    $hud.Opacity = if ([string]$config.transparencyMode -eq 'uniform') { [double]$config.opacity } else { 1.0 }
    $hudShell.CornerRadius = New-Object Windows.CornerRadius([double]$config.cornerRadius)
    if (-not $summaryFlowActive) {
        $hudShell.BorderBrush = New-HudRoleBrush ([string]$config.border) '#22FFFFFF' 'decoration'
        $hudShell.BorderThickness = New-Object Windows.Thickness([double]$config.themeStyle.borderWidth)
    }
    $hudShell.Background = New-HudSurfaceBrush
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
    [void](Apply-HudAppearance)
    $summaryNotice = if ([string]$config.multiTask.displayMode -eq 'summary') { Get-HudUserTaskStates | Where-Object { $_.AgentNoticeUntil -gt [DateTimeOffset]::Now -and -not [string]::IsNullOrWhiteSpace([string]$_.AgentNoticeText) } | Sort-Object AttentionRevision -Descending | Select-Object -First 1 } else { $null }
    $hasSummaryNotice = $null -ne $summaryNotice
    if ([bool]$script:summaryNoticeVisible -ne $hasSummaryNotice -or $hasSummaryNotice) { $script:lastHudMetricsStructureSignature = '' }
    $script:summaryNoticeVisible = $hasSummaryNotice
    [void](Render-HudMetrics)
    if ($hasSummaryNotice) { Add-HudAgentNotice $summaryNotice }
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
            elseif ([string]$mainAttention.AttentionReason -eq 'context') { Start-HudContextAlertAnimation $contextMetricContainer ([int]$mainAttention.ContextAlertLevel) }
            else { Start-HudAttentionAnimation $statusDot $hudShell ([string]$config.attention.summaryMode) }
        }
    }
    $hud.UpdateLayout()
    if ([string]$config.position -ne 'custom') { Move-HudToConfiguredPosition }
    Position-TaskBubbles
    Update-HudIdleIndicatorMode
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
    $script:config.multiTask.nameMode = $PreviewTaskNameMode
    if ($PreviewQuietLayout -ne 'none') {
        $script:config.behavior.idleIndicator.enabled = $true
        $script:config.behavior.idleIndicator.layout = $PreviewQuietLayout
        $script:config.behavior.idleIndicator.taskStyle = $PreviewQuietTaskStyle
        foreach ($key in $statusPalettes.codexMicro.Keys) { $script:config.statusColors.$key = [string]$statusPalettes.codexMicro[$key] }
        $script:config.statusPalette = 'codexMicro'
    }
    if ($PreviewAttentionMode -ne 'none') {
        $script:config.attention.summaryMode = $PreviewAttentionMode
        $script:config.attention.listMode = $PreviewAttentionMode
        $script:config.attention.taskBubbleMode = $PreviewAttentionMode
    }
    $script:config.transparencyMode = $PreviewTransparencyMode
    if ($PreviewOpacity -ge 0) { $script:config.opacity = [Math]::Max(0.0, [Math]::Min(1.0, $PreviewOpacity)) }
    if ($PreviewFontSize -gt 0) { $script:config.fontSize = [Math]::Round($PreviewFontSize, 1) }
    $script:config.fields.weeklyRemaining = $true
    $script:config.fields.fiveHourRemaining = $true
    $script:locale = Get-RuntimeHudLocale ([string]$config.language)
    $script:settingsLocale = if ([string]$config.language -eq 'symbols') { Get-RuntimeHudLocale 'en' } else { $locale }
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
    if ($PreviewHudMode -eq 'list' -or $PreviewQuietLayout -ne 'none') {
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
                SessionId = ('preview-thread-{0}' -f ($index + 1))
                ProfileId = if ($index -eq 3) { 'deepseek' } else { 'codex' }
                ProfileLabel = if ($index -eq 3) { 'DeepSeek' } else { 'Codex' }
                ClientSurface = if ($index -eq 1) { 'vscode' } elseif (@(2,3) -contains $index) { 'cli' } else { 'desktop' }
                ModelProvider = if ($index -eq 3) { 'deepseek' } else { 'openai' }
                Snapshot = $taskSnapshot
                LastUsageAt = if ($PreviewQuietLayout -ne 'none') { [DateTimeOffset]::Now.AddMinutes(-20) } elseif ($index -lt 2) { [DateTimeOffset]::Now.AddSeconds(-$index) } elseif ($index -eq 2) { [DateTimeOffset]::Now.AddSeconds(-36) } else { [DateTimeOffset]::Now.AddMinutes(-5) }
                LastReadErrorAt = [DateTimeOffset]::MinValue
                LastRenderedStatus = ''
                TerminalStatus = if ($PreviewQuietLayout -ne 'none' -and $index -eq 1) { 'completed' } elseif ($PreviewQuietLayout -ne 'none' -and $index -eq 2) { 'aborted' } else { '' }
                TerminalAt = if ($PreviewQuietLayout -ne 'none' -and @(1,2) -contains $index) { [DateTimeOffset]::Now.AddMinutes(-1) } else { [DateTimeOffset]::MinValue }
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
                ContextAlertLevel = 0
                ContextAlertPercent = 0.0
                ContextAlertUntil = [DateTimeOffset]::MinValue
                ActiveTurnId = ''
                PendingCompletionTurnId = ''
                PendingCompletionAt = [DateTimeOffset]::MinValue
                PendingCompletionDueAt = [DateTimeOffset]::MinValue
                LastWriteTimeUtc = [DateTime]::UtcNow.AddSeconds(-($index * 14))
                Detached = $false
                BubbleWidth = 0.0
                BubbleHeight = 0.0
            }
        }
    }
    Render-Hud
    if ($PreviewQuietLayout -ne 'none') { Set-HudIndicatorCollapsed $true }
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
    if ($SettingsHost) { [IO.File]::WriteAllText($reloadSettingsSignal,[DateTime]::UtcNow.ToString('O')) }
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
    if ($SettingsHost) { [IO.File]::WriteAllText($reloadSettingsSignal, [DateTime]::UtcNow.ToString('O')) }
    Update-DisplaySnapshot
}

function Sync-ControlsFromConfig {
    if (-not $loadSettingsUi) { return }
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
        Select-ComboTag $listDetailCombo ([string]$config.multiTask.listDetail)
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
        Select-ComboTag $idleIndicatorDelayCombo ([string][int]$config.behavior.idleIndicator.afterMinutes)
        Select-ComboTag $idleIndicatorLayoutCombo ([string]$config.behavior.idleIndicator.layout)
        Select-ComboTag $idleIndicatorTaskStyleCombo ([string]$config.behavior.idleIndicator.taskStyle)
        $contextThresholdControls = @($contextThreshold1Text,$contextThreshold2Text,$contextThreshold3Text)
        $contextThresholdValues = @($config.behavior.contextAlerts.thresholds)
        for ($index = 0; $index -lt $contextThresholdControls.Count; $index++) {
            $contextThresholdControls[$index].Text = if ($index -lt $contextThresholdValues.Count) { [string][int]$contextThresholdValues[$index] } else { '' }
        }
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
        $sourceDesktopCheck.IsChecked = [bool]$config.sessionSources.desktop
        $sourceVsCodeCheck.IsChecked = [bool]$config.sessionSources.vscode
        $sourceDefaultCliCheck.IsChecked = [bool]$config.sessionSources.defaultCli
        $sourceDeepSeekCliCheck.IsChecked = [bool]$config.sessionSources.deepSeekCli
        $attentionCompletedCheck.IsChecked = [bool]$config.attention.onCompleted
        $attentionErrorCheck.IsChecked = [bool]$config.attention.onAbortedOrError
        $attentionSettledCheck.IsChecked = [bool]$config.attention.onSettled
        $agentNotificationEnabledCheck.IsChecked = [bool]$config.agentNotifications.enabled
        $dotAttentionEnabledCheck.IsChecked = [bool]$config.attention.dotEnabled
        $dotBreathingCheck.IsChecked = [bool]$config.attention.dotBreathing
        $openTaskOnDoubleClickCheck.IsChecked = [bool]$config.behavior.openTaskOnDoubleClick
        $idleIndicatorEnabledCheck.IsChecked = [bool]$config.behavior.idleIndicator.enabled
        $idleIndicatorBubblesCheck.IsChecked = [bool]$config.behavior.idleIndicator.includeTaskBubbles
        $contextMetricVisibleCheck.IsChecked = [bool]$config.fields.context
        $contextAlertsEnabledCheck.IsChecked = [bool]$config.behavior.contextAlerts.enabled
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
    $tabMap = @{ general='GeneralTab'; sources='SourcesTab'; multi='MultiTaskTab'; behavior='BehaviorTab'; metrics='MetricsTab'; appearance='AppearanceTab' }
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
    $listDetail = Get-ComboTag $listDetailCombo
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
    $idleIndicatorDelay = Get-ComboTag $idleIndicatorDelayCombo
    $idleIndicatorLayout = Get-ComboTag $idleIndicatorLayoutCombo
    $idleIndicatorTaskStyle = Get-ComboTag $idleIndicatorTaskStyleCombo
    $contextThresholdControls = @($contextThreshold1Text,$contextThreshold2Text,$contextThreshold3Text)
    $contextThresholds = Get-HudContextAlertThresholds @($contextThresholdControls | ForEach-Object { [string]$_.Text })
    $contextThresholdsValid = $null -ne $contextThresholds
    $previousDisplayMode = [string]$config.multiTask.displayMode
    $previousMaxSplitBubbles = [int]$config.multiTask.maxSplitBubbles
    $previousContextAlertsEnabled = [bool]$config.behavior.contextAlerts.enabled
    $previousContextVisible = [bool]$config.fields.context
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
    if ($listDetail) { $config.multiTask.listDetail = $listDetail }
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
    if ($idleIndicatorDelay) { $config.behavior.idleIndicator.afterMinutes = [int]$idleIndicatorDelay }
    if ($idleIndicatorLayout) { $config.behavior.idleIndicator.layout = $idleIndicatorLayout }
    if ($idleIndicatorTaskStyle) { $config.behavior.idleIndicator.taskStyle = $idleIndicatorTaskStyle }
    if ($contextThresholdsValid) {
        $config.behavior.contextAlerts.thresholds = @($contextThresholds)
        for ($index = 0; $index -lt $contextThresholdControls.Count; $index++) {
            $contextThresholdControls[$index].Text = if ($index -lt $contextThresholds.Count) { [string][int]$contextThresholds[$index] } else { '' }
        }
    }
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
    $config.sessionSources.desktop = [bool]$sourceDesktopCheck.IsChecked
    $config.sessionSources.vscode = [bool]$sourceVsCodeCheck.IsChecked
    $config.sessionSources.defaultCli = [bool]$sourceDefaultCliCheck.IsChecked
    $config.sessionSources.deepSeekCli = [bool]$sourceDeepSeekCliCheck.IsChecked
    $config.attention.onCompleted = [bool]$attentionCompletedCheck.IsChecked
    $config.attention.onAbortedOrError = [bool]$attentionErrorCheck.IsChecked
    $config.attention.onSettled = [bool]$attentionSettledCheck.IsChecked
    $config.agentNotifications.enabled = [bool]$agentNotificationEnabledCheck.IsChecked
    $config.attention.dotEnabled = [bool]$dotAttentionEnabledCheck.IsChecked
    $config.attention.dotBreathing = [bool]$dotBreathingCheck.IsChecked
    $config.behavior.openTaskOnDoubleClick = [bool]$openTaskOnDoubleClickCheck.IsChecked
    $config.behavior.idleIndicator.enabled = [bool]$idleIndicatorEnabledCheck.IsChecked
    $config.behavior.idleIndicator.includeTaskBubbles = [bool]$idleIndicatorBubblesCheck.IsChecked
    $config.behavior.contextAlerts.enabled = [bool]$contextAlertsEnabledCheck.IsChecked -and [bool]$config.fields.context
    if (-not [bool]$config.fields.context) { $contextAlertsEnabledCheck.IsChecked = $false }
    $contextMetricVisibleCheck.IsChecked = [bool]$config.fields.context
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
    if (($previousContextAlertsEnabled -and -not [bool]$config.behavior.contextAlerts.enabled) -or ($previousContextVisible -and -not [bool]$config.fields.context)) {
        Reset-HudContextAlertRuntime
    } else {
        foreach ($state in @($sessionStates.Values)) {
            if ($null -ne $state.Snapshot) { $state.ContextAlertLevel = Get-HudContextAlertLevel ([double]$state.Snapshot.ContextPercent) $config.behavior.contextAlerts.thresholds }
        }
    }
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
    if ($SettingsHost) { [IO.File]::WriteAllText($reloadSettingsSignal, [DateTime]::UtcNow.ToString('O')) }
    Update-DisplaySnapshot
    $saveStatus.Text = if ($contextThresholdsValid) { ('{0}  {1}' -f [string]$settingsLocale.savedAt, (Get-Date).ToString('HH:mm:ss')) } else { [string]$settingsLocale.contextThresholdsInvalid }
}

function Show-HudSettings {
    if (-not $loadSettingsUi) {
        Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-SettingsHost') -WindowStyle Hidden | Out-Null
        return
    }
    Sync-ControlsFromConfig
    if (-not $settings.IsVisible) { $settings.Show() }
    $settings.Activate() | Out-Null
}

function Stop-HudApplication {
    param([switch]$UserInitiated)
    if ($UserInitiated) {
        try { [IO.File]::WriteAllText((Join-Path $paths.StateRoot 'manual-exit.signal'), [DateTime]::UtcNow.ToString('O')) } catch { }
    }
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
        ClientSurface = 'unknown'
        ModelProvider = ''
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
                $originator = if ($null -ne $record.payload.PSObject.Properties['originator']) { [string]$record.payload.originator } else { '' }
                $sourceName = if ($null -ne $record.payload.PSObject.Properties['source'] -and $record.payload.source -is [string]) { [string]$record.payload.source } else { '' }
                if ($originator -eq 'codex_vscode' -or $originator -eq 'Codex VS Code') { $identity.ClientSurface = 'vscode' }
                elseif ($originator -eq 'Codex Desktop' -or $sourceName -eq 'vscode') { $identity.ClientSurface = 'desktop' }
                elseif ($originator -match 'codex-tui' -or $sourceName -eq 'cli') { $identity.ClientSurface = 'cli' }
                if ($null -ne $record.payload.PSObject.Properties['model_provider']) {
                    $provider = ([string]$record.payload.model_provider).Trim()
                    $identity.ModelProvider = if ($provider.Length -gt 40) { $provider.Substring(0,40) } else { $provider }
                }
            }
            break
        }
    } catch { }
    return $identity
}

function Get-HudIndexedSessionTitle {
    param([string]$ProfileId, [string]$SessionId)
    if ([string]::IsNullOrWhiteSpace($SessionId) -or -not $sessionTitleMaps.ContainsKey($ProfileId)) { return '' }
    $map = $sessionTitleMaps[$ProfileId]
    if ($map.ContainsKey($SessionId)) { return [string]$map[$SessionId] }
    return ''
}

function Get-HudSessionIdFromPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $match = [regex]::Match([IO.Path]::GetFileName($Path),'(?i)(?<id>[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})(?:\.jsonl)?$')
    if ($match.Success) { return [string]$match.Groups['id'].Value }
    return ''
}

function Get-HudSessionId {
    param([System.IO.FileInfo]$File)
    return [string](Get-HudSessionIdentity $File).SessionId
}

function Refresh-HudSessionIndex {
    param([Parameter(Mandatory = $true)]$Profile)
    $profileId = [string]$Profile.Id
    $sessionIndexPath = [string]$Profile.SessionIndexPath
    if (-not (Test-Path -LiteralPath $sessionIndexPath -PathType Leaf)) { return $false }
    try { $indexFile = Get-Item -LiteralPath $sessionIndexPath -ErrorAction Stop } catch { return $false }
    if ($indexFile.LastWriteTimeUtc -le [DateTime]$sessionIndexLastWriteUtc[$profileId]) { return $false }
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
    $sessionTitleMaps[$profileId] = $nextMap
    $sessionIndexLastWriteUtc[$profileId] = $indexFile.LastWriteTimeUtc
    $changed = $false
    foreach ($state in @($sessionStates.Values | Where-Object { [string]$_.ProfileId -eq $profileId })) {
        $nextTitle = Get-HudIndexedSessionTitle $profileId ([string]$state.SessionId)
        if ([string]$state.ConversationLabel -ne $nextTitle) { $state.ConversationLabel = $nextTitle; $changed = $true }
        if ($null -ne $state.PSObject.Properties['IsReadBlocked'] -and [bool]$state.IsReadBlocked -and
            $null -ne $state.PSObject.Properties['IdentityMetadataFound'] -and -not [bool]$state.IdentityMetadataFound -and
            -not [string]::IsNullOrWhiteSpace([string]$state.SessionId) -and -not [string]::IsNullOrWhiteSpace($nextTitle)) {
            $state.IdentityMetadataFound = $true
            $state.IdentityProvisional = $true
            $state.NeedsSnapshotHydration = $true
            $changed = $true
        }
    }
    return $changed
}

function Initialize-SessionFile {
    param([System.IO.FileInfo]$File, [Parameter(Mandatory = $true)]$Profile)
    if ($sessionStates.ContainsKey($File.FullName)) { return $false }
    $readBlocked = if ($null -ne $File.PSObject.Properties['ReadBlocked']) { [bool]$File.ReadBlocked } else { [bool](Test-HudSessionFileReadBlocked $File.FullName) }
    $identity = Get-HudSessionIdentity $File
    $needsSnapshotHydration = $false
    $initialSnapshot = $null
    if (-not [bool]$identity.IsInternalSession) {
        try { $initialSnapshot = Get-LatestHudSnapshot $File }
        catch {
            if ($readBlocked -or (Test-HudSessionFileReadBlocked $File.FullName)) {
                $readBlocked = $true
                $needsSnapshotHydration = $true
            } else { throw }
        }
    }
    $sessionId = [string]$identity.SessionId
    $conversationLabel = Get-HudIndexedSessionTitle ([string]$Profile.Id) $sessionId
    $identityProvisional = $false
    $identityMetadataFound = [bool]$identity.MetadataFound
    if (-not $identityMetadataFound -and $readBlocked) {
        $sessionId = Get-HudSessionIdFromPath $File.FullName
        $conversationLabel = Get-HudIndexedSessionTitle ([string]$Profile.Id) $sessionId
        $identityProvisional = -not [string]::IsNullOrWhiteSpace($sessionId) -and -not [string]::IsNullOrWhiteSpace($conversationLabel)
        $identityMetadataFound = $identityProvisional
        $needsSnapshotHydration = $true
    }
    $sessionStates[$File.FullName] = [pscustomobject]@{
        Path = $File.FullName
        FileInfo = $File
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
        TerminalStatus = if ($null -ne $initialSnapshot -and -not [bool]$initialSnapshot.TerminalSilent -and $null -ne $initialSnapshot.PSObject.Properties['TerminalStatus']) { [string]$initialSnapshot.TerminalStatus } else { '' }
        TerminalAt = if ($null -ne $initialSnapshot -and -not [bool]$initialSnapshot.TerminalSilent -and $null -ne $initialSnapshot.PSObject.Properties['TerminalTimestamp'] -and $null -ne $initialSnapshot.TerminalTimestamp) { [DateTimeOffset]$initialSnapshot.TerminalTimestamp } else { [DateTimeOffset]::MinValue }
        TerminalSilent = $false
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
        ContextAlertLevel = 0
        ContextAlertPercent = 0.0
        ContextAlertUntil = [DateTimeOffset]::MinValue
        ActiveTurnId = ''
        PendingCompletionTurnId = ''
        PendingCompletionAt = [DateTimeOffset]::MinValue
        PendingCompletionDueAt = [DateTimeOffset]::MinValue
        Detached = $false
        BubbleWidth = 0.0
        BubbleHeight = 0.0
        IsInternalSession = [bool]$identity.IsInternalSession
        IdentityMetadataFound = [bool]$identityMetadataFound
        IdentityProvisional = [bool]$identityProvisional
        NeedsSnapshotHydration = [bool]$needsSnapshotHydration
        IsReadBlocked = [bool]$readBlocked
        LastLockObservedAt = if ($readBlocked) { [DateTimeOffset]::Now } else { [DateTimeOffset]::MinValue }
        RuntimeActivityAt = [DateTimeOffset]::MinValue
        SessionId = $sessionId
        ConversationLabel = $conversationLabel
        ProfileId = [string]$Profile.Id
        ProfileLabel = [string]$Profile.Label
        ClientSurface = if ([string]$identity.ClientSurface -ne 'unknown') { [string]$identity.ClientSurface } else { [string]$Profile.DefaultClientSurface }
        ModelProvider = if (-not [string]::IsNullOrWhiteSpace([string]$identity.ModelProvider)) { [string]$identity.ModelProvider } else { [string]$Profile.DefaultProvider }
        Dismissed = $false
    }
    $sessionStates[$File.FullName].ConversationLabel = $conversationLabel
    Write-HudDebug ('Session identity loaded: {0}; metadata={1}; officialTitle={2}' -f [string]$sessionStates[$File.FullName].Workspace,[bool]$identity.MetadataFound,(-not [string]::IsNullOrWhiteSpace([string]$sessionStates[$File.FullName].ConversationLabel)))
    return $true
}

function Refresh-HudSessionIdentity {
    param([Parameter(Mandatory = $true)]$State)
    if ($null -ne $State.PSObject.Properties['IsReadBlocked'] -and [bool]$State.IsReadBlocked) { return $false }
    $needsIdentity = ($null -eq $State.PSObject.Properties['IdentityMetadataFound'] -or -not [bool]$State.IdentityMetadataFound) -or
        ($null -ne $State.PSObject.Properties['IdentityProvisional'] -and [bool]$State.IdentityProvisional)
    $needsSnapshot = $null -ne $State.PSObject.Properties['NeedsSnapshotHydration'] -and [bool]$State.NeedsSnapshotHydration
    if (-not $needsIdentity -and -not $needsSnapshot) { return $false }
    $file = if ($null -ne $State.PSObject.Properties['FileInfo'] -and $null -ne $State.FileInfo) { $State.FileInfo } else { [IO.FileInfo]::new([string]$State.Path) }
    $file.Refresh()
    if (-not $file.Exists) { return $false }
    $updated = $false
    if ($needsIdentity) {
        $identity = Get-HudSessionIdentity $file
        if ([bool]$identity.MetadataFound) {
            $State.IdentityMetadataFound = $true
            $State.IdentityProvisional = $false
            $State.IsInternalSession = [bool]$identity.IsInternalSession
            $State.SessionId = [string]$identity.SessionId
            $State.ClientSurface = if ([string]$identity.ClientSurface -ne 'unknown') { [string]$identity.ClientSurface } else { [string]$State.ClientSurface }
            if (-not [string]::IsNullOrWhiteSpace([string]$identity.ModelProvider)) { $State.ModelProvider = [string]$identity.ModelProvider }
            if ([string]::IsNullOrWhiteSpace([string]$State.Workspace) -and -not [string]::IsNullOrWhiteSpace([string]$identity.Workspace)) { $State.Workspace = [string]$identity.Workspace }
            $nextTitle = Get-HudIndexedSessionTitle ([string]$State.ProfileId) ([string]$State.SessionId)
            $State.ConversationLabel = $nextTitle
            Write-HudDebug ('Session identity resolved: {0}; internal={1}; officialTitle={2}' -f [string]$State.Workspace,[bool]$State.IsInternalSession,(-not [string]::IsNullOrWhiteSpace($nextTitle)))
            $updated = $true
        }
    }
    if ($needsSnapshot -and -not [bool]$State.IsInternalSession) {
        try {
            $snapshot = Get-LatestHudSnapshot $file
            $State.Snapshot = $snapshot
            if ($null -ne $snapshot) {
                $State.Model = [string]$snapshot.Model
                if ($null -ne $snapshot.PSObject.Properties['Workspace'] -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.Workspace)) { $State.Workspace = [string]$snapshot.Workspace }
                $State.AllowanceTimestamp = $snapshot.AllowanceTimestamp
                $State.WeeklyRemainingPercent = $snapshot.WeeklyRemainingPercent
                $State.FiveHourRemainingPercent = $snapshot.FiveHourRemainingPercent
                $State.LastUsageAt = [DateTimeOffset]$snapshot.Timestamp
                $State.TerminalStatus = if ([bool]$snapshot.TerminalSilent) { '' } else { [string]$snapshot.TerminalStatus }
                $State.TerminalAt = if (-not [bool]$snapshot.TerminalSilent -and $null -ne $snapshot.TerminalTimestamp) { [DateTimeOffset]$snapshot.TerminalTimestamp } else { [DateTimeOffset]::MinValue }
                $State.TerminalSilent = $false
                $State.HasObservedActivity = $true
            }
            $State.NeedsSnapshotHydration = $false
            $updated = $true
        } catch {
            if (Test-HudSessionFileReadBlocked ([string]$State.Path)) {
                $State.IsReadBlocked = $true
                $State.LastLockObservedAt = [DateTimeOffset]::Now
                $State.LastReadErrorAt = [DateTimeOffset]::MinValue
            } else {
                $State.LastReadErrorAt = [DateTimeOffset]::Now
                $script:lastReadErrorAt = [DateTimeOffset]::Now
            }
        }
    }
    return $updated
}

function Set-HudSessionIdentityFromRecord {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Record)
    if ([string]$Record.type -ne 'session_meta') { return $false }
    $State.IdentityMetadataFound = $true
    if ($null -ne $State.PSObject.Properties['IdentityProvisional']) { $State.IdentityProvisional = $false }
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
        $originator = if ($null -ne $Record.payload.PSObject.Properties['originator']) { [string]$Record.payload.originator } else { '' }
        $sourceName = if ($null -ne $Record.payload.PSObject.Properties['source'] -and $Record.payload.source -is [string]) { [string]$Record.payload.source } else { '' }
        if ($originator -eq 'codex_vscode' -or $originator -eq 'Codex VS Code') { $State.ClientSurface = 'vscode' }
        elseif ($originator -eq 'Codex Desktop' -or $sourceName -eq 'vscode') { $State.ClientSurface = 'desktop' }
        elseif ($originator -match 'codex-tui' -or $sourceName -eq 'cli') { $State.ClientSurface = 'cli' }
        if ($null -ne $Record.payload.PSObject.Properties['model_provider']) {
            $provider = ([string]$Record.payload.model_provider).Trim()
            $State.ModelProvider = if ($provider.Length -gt 40) { $provider.Substring(0,40) } else { $provider }
        }
    }
    $State.ConversationLabel = Get-HudIndexedSessionTitle ([string]$State.ProfileId) ([string]$State.SessionId)
    Write-HudDebug ('Session identity resolved: {0}; internal={1}; officialTitle={2}' -f [string]$State.Workspace,[bool]$State.IsInternalSession,(-not [string]::IsNullOrWhiteSpace([string]$State.ConversationLabel)))
    return $true
}

function Read-AppendedSessionData {
    param([Parameter(Mandatory = $true)]$State)
    if ([string]::IsNullOrWhiteSpace([string]$State.Path)) { return $false }
    if ($null -ne $State.PSObject.Properties['IsReadBlocked'] -and [bool]$State.IsReadBlocked) { return $false }
    try {
        $identityChanged = Refresh-HudSessionIdentity $State
        $file = if ($null -ne $State.PSObject.Properties['FileInfo'] -and $null -ne $State.FileInfo) { $State.FileInfo } else { [IO.FileInfo]::new([string]$State.Path) }
        $file.Refresh()
        if (-not $file.Exists) { return $identityChanged }
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
            if (-not [bool]$State.IdentityMetadataFound) {
                $identityPrefix = $line.Substring(0,[Math]::Min(512,$line.Length))
                if ($identityPrefix -match '"type"\s*:\s*"session_meta"') {
                    try {
                        $rawRecord = $line | ConvertFrom-Json -ErrorAction Stop
                        if (Set-HudSessionIdentityFromRecord $State $rawRecord) { $updated = $true }
                    } catch { }
                }
            }
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
                    $State.PendingCompletionAt = [DateTimeOffset]$item.Timestamp
                    $State.PendingCompletionDueAt = [DateTimeOffset]::Now.AddSeconds([int]$config.attention.completionGraceSeconds)
                    Write-HudDebug ('Pending completion scheduled: {0} turn={1}' -f [string]$State.Workspace,[string]$item.TurnId)
                    if ([int]$config.attention.completionGraceSeconds -eq 0) { [void](Confirm-PendingTaskCompletion $State) }
                }
                $updated = $true
            } elseif ($item.Kind -eq 'completed_silent') {
                Clear-PendingTaskCompletion $State
                $State.TerminalStatus = ''
                $State.TerminalAt = [DateTimeOffset]::MinValue
                $State.TerminalSilent = $false
                Reset-TerminalExitState $State
                Write-HudDebug ('Silent completion ignored: ' + [string]$State.Workspace)
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
                [void](Update-HudContextAlertState $State)
                $updated = $true
            }
        }
        return $updated
    } catch {
        if (Test-HudSessionFileReadBlocked ([string]$State.Path)) {
            $State.IsReadBlocked = $true
            $State.LastLockObservedAt = [DateTimeOffset]::Now
            $State.LastReadErrorAt = [DateTimeOffset]::MinValue
            Write-HudDebug ('Session is temporarily held by Codex: ' + [string]$State.Path)
            return $false
        }
        $State.LastReadErrorAt = [DateTimeOffset]::Now
        $script:lastReadErrorAt = [DateTimeOffset]::Now
        Write-HudDebug ('Session read failed: ' + $_.Exception.Message)
        return $false
    }
}

function Write-HudTaskRegistry {
    try {
        $tasks = @(Get-HudUserTaskStates | Sort-Object Number | ForEach-Object {
            $updatedAt = if ($null -ne $_.PSObject.Properties['RuntimeActivityAt'] -and [DateTimeOffset]$_.RuntimeActivityAt -gt [DateTimeOffset]$_.LastUsageAt) { [DateTimeOffset]$_.RuntimeActivityAt } else { [DateTimeOffset]$_.LastUsageAt }
            [ordered]@{
                task_number = [int]$_.Number
                workspace = [string]$_.Workspace
                status = [string](Get-TaskStatus $_)
                client = [string]$_.ClientSurface
                provider = [string]$_.ModelProvider
                profile = [string]$_.ProfileId
                updated_at = $updatedAt.ToString('O')
            }
        })
        $registry = [ordered]@{ version=2; generated_at=[DateTimeOffset]::Now.ToString('O'); tasks=$tasks }
        [IO.File]::WriteAllText((Join-Path $paths.StateRoot 'task-registry.json'),($registry | ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    } catch { Write-HudDebug ('Task registry update failed: ' + $_.Exception.Message) }
}

function Invoke-HudIdleMemoryTrim {
    $now = [DateTimeOffset]::Now
    if (-not $memoryTrimPending) { return }
    $quietEnough = ($now - $lastMaterialUpdateAt).TotalSeconds -ge 5
    $activeTrimDue = ($now - $lastWorkingSetTrimAt).TotalSeconds -ge 5
    if (-not $quietEnough -and -not $activeTrimDue) { return }
    try {
        $process = [Diagnostics.Process]::GetCurrentProcess()
        if ($process.WorkingSet64 -lt 220MB) { $script:memoryTrimPending = $false; return }
        if (($now - $lastFullGcAt).TotalMinutes -ge 2) {
            [GC]::Collect(2,[GCCollectionMode]::Optimized)
            [GC]::WaitForPendingFinalizers()
            [GC]::Collect(2,[GCCollectionMode]::Optimized)
            $script:lastFullGcAt = $now
        }
        [void][HudNativeMethods]::SetProcessWorkingSetSize([HudNativeMethods]::GetCurrentProcess(),[IntPtr](-1),[IntPtr](-1))
        $script:lastWorkingSetTrimAt = $now
        $script:memoryTrimPending = $false
        Write-HudDebug ('Idle memory trim completed; workingSetMB=' + [Math]::Round($process.WorkingSet64/1MB,1))
    } catch { Write-HudDebug ('Idle memory trim skipped: ' + $_.Exception.Message) }
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

function ConvertFrom-HudExtendedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if ($Path.StartsWith('\\?\UNC\',[StringComparison]::OrdinalIgnoreCase)) { return '\\' + $Path.Substring(8) }
    if ($Path.StartsWith('\\?\',[StringComparison]::OrdinalIgnoreCase)) { return $Path.Substring(4) }
    return $Path
}

function Refresh-ActiveSessions {
    $isInitialScan = -not $initialSessionScanComplete
    $refreshNow = [DateTimeOffset]::Now
    $indexChanged = $false
    $runtimeCutoff = $refreshNow.AddMinutes(-[Math]::Max(3,[int]$config.activeWindowMinutes))
    $candidateMap = @{}
    foreach ($profile in $sessionProfiles) {
        $enabled = if ([string]$profile.Id -eq 'deepseek') {
            [bool]$config.sessionSources.deepSeekCli
        } else {
            [bool]$config.sessionSources.desktop -or [bool]$config.sessionSources.vscode -or [bool]$config.sessionSources.defaultCli
        }
        if (-not $enabled) { continue }
        if (Refresh-HudSessionIndex $profile) { $indexChanged = $true }
        foreach ($file in @(Get-ActiveHudSessionFiles ([string]$profile.SessionsRoot) ([int]$config.activeWindowMinutes) 64)) {
            $candidateMap[$file.FullName] = [pscustomobject]@{ File=$file; Profile=$profile; RuntimeActivityAt=[DateTimeOffset]::MinValue }
        }
        foreach ($activity in @(Get-HudRecentRuntimeSessions ([string]$profile.StateDatabasePath) $runtimeCutoff 64)) {
            try {
                $runtimePath = [IO.Path]::GetFullPath((ConvertFrom-HudExtendedPath ([string]$activity.RolloutPath)))
                $profileRoot = [IO.Path]::GetFullPath([string]$profile.SessionsRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                if (-not $runtimePath.StartsWith($profileRoot,[StringComparison]::OrdinalIgnoreCase)) { continue }
                if ((Get-HudSessionIdFromPath $runtimePath) -ne [string]$activity.SessionId) { continue }
                if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { continue }
                if ($candidateMap.ContainsKey($runtimePath)) {
                    $candidateMap[$runtimePath].RuntimeActivityAt = [DateTimeOffset]$activity.UpdatedAt
                } else {
                    $runtimeFile = Get-Item -LiteralPath $runtimePath -ErrorAction Stop
                    $runtimeFile | Add-Member -NotePropertyName ReadBlocked -NotePropertyValue ([bool](Test-HudSessionFileReadBlocked $runtimePath)) -Force
                    $candidateMap[$runtimePath] = [pscustomobject]@{ File=$runtimeFile; Profile=$profile; RuntimeActivityAt=[DateTimeOffset]$activity.UpdatedAt }
                }
            } catch { continue }
        }
    }
    $candidates = @($candidateMap.Values)
    $cutoff = [DateTime]::UtcNow.AddMinutes(-[Math]::Max(1,[int]$config.activeWindowMinutes))
    $files = @($candidates | Where-Object {
        ($null -ne $_.File.PSObject.Properties['ReadBlocked'] -and [bool]$_.File.ReadBlocked) -or $_.File.LastWriteTimeUtc -ge $cutoff -or [DateTimeOffset]$_.RuntimeActivityAt -ge $runtimeCutoff
    } | Sort-Object @{Expression={ [bool]$_.File.ReadBlocked };Descending=$true},@{Expression={ if ([DateTimeOffset]$_.RuntimeActivityAt -gt [DateTimeOffset]$_.File.LastWriteTimeUtc) { [DateTimeOffset]$_.RuntimeActivityAt } else { [DateTimeOffset]$_.File.LastWriteTimeUtc } };Descending=$true} | Select-Object -First 64)
    $activePaths = @{}
    $changed = [bool]$indexChanged
    foreach ($candidate in $files) {
        $file = $candidate.File
        $profile = $candidate.Profile
        $activePaths[$file.FullName] = $true
        $initialized = Initialize-SessionFile $file $profile
        $state = $sessionStates[$file.FullName]
        $readBlocked = $null -ne $file.PSObject.Properties['ReadBlocked'] -and [bool]$file.ReadBlocked
        if ([bool]$state.IsReadBlocked -ne $readBlocked) { $state.IsReadBlocked = $readBlocked; $changed = $true }
        if ($readBlocked) {
            $state.LastLockObservedAt = $refreshNow
            $state.LastReadErrorAt = [DateTimeOffset]::MinValue
        } elseif (Refresh-HudSessionIdentity $state) { $changed = $true }
        $runtimeActivityAt = [DateTimeOffset]$candidate.RuntimeActivityAt
        if ($runtimeActivityAt -ge $runtimeCutoff) {
            if ($null -eq $state.PSObject.Properties['RuntimeActivityAt']) { $state | Add-Member -NotePropertyName RuntimeActivityAt -NotePropertyValue $runtimeActivityAt }
            elseif ($runtimeActivityAt -gt [DateTimeOffset]$state.RuntimeActivityAt) { $state.RuntimeActivityAt = $runtimeActivityAt; $changed = $true }
            if (-not [string]::IsNullOrWhiteSpace([string]$state.TerminalStatus) -and
                $state.TerminalAt -ne [DateTimeOffset]::MinValue -and
                [DateTimeOffset]$state.RuntimeActivityAt -gt ([DateTimeOffset]$state.TerminalAt).AddSeconds([Math]::Max(2,[int]$config.attention.completionGraceSeconds))) {
                $state.TerminalStatus = ''
                $state.TerminalAt = [DateTimeOffset]::MinValue
                $state.TerminalSilent = $false
                Clear-PendingTaskCompletion $state
                Reset-TerminalExitState $state
                if (@('completed','failed','aborted') -contains [string]$state.AttentionReason) {
                    $state.AttentionReason = ''
                    $state.AttentionUntil = [DateTimeOffset]::MinValue
                }
                $changed = $true
            }
        }
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
            $readBlocked = Test-HudSessionFileReadBlocked ([string]$path)
            if ($readBlocked) {
                if (-not [bool]$state.IsReadBlocked) { $state.IsReadBlocked = $true; $changed = $true }
                $state.LastLockObservedAt = $refreshNow
                $state.LastReadErrorAt = [DateTimeOffset]::MinValue
                $activePaths[$path] = $true
                continue
            }
            if ($null -ne $state.PSObject.Properties['IsReadBlocked'] -and [bool]$state.IsReadBlocked) {
                $state.IsReadBlocked = $false
                $changed = $true
            }
            if ($null -ne $state.PSObject.Properties['LastLockObservedAt'] -and
                $state.LastLockObservedAt -ne [DateTimeOffset]::MinValue -and
                ($refreshNow - [DateTimeOffset]$state.LastLockObservedAt).TotalMinutes -le 10) {
                $activePaths[$path] = $true
                if (Refresh-HudSessionIdentity $state) { $changed = $true }
                continue
            }
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

if ($loadSettingsUi) {
Build-ThemeButtons

function Flush-SliderPreview {
    if (-not $script:sliderPreviewDirty) { return }
    $script:sliderPreviewDirty = $false
    try {
        Save-HudConfig $paths $config
        if ($SettingsHost) {
            [IO.File]::WriteAllText($reloadSettingsSignal, [DateTime]::UtcNow.ToString('O'))
        }
    } catch {
        # An individual preview frame must never bring down the settings host.
        Write-HudDebug ('Slider preview save failed: ' + $_.Exception.Message)
        $saveStatus.Text = [string]$settingsLocale.saveFailed
    }
}

$script:sliderPreviewDirty = $false
$sliderPreviewTimer = New-Object Windows.Threading.DispatcherTimer
$sliderPreviewTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$sliderPreviewTimer.Add_Tick({
    if (-not $script:sliderPreviewDirty) {
        $sliderPreviewTimer.Stop()
        return
    }
    Flush-SliderPreview
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
    # Keep direct manipulation visually continuous without doing unguarded
    # disk I/O for every WPF pixel event.  33 ms is about 30 fps and flushes
    # during the drag rather than only when it stops.
    $script:sliderPreviewDirty = $true
    if (-not $sliderPreviewTimer.IsEnabled) { $sliderPreviewTimer.Start() }
    $saveStatus.Text = ('{0}  {1}' -f [string]$settingsLocale.savedAt, (Get-Date).ToString('HH:mm:ss'))
}

$liveControls = @(
    $languageCombo,$layoutCombo,$numberCombo,$positionCombo,$monitorScopeCombo,$activeWindowCombo,$taskRetentionCombo,$terminalExitModeCombo,
    $displayModeCombo,$listStyleCombo,$listDensityCombo,$listDetailCombo,$taskNameModeCombo,$maxSplitCombo,$numberCooldownCombo,
    $summaryAttentionModeCombo,$listAttentionModeCombo,$taskBubbleAttentionModeCombo,$dotPatternCombo,$dotBrightnessCombo,$dotSpeedCombo,$attentionDurationCombo,$transparencyModeCombo,
    $agentNotificationPermissionCombo,$agentNotificationModeCombo,$agentNotificationIntensityCombo,$agentNotificationDurationCombo,
    $idleIndicatorDelayCombo,$idleIndicatorLayoutCombo,$idleIndicatorTaskStyleCombo,
    $alwaysOnTopCheck,$mousePassthroughCheck,$statusDotCheck,$animateCheck,$autoSplitCheck,$sourceDesktopCheck,$sourceVsCodeCheck,$sourceDefaultCliCheck,$sourceDeepSeekCliCheck,
    $attentionCompletedCheck,$attentionErrorCheck,$attentionSettledCheck,$dotAttentionEnabledCheck,$dotBreathingCheck,$agentNotificationEnabledCheck,
    $openTaskOnDoubleClickCheck,$idleIndicatorEnabledCheck,$idleIndicatorBubblesCheck
) + @($fieldControls.GetEnumerator() | Where-Object { [string]$_.Key -ne 'context' } | ForEach-Object { $_.Value }) + @($bubbleFieldControls.Values)
foreach ($control in $liveControls) {
    if ($control -is [Windows.Controls.ComboBox]) { $control.Add_SelectionChanged({ Apply-ControlsToConfig }) }
    else { $control.Add_Click({ Apply-ControlsToConfig }) }
}
foreach ($control in @($contextThreshold1Text,$contextThreshold2Text,$contextThreshold3Text)) { $control.Add_LostFocus({ Apply-ControlsToConfig }) }
$contextAlertsEnabledCheck.Add_Click({
    if($syncingControls){return}
    $enabled = [bool]$contextAlertsEnabledCheck.IsChecked
    if($enabled){$fieldControls['context'].IsChecked=$true;$contextMetricVisibleCheck.IsChecked=$true}
    Apply-ControlsToConfig
    if($enabled){$saveStatus.Text=[string]$settingsLocale.contextDependencyEnabled}
})
$contextMetricVisibleCheck.Add_Click({
    if($syncingControls){return}
    $visible = [bool]$contextMetricVisibleCheck.IsChecked
    $fieldControls['context'].IsChecked=$visible
    $contextAlertsEnabledCheck.IsChecked=$visible
    Apply-ControlsToConfig
    $saveStatus.Text=if($visible){[string]$settingsLocale.contextDependencyEnabled}else{[string]$settingsLocale.contextDependencyDisabled}
})
$fieldControls['context'].Add_Click({
    if($syncingControls){return}
    $visible = [bool]$fieldControls['context'].IsChecked
    $contextMetricVisibleCheck.IsChecked=$visible
    if(-not $visible){$contextAlertsEnabledCheck.IsChecked=$false}
    Apply-ControlsToConfig
    if(-not $visible){$saveStatus.Text=[string]$settingsLocale.contextDependencyDisabled}
})
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
$closeSettingsButton.Add_Click({
    Flush-SliderPreview
    Save-HudConfig $paths $config
    if ($SettingsHost) { $script:closingApp=$true; $settings.Close() } else { $settings.Hide() }
})
$saveButton.Add_Click({
    Flush-SliderPreview
    Apply-ControlsToConfig
    if ($SettingsHost) { $script:closingApp=$true; $settings.Close() } else { $settings.Hide() }
})
$resetButton.Add_Click({
    $script:config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $script:pricingCatalog = Get-HudPricingCatalog $pluginRoot ([string]$config.pricing.path)
    Sync-ControlsFromConfig
    Save-HudConfig $paths $config
    Update-DisplaySnapshot
})
$settings.Add_Closing({
    Flush-SliderPreview
    Save-HudConfig $paths $config
    if ($SettingsHost) {
        [IO.File]::WriteAllText($reloadSettingsSignal,[DateTime]::UtcNow.ToString('O'))
        $script:closingApp = $true
    } elseif (-not $closingApp) { $_.Cancel = $true; $settings.Hide() }
})
}

if ($SettingsHost) {
    Sync-ControlsFromConfig
    $settingsApplication = [Windows.Application]::new()
    $settings.Add_Loaded({
        # The settings host is short-lived. Keep it above normal/maximized
        # windows for its whole lifetime so an open request is immediately
        # actionable instead of requiring a taskbar click.
        $settings.Topmost = $true
        $settings.Activate() | Out-Null
        $settings.Focus() | Out-Null
    })
    try { $settingsApplication.Run($settings) | Out-Null } finally { Release-HudMutex }
    exit 0
}

$taskListToggleButton.Add_Click({
    # The aggregate toggle only opens or retracts the embedded list.  It must
    # never merge independently detached task bubbles as a side effect.
    if ([string]$config.multiTask.displayMode -eq 'list') {
        $config.multiTask.displayMode = if ($splitWindows.Count -gt 0) { 'split' } else { 'summary' }
    } else {
        $config.multiTask.displayMode = 'list'
    }
    Save-HudConfig $paths $config
    Render-Hud
    Update-ContextMenuText
    $_.Handled = $true
})

$hud.Add_MouseLeftButtonDown({
    if ($_.ClickCount -ge 2) { Show-HudSettings; return }
    if ($_.ButtonState -eq [Windows.Input.MouseButtonState]::Pressed) {
        try {
            $hud.DragMove()
            $screenLeft = [double][Windows.SystemParameters]::VirtualScreenLeft
            $screenTop = [double][Windows.SystemParameters]::VirtualScreenTop
            $screenRight = $screenLeft + [double][Windows.SystemParameters]::VirtualScreenWidth
            $screenBottom = $screenTop + [double][Windows.SystemParameters]::VirtualScreenHeight
            $cursorPosition = [System.Windows.Forms.Cursor]::Position
            $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($hud)
            $cursorLeft = [double]$cursorPosition.X / [double]$dpi.DpiScaleX
            $cursorTop = [double]$cursorPosition.Y / [double]$dpi.DpiScaleY
            if ([double]$hud.Left -ge $screenLeft -and $cursorLeft -le ($screenLeft + 1)) { $hud.Left = $screenLeft - 18 }
            elseif (([double]$hud.Left + [double]$hud.ActualWidth) -le $screenRight -and $cursorLeft -ge ($screenRight - 1)) { $hud.Left = $screenRight - [double]$hud.ActualWidth + 18 }
            if ([double]$hud.Top -ge $screenTop -and $cursorTop -le ($screenTop + 1)) { $hud.Top = $screenTop - 18 }
            elseif (([double]$hud.Top + [double]$hud.ActualHeight) -le $screenBottom -and $cursorTop -ge ($screenBottom - 1)) { $hud.Top = $screenBottom - [double]$hud.ActualHeight + 18 }
            $config.position = 'custom'
            $config.customLeft = [double]$hud.Left + 18
            $config.customTop = [double]$hud.Top + 18
            Save-HudConfig $paths $config
            Position-TaskBubbles
        } catch { }
    }
})
$hud.Add_MouseEnter({ if ($isMainIndicatorCollapsed) { Set-HudIndicatorCollapsed $false } })

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
$trayExitItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Stop-HudApplication -UserInitiated }) })
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
Update-ContextMenuText -Force
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
$exitItem.Add_Click({ Stop-HudApplication -UserInitiated })

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
    if ([IO.File]::Exists($reloadSettingsSignal)) {
        Remove-Item -LiteralPath $reloadSettingsSignal -Force -ErrorAction SilentlyContinue
        $script:config = Get-HudConfig $paths
        $script:locale = Get-RuntimeHudLocale ([string]$config.language)
        $script:settingsLocale = if ([string]$config.language -eq 'symbols') { Get-RuntimeHudLocale 'en' } else { $locale }
        $script:pricingCatalog = Get-HudPricingCatalog $pluginRoot ([string]$config.pricing.path)
        $script:lastHudAppearanceSignature = ''
        $script:lastHudMetricsStructureSignature = ''
        $script:lastTaskListRenderSignature = ''
        [void](Apply-HudAppearance)
        Update-DisplaySnapshot
        Update-ContextMenuText -Force
    }
    if ([IO.File]::Exists($openSignal)) { Remove-Item -LiteralPath $openSignal -Force -ErrorAction SilentlyContinue; Show-HudSettings }
    if ([IO.File]::Exists($showSignal)) { Remove-Item -LiteralPath $showSignal -Force -ErrorAction SilentlyContinue; $hud.Show() }
    if ([IO.File]::Exists($hideSignal)) { Remove-Item -LiteralPath $hideSignal -Force -ErrorAction SilentlyContinue; $hud.Hide() }
    if ([IO.File]::Exists($pauseSignal)) {
        Remove-Item -LiteralPath $pauseSignal -Force -ErrorAction SilentlyContinue
        $script:paused = -not $paused
        Update-ContextMenuText
        Render-Hud
    }
    if ([IO.File]::Exists($passthroughOffSignal)) {
        Remove-Item -LiteralPath $passthroughOffSignal -Force -ErrorAction SilentlyContinue
        Disable-HudMousePassthrough
    }
    if ([IO.File]::Exists($exitSignal)) { Remove-Item -LiteralPath $exitSignal -Force -ErrorAction SilentlyContinue; Stop-HudApplication; return }
    $changed = Process-HudAgentNotifications
    foreach ($state in @($sessionStates.Values)) {
        if ($state.AgentNoticeUntil -ne [DateTimeOffset]::MinValue -and $state.AgentNoticeUntil -le [DateTimeOffset]::Now) {
            $state.AgentNoticeText = ''
            $state.AgentNoticeUntil = [DateTimeOffset]::MinValue
            $state.AgentNoticeRecipe = $null
            if ([string]$state.AttentionReason -eq 'agent') { $state.AttentionUntil = [DateTimeOffset]::MinValue }
            $changed = $true
        }
        if ($state.ContextAlertUntil -ne [DateTimeOffset]::MinValue -and $state.ContextAlertUntil -le [DateTimeOffset]::Now) {
            $state.ContextAlertUntil = [DateTimeOffset]::MinValue
            if ([string]$state.AttentionReason -eq 'context') { $state.AttentionUntil = [DateTimeOffset]::MinValue }
            $changed = $true
        }
    }
    if ($paused) { if ($changed) { Update-DisplaySnapshot }; return }
    if (((Get-Date) - $lastFolderScan).TotalSeconds -ge 1.5) {
        $script:lastFolderScan = Get-Date
        if (Refresh-ActiveSessions) { $changed = $true }
    }
    foreach ($state in @($sessionStates.Values)) {
        $confirmedInternal = $null -ne $state.PSObject.Properties['IdentityMetadataFound'] -and [bool]$state.IdentityMetadataFound -and $null -ne $state.PSObject.Properties['IsInternalSession'] -and [bool]$state.IsInternalSession
        if (-not $confirmedInternal -and (Read-AppendedSessionData $state)) { $changed = $true }
        if (Confirm-PendingTaskCompletion $state) { $changed = $true }
        if (Update-TerminalExitState $state) { $changed = $true }
        $taskStatus = Update-TaskStatusTransition $state
        if ([string]$state.LastRenderedStatus -ne $taskStatus) { $changed = $true }
    }
    if ($changed) {
        $script:lastMaterialUpdateAt = [DateTimeOffset]::Now
        $script:memoryTrimPending = $true
        Update-DisplaySnapshot
    }
    else {
        $nextStatus = Get-HudStatus
        if ($nextStatus -ne $currentStatus) { Render-Hud; Update-ContextMenuText }
        else { Update-HudIdleIndicatorMode }
    }
    Invoke-HudIdleMemoryTrim
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
