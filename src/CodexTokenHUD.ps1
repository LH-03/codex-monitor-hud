param(
    [switch]$Managed,
    [int]$ParentPid = 0,
    [switch]$OpenSettings,
    [switch]$SelfTest,
    [switch]$DebugLog,
    [string]$RenderPreview,
    [string]$RenderSettingsPreview,
    [string]$RenderColorPickerPreview,
    [switch]$PreviewSettingsAdvanced,
    [ValidateSet('zh-CN','en','symbols')][string]$PreviewLanguage = 'zh-CN',
    [ValidateSet('chips','compact','inline','outline','cards','stacked')][string]$PreviewLayout = 'chips',
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
}
'@
}

$pluginRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TokenHud.Core.psm1') -Force
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
$hudHeartbeat = Join-Path $paths.StateRoot 'hud.heartbeat'
$lastHudHeartbeat = [DateTime]::MinValue

$mutex = $null
$isUtilityRun = $SelfTest -or -not [string]::IsNullOrWhiteSpace($RenderPreview) -or -not [string]::IsNullOrWhiteSpace($RenderSettingsPreview) -or -not [string]::IsNullOrWhiteSpace($RenderColorPickerPreview)
if (-not $isUtilityRun) {
    $createdNew = $false
    $mutex = New-Object Threading.Mutex($true, 'Local\CodexTokenHUD', [ref]$createdNew)
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

function New-AuroraBrush {
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point(0, 0)
    $brush.EndPoint = New-Object Windows.Point(1, 1)
    $brush.GradientStops.Add((New-Object Windows.Media.GradientStop(([Windows.Media.ColorConverter]::ConvertFromString('#EE171A2E')), 0.0)))
    $brush.GradientStops.Add((New-Object Windows.Media.GradientStop(([Windows.Media.ColorConverter]::ConvertFromString('#E622365E')), 0.52)))
    $brush.GradientStops.Add((New-Object Windows.Media.GradientStop(([Windows.Media.ColorConverter]::ConvertFromString('#E62B174B')), 1.0)))
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
$locale = Get-HudLocale $paths ([string]$config.language)
$settingsLocale = if ([string]$config.language -eq 'symbols') { Get-HudLocale $paths 'en' } else { $locale }
$snapshot = $null
$sessionStates = @{}
$lastFolderScan = [DateTime]::MinValue
$lastUsageAt = [DateTimeOffset]::MinValue
$lastReadErrorAt = [DateTimeOffset]::MinValue
$paused = $false
$closingApp = $false
$syncingControls = $false
$interactivePreview = $false
$currentStatus = 'idle'
$themes = @(Get-HudThemes $pluginRoot)
$hudHandle = [IntPtr]::Zero
$hudBaseExtendedStyle = $null
$statusPalettes = [ordered]@{
    default = [ordered]@{ active='#FF34C759'; listening='#FF0A84FF'; idle='#FFFF9F0A'; paused='#FF8E8E93'; error='#FFFF453A' }
    intuitive = [ordered]@{ active='#FF30D158'; listening='#FF0A84FF'; idle='#FF8E8E93'; paused='#FFFF9F0A'; error='#FFFF453A' }
    colorblind = [ordered]@{ active='#FF009E73'; listening='#FF56B4E9'; idle='#FF8A8A8A'; paused='#FFE69F00'; error='#FFD55E00' }
    calm = [ordered]@{ active='#FF5AC8A8'; listening='#FF6FA8DC'; idle='#FF9AA0A6'; paused='#FFD4A95B'; error='#FFD97070' }
}

$hud = Load-XamlWindow (Join-Path $PSScriptRoot 'HudWindow.xaml')
Write-HudDebug 'HUD XAML loaded.'
$hudShell = Find-Control $hud 'HudShell'
$hudShadow = Find-Control $hud 'HudShadow'
$statusDot = Find-Control $hud 'StatusDot'
$metricsPanel = Find-Control $hud 'MetricsPanel'

$settings = Load-XamlWindow (Join-Path $PSScriptRoot 'SettingsWindow.xaml')
Write-HudDebug 'Settings XAML loaded.'
$titleBar = Find-Control $settings 'TitleBar'
$closeSettingsButton = Find-Control $settings 'CloseSettingsButton'
$languageCombo = Find-Control $settings 'LanguageCombo'
$layoutCombo = Find-Control $settings 'LayoutCombo'
$numberCombo = Find-Control $settings 'NumberCombo'
$positionCombo = Find-Control $settings 'PositionCombo'
$monitorScopeCombo = Find-Control $settings 'MonitorScopeCombo'
$activeWindowCombo = Find-Control $settings 'ActiveWindowCombo'
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
}
$statusColorButtons = [ordered]@{
    active = Find-Control $settings 'StatusActiveButton'
    listening = Find-Control $settings 'StatusListeningButton'
    idle = Find-Control $settings 'StatusIdleButton'
    paused = Find-Control $settings 'StatusPausedButton'
    error = Find-Control $settings 'StatusErrorButton'
}
$activeSecondsText = Find-Control $settings 'ActiveSecondsText'
$idleSecondsText = Find-Control $settings 'IdleSecondsText'
$errorHoldSecondsText = Find-Control $settings 'ErrorHoldSecondsText'
$resetButton = Find-Control $settings 'ResetButton'
$saveButton = Find-Control $settings 'SaveButton'
$saveStatus = Find-Control $settings 'SaveStatus'
$settingsScrollViewer = Find-Control $settings 'SettingsScrollViewer'

$fieldControls = [ordered]@{}
foreach ($key in @('Input','Cached','Uncached','Output','Reasoning','CallTotal','TaskTotal','Context','Model','Updated','ActiveTasks','WeeklyRemaining')) {
    $control = Find-Control $settings ('Field' + $key)
    $fieldControls[[string]$control.Tag] = $control
}

$settingsTextControls = @{}
foreach ($name in @(
    'SettingsSubtitle','PresetsTitle','PresetsHint','LanguageLayoutTitle','DisplayLanguageLabel','BubbleStyleLabel',
    'NumberFormatLabel','PositionLabel','MonitorScopeLabel','ActiveWindowLabel','MetricsTitle','MetricsHint',
    'AppearanceTitle','FontSizeLabel','RadiusLabel','OpacityLabel','BackgroundColorLabel','ForegroundColorLabel','AccentColorLabel',
    'MousePassthroughHint','StatusPalettesTitle','StatusPalettesHint'
)) { $settingsTextControls[$name] = Find-Control $settings $name }

$settingsContentControls = @{}
foreach ($name in @(
    'PresetFrost','PresetMidnight','PresetAurora','PresetGraphite','PresetMinimal',
        'LanguageZhItem','LanguageEnItem','LanguageSymbolsItem','LayoutChipsItem','LayoutCompactItem','LayoutInlineItem','LayoutOutlineItem','LayoutCardsItem','LayoutStackedItem',
    'NumberExactItem','NumberCompactItem','NumberAutoItem','PositionTopRightItem','PositionTopCenterItem','PositionTopLeftItem',
    'PositionBottomRightItem','PositionBottomCenterItem','PositionBottomLeftItem','MonitorLatestItem','MonitorAggregateItem',
    'ActiveWindow5Item','ActiveWindow15Item','ActiveWindow30Item','ActiveWindow60Item',
    'StatusPaletteDefault','StatusPaletteIntuitive','StatusPaletteColorblind','StatusPaletteCalm'
)) { $settingsContentControls[$name] = Find-Control $settings $name }

$presetPanel = $settingsContentControls['PresetFrost'].Parent
$themeButtons = @{}

$colorPicker = Load-XamlWindow (Join-Path $PSScriptRoot 'ColorPickerWindow.xaml')
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
        SettingsSubtitle='settingsSubtitle'; PresetsTitle='presetsTitle'; PresetsHint='presetsHint';
        LanguageLayoutTitle='languageLayoutTitle'; DisplayLanguageLabel='displayLanguage'; BubbleStyleLabel='bubbleStyle';
        NumberFormatLabel='numberFormat'; PositionLabel='position'; MonitorScopeLabel='monitorScope'; ActiveWindowLabel='activeWindow';
        MetricsTitle='metricsTitle'; MetricsHint='metricsHint'; AppearanceTitle='appearanceTitle'; FontSizeLabel='fontSize';
        RadiusLabel='cornerRadius'; OpacityLabel='opacity'; BackgroundColorLabel='backgroundColor';
        ForegroundColorLabel='foregroundColor'; AccentColorLabel='accentColor'; MousePassthroughHint='mousePassthroughHint';
        StatusPalettesTitle='statusPalettesTitle'; StatusPalettesHint='statusPalettesHint'
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
        PositionTopRightItem='positionTopRight'; PositionTopCenterItem='positionTopCenter'; PositionTopLeftItem='positionTopLeft';
        PositionBottomRightItem='positionBottomRight'; PositionBottomCenterItem='positionBottomCenter'; PositionBottomLeftItem='positionBottomLeft';
        MonitorLatestItem='monitorLatest'; MonitorAggregateItem='monitorAggregate';
        ActiveWindow5Item='minutes5'; ActiveWindow15Item='minutes15'; ActiveWindow30Item='minutes30'; ActiveWindow60Item='minutes60';
        StatusPaletteDefault='statusPaletteDefault'; StatusPaletteIntuitive='statusPaletteIntuitive';
        StatusPaletteColorblind='statusPaletteColorblind'; StatusPaletteCalm='statusPaletteCalm'
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
    foreach($pair in @(@($backgroundColorButton,$backgroundText),@($foregroundColorButton,$foregroundText),@($accentColorButton,$accentText))){
        try{$pair[0].Foreground=New-HudBrush ([string]$pair[1].Text) '#FF0A84FF'}catch{}
    }
    foreach($key in $statusColorButtons.Keys){try{$statusColorButtons[$key].Foreground=New-HudBrush ([string]$statusTextControls[$key].Text) '#FF8E8E93'}catch{}}
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
$pickerApplyButton.Add_Click({$pickerTargetText.Text=Format-HudColor (Get-PickerColor);Update-ColorSwatches;Apply-ControlsToConfig;$colorPicker.Hide()})
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
    $text.Text = if ($paused) { [string]$locale.paused } else { [string]$locale.waiting }
    $text.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Microsoft YaHei UI')
    $text.FontSize = [double]$config.fontSize
    $text.FontWeight = [Windows.FontWeights]::SemiBold
    $text.Foreground = New-HudBrush ([string]$config.foreground) '#FFFFFFFF'
    $text.VerticalAlignment = [Windows.VerticalAlignment]::Center
    [void]$metricsPanel.Children.Add($text)
}

function Add-HudSeparator {
    if ($metricsPanel.Children.Count -eq 0) { return }
    $separator = New-Object Windows.Controls.TextBlock
    $separator.Text = if ([string]$config.separator -eq 'bar') { '|' } else { [char]0x00B7 }
    $separator.Margin = New-Object Windows.Thickness(7, 0, 7, 0)
    $separator.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $separator.Foreground = New-HudBrush ([string]$config.muted) '#FF8A94A6'
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
    $label.Foreground = New-HudBrush ([string]$config.muted) '#FF8A94A6'
    $label.VerticalAlignment = [Windows.VerticalAlignment]::Center
    $label.Margin = if ([string]$config.layout -eq 'cards') { New-Object Windows.Thickness(0, 0, 0, 2) } else { New-Object Windows.Thickness(0, 0, 6, 0) }

    $value = New-Object Windows.Controls.TextBlock
    $value.Text = [string]$Metric.Value
    $value.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Variable Text, Microsoft YaHei UI')
    $value.FontSize = [double]$config.fontSize
    $value.FontWeight = [Windows.FontWeights]::SemiBold
    $value.Foreground = New-HudBrush ([string]$config.foreground) '#FFFFFFFF'
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

function Get-HudStatus {
    if ($paused) { return 'paused' }
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
    $keys = @{ active='statusActive'; listening='statusListening'; idle='statusIdle'; paused='statusPaused'; error='statusError' }
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
        @('exitItem','exit')
    )){
        $variable=Get-Variable -Name $pair[0] -Scope Script -ErrorAction SilentlyContinue
        if($null-ne$variable -and $null-ne$variable.Value){$variable.Value.Header=Get-BilingualText ([string]$pair[1])}
    }
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
    $trayDisablePassthroughItem.Text = ('{0} / {1}' -f [string]$trayZh.disableMousePassthrough, [string]$trayEn.disableMousePassthrough)
    $trayDisablePassthroughItem.Enabled = [bool]$config.mousePassthrough
    $trayExitItem.Text = ('{0} HUD / {1} HUD' -f [string]$trayZh.exit, [string]$trayEn.exit)
    $trayIcon.Text = if ([bool]$config.mousePassthrough) { 'Codex Token HUD - click-through ON' } else { 'Codex Token HUD - monitoring' }
}

function Disable-HudMousePassthrough {
    if (-not [bool]$config.mousePassthrough) { return }
    $config.mousePassthrough = $false
    Save-HudConfig $paths $config
    Sync-ControlsFromConfig
    Apply-HudAppearance
    Update-ContextMenuText
}

function Set-HudMousePassthrough {
    param([bool]$Enabled)
    if ($hudHandle -eq [IntPtr]::Zero) { return }
    $gwlExStyle = -20
    $wsExTransparent = 0x00000020
    $wsExNoActivate = 0x08000000
    $current = [HudNativeMethods]::GetWindowLong($hudHandle, $gwlExStyle)
    if ($null -eq $hudBaseExtendedStyle) { $script:hudBaseExtendedStyle = $current }
    if ($Enabled) {
        $next = $current -bor $wsExTransparent -bor $wsExNoActivate
    } else {
        $next = $current
        if (($hudBaseExtendedStyle -band $wsExTransparent) -eq 0) { $next = $next -band (-bnot $wsExTransparent) }
        if (($hudBaseExtendedStyle -band $wsExNoActivate) -eq 0) { $next = $next -band (-bnot $wsExNoActivate) }
    }
    if ($next -ne $current) { [void][HudNativeMethods]::SetWindowLong($hudHandle, $gwlExStyle, $next) }
}

function Apply-HudAppearance {
    $script:locale = Get-HudLocale $paths ([string]$config.language)
    $hud.Topmost = [bool]$config.alwaysOnTop
    Set-HudMousePassthrough ([bool]$config.mousePassthrough)
    $hud.Opacity = [double]$config.opacity
    $hudShell.CornerRadius = New-Object Windows.CornerRadius([double]$config.cornerRadius)
    $hudShell.BorderBrush = New-HudBrush ([string]$config.border) '#22FFFFFF'
    $hudShell.Background = if ([string]$config.preset -eq 'aurora') { New-AuroraBrush } else { New-HudBrush ([string]$config.background) '#EAFFFFFF' }
    $script:currentStatus = Get-HudStatus
    $statusColor = [string]$config.statusColors.$currentStatus
    $statusDot.Fill = New-HudBrush $statusColor '#FF8E8E93'
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
    $hud.UpdateLayout()
    if ([string]$config.position -ne 'custom') { Move-HudToConfiguredPosition }
    if ([bool]$config.animateUpdates -and -not $interactivePreview) {
        $animation = New-Object Windows.Media.Animation.DoubleAnimation(0.58, 1.0, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(240))))
        $hudShell.BeginAnimation([Windows.UIElement]::OpacityProperty, $animation)
    }
}

function Export-HudPreview {
    param([Parameter(Mandatory = $true)][string]$Path)
    $script:config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    $script:config.language = $PreviewLanguage
    $script:config.layout = $PreviewLayout
    if ($PreviewFontSize -gt 0) { $script:config.fontSize = [Math]::Round($PreviewFontSize, 1) }
    $script:config.fields.weeklyRemaining = $true
    $script:locale = Get-HudLocale $paths ([string]$config.language)
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

function Set-Preset {
    param([string]$Name)
    $theme = $themes | Where-Object { [string]$_.id -eq $Name } | Select-Object -First 1
    if ($null -eq $theme) { return }
    $config.preset = $Name
    $appearanceKeys = @('background','foreground','muted','accent','border','cornerRadius','opacity','fontSize')
    foreach($property in $theme.settings.PSObject.Properties){
        if($appearanceKeys -contains $property.Name -and $null-ne$config.PSObject.Properties[$property.Name]){$config.($property.Name)=$property.Value}
    }
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
        Apply-SettingsLanguage
        foreach ($key in $fieldControls.Keys) { $fieldControls[$key].IsChecked = [bool]$config.fields.$key }
        $fontSizeSlider.Value = [double]$config.fontSize
        $radiusSlider.Value = [double]$config.cornerRadius
        $opacitySlider.Value = [double]$config.opacity
        $alwaysOnTopCheck.IsChecked = [bool]$config.alwaysOnTop
        $mousePassthroughCheck.IsChecked = [bool]$config.mousePassthrough
        $statusDotCheck.IsChecked = [bool]$config.showStatusDot
        $animateCheck.IsChecked = [bool]$config.animateUpdates
        $backgroundText.Text = [string]$config.background
        $foregroundText.Text = [string]$config.foreground
        $accentText.Text = [string]$config.accent
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
    $content = $settings.Content
    $size = New-Object Windows.Size(720, 790)
    $content.Measure($size)
    $content.Arrange((New-Object Windows.Rect(0, 0, 720, 790)))
    $content.UpdateLayout()
    $settingsScrollViewer.ScrollToHome()
    if ($PreviewSettingsAdvanced) {
        $advancedStatusExpander.IsExpanded = $true
        $settingsScrollViewer.ScrollToEnd()
    } else { $settingsScrollViewer.ScrollToTop() }
    $settingsScrollViewer.ScrollToLeftEnd()
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
    if ($language) { $config.language = $language }
    if ($layout) { $config.layout = $layout }
    if ($number) { $config.numberFormat = $number }
    if ($position) { $config.position = $position }
    if ($monitorScope) { $config.monitorScope = $monitorScope }
    if ($activeWindow) { $config.activeWindowMinutes = [int]$activeWindow }
    Apply-SettingsLanguage
    foreach ($key in $fieldControls.Keys) { $config.fields.$key = [bool]$fieldControls[$key].IsChecked }
    $config.fontSize = [Math]::Round([double]$fontSizeSlider.Value, 1)
    $config.cornerRadius = [int]$radiusSlider.Value
    $config.opacity = [Math]::Round([double]$opacitySlider.Value, 2)
    $config.alwaysOnTop = [bool]$alwaysOnTopCheck.IsChecked
    $config.mousePassthrough = [bool]$mousePassthroughCheck.IsChecked
    $config.showStatusDot = [bool]$statusDotCheck.IsChecked
    $config.animateUpdates = [bool]$animateCheck.IsChecked
    foreach ($pair in @(@('background',$backgroundText.Text), @('foreground',$foregroundText.Text), @('accent',$accentText.Text))) {
        try { [void](New-HudBrush ([string]$pair[1])); $config.($pair[0]) = [string]$pair[1] } catch { }
    }
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
    Save-HudConfig $paths $config
    Update-DisplaySnapshot
    $saveStatus.Text = ('{0}  {1}' -f [string]$settingsLocale.savedAt, (Get-Date).ToString('HH:mm:ss'))
}

function Show-HudSettings {
    Sync-ControlsFromConfig
    if (-not $settings.IsVisible) { $settings.Show() }
    $settings.Activate() | Out-Null
}

function Initialize-SessionFile {
    param([System.IO.FileInfo]$File)
    if ($sessionStates.ContainsKey($File.FullName)) { return $false }
    $initialSnapshot = Get-LatestHudSnapshot $File
    $sessionStates[$File.FullName] = [pscustomobject]@{
        Path = $File.FullName
        Offset = [Int64]$File.Length
        PendingText = ''
        Model = if ($null -ne $initialSnapshot) { [string]$initialSnapshot.Model } else { '' }
        Snapshot = $initialSnapshot
        AllowanceTimestamp = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['AllowanceTimestamp']) { $initialSnapshot.AllowanceTimestamp } else { $null }
        WeeklyRemainingPercent = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['WeeklyRemainingPercent']) { $initialSnapshot.WeeklyRemainingPercent } else { $null }
        FiveHourRemainingPercent = if ($null -ne $initialSnapshot -and $null -ne $initialSnapshot.PSObject.Properties['FiveHourRemainingPercent']) { $initialSnapshot.FiveHourRemainingPercent } else { $null }
        LastWriteTimeUtc = $File.LastWriteTimeUtc
    }
    return $true
}

function Read-AppendedSessionData {
    param([Parameter(Mandatory = $true)]$State)
    if ([string]::IsNullOrWhiteSpace([string]$State.Path) -or -not (Test-Path -LiteralPath $State.Path)) { return $false }
    try {
        $file = Get-Item -LiteralPath $State.Path
        $State.LastWriteTimeUtc = $file.LastWriteTimeUtc
        if ($file.Length -lt $State.Offset) {
            $State.Offset = [Int64]0
            $State.PendingText = ''
            $State.Model = ''
        }
        if ($file.Length -eq $State.Offset) { return $false }
        $stream = New-Object IO.FileStream($State.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            [void]$stream.Seek($State.Offset, [IO.SeekOrigin]::Begin)
            $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $State.Offset = [Int64]$stream.Position
        } finally { $stream.Dispose() }

        $split = Split-HudJsonLines ([string]$State.PendingText) $text
        $State.PendingText = [string]$split.PendingText
        $updated = $false
        foreach ($line in @($split.CompleteLines)) {
            $item = Convert-HudRecord $line
            if ($null -eq $item) { continue }
            if ($item.Kind -eq 'context') { $State.Model = [string]$item.Model }
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
                if ($null -ne $State.AllowanceTimestamp) {
                    $item.AllowanceTimestamp = $State.AllowanceTimestamp
                    $item.WeeklyRemainingPercent = $State.WeeklyRemainingPercent
                    $item.FiveHourRemainingPercent = $State.FiveHourRemainingPercent
                }
                $State.Snapshot = $item
                $script:lastUsageAt = [DateTimeOffset]::Now
                $updated = $true
            }
        }
        return $updated
    } catch { $script:lastReadErrorAt = [DateTimeOffset]::Now; return $false }
}

function Update-DisplaySnapshot {
    $snapshots = @($sessionStates.Values | ForEach-Object { $_.Snapshot } | Where-Object { $null -ne $_ })
    if ($snapshots.Count -eq 0) { $script:snapshot = $null; Render-Hud; return }
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
}

function Refresh-ActiveSessions {
    $files = @(Get-ActiveHudSessionFiles $paths.SessionsRoot ([int]$config.activeWindowMinutes))
    $activePaths = @{}
    $changed = $false
    foreach ($file in $files) {
        $activePaths[$file.FullName] = $true
        if (Initialize-SessionFile $file) { $changed = $true }
    }
    foreach ($path in @($sessionStates.Keys)) {
        if (-not $activePaths.ContainsKey($path)) { $sessionStates.Remove($path); $changed = $true }
    }
    return $changed
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

$liveControls = @($languageCombo,$layoutCombo,$numberCombo,$positionCombo,$monitorScopeCombo,$activeWindowCombo,$alwaysOnTopCheck,$mousePassthroughCheck,$statusDotCheck,$animateCheck) + @($fieldControls.Values)
foreach ($control in $liveControls) {
    if ($control -is [Windows.Controls.ComboBox]) { $control.Add_SelectionChanged({ Apply-ControlsToConfig }) }
    else { $control.Add_Click({ Apply-ControlsToConfig }) }
}
$fontSizeSlider.Add_ValueChanged({ Apply-SliderPreview 'fontSize' })
$radiusSlider.Add_ValueChanged({ Apply-SliderPreview 'cornerRadius' })
$opacitySlider.Add_ValueChanged({ Apply-SliderPreview 'opacity' })
foreach ($textBox in @($backgroundText,$foregroundText,$accentText,$activeSecondsText,$idleSecondsText,$errorHoldSecondsText)) { $textBox.Add_LostFocus({ Apply-ControlsToConfig }) }
foreach ($textBox in @($statusTextControls.Values)) { $textBox.Add_LostFocus({ Apply-ControlsToConfig -StatusColorsChanged }) }

foreach($pair in @(@($backgroundColorButton,$backgroundText),@($foregroundColorButton,$foregroundText),@($accentColorButton,$accentText))){
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
$closeSettingsButton.Add_Click({ Save-HudConfig $paths $config; $settings.Hide() })
$saveButton.Add_Click({ Apply-ControlsToConfig; $settings.Hide() })
$resetButton.Add_Click({
    $script:config = Get-Content -Raw -Encoding UTF8 -LiteralPath $paths.DefaultConfigPath | ConvertFrom-Json
    Sync-ControlsFromConfig
    Save-HudConfig $paths $config
    Update-DisplaySnapshot
})
$settings.Add_Closing({
    if (-not $closingApp) { $_.Cancel = $true; Save-HudConfig $paths $config; $settings.Hide() }
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
        } catch { }
    }
})

$contextMenu = New-Object Windows.Controls.ContextMenu
$statusItem = New-Object Windows.Controls.MenuItem
$settingsItem = New-Object Windows.Controls.MenuItem
$passthroughItem = New-Object Windows.Controls.MenuItem
$pauseItem = New-Object Windows.Controls.MenuItem
$positionItem = New-Object Windows.Controls.MenuItem
$exitItem = New-Object Windows.Controls.MenuItem

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = [System.Drawing.SystemIcons]::Information
$trayIcon.Visible = $true
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayStatusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayStatusItem.Enabled = $false
$trayOpenSettingsItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayDisablePassthroughItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayExitItem = New-Object System.Windows.Forms.ToolStripMenuItem
[void]$trayMenu.Items.Add($trayStatusItem)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayMenu.Items.Add($trayOpenSettingsItem)
[void]$trayMenu.Items.Add($trayDisablePassthroughItem)
[void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$trayMenu.Items.Add($trayExitItem)
$trayIcon.ContextMenuStrip = $trayMenu
$trayOpenSettingsItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Show-HudSettings }) })
$trayDisablePassthroughItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Disable-HudMousePassthrough }) })
$trayExitItem.Add_Click({ [void]$hud.Dispatcher.BeginInvoke([Action]{ $script:closingApp = $true; $settings.Close(); $hud.Close() }) })
$trayIcon.Add_DoubleClick({ [void]$hud.Dispatcher.BeginInvoke([Action]{ Show-HudSettings }) })
$statusItem.IsEnabled = $false
[void]$contextMenu.Items.Add($statusItem)
[void]$contextMenu.Items.Add((New-Object Windows.Controls.Separator))
[void]$contextMenu.Items.Add($settingsItem)
[void]$contextMenu.Items.Add($passthroughItem)
[void]$contextMenu.Items.Add($pauseItem)
[void]$contextMenu.Items.Add($positionItem)
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
$positionItem.Add_Click({ if ([string]$config.position -eq 'custom') { $config.position = 'top-right' }; Move-HudToConfiguredPosition; Save-HudConfig $paths $config })
$exitItem.Add_Click({ $script:closingApp = $true; $settings.Close(); $hud.Close() })

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
            $script:closingApp = $true; $settings.Close(); $hud.Close(); return
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
    if (Test-Path -LiteralPath $exitSignal) { Remove-Item -LiteralPath $exitSignal -Force -ErrorAction SilentlyContinue; $script:closingApp = $true; $settings.Close(); $hud.Close(); return }
    $nextStatus = Get-HudStatus
    if($nextStatus -ne $currentStatus){Render-Hud;Update-ContextMenuText}
    if ($paused) { return }
    $changed = $false
    if (((Get-Date) - $lastFolderScan).TotalSeconds -ge 3) {
        $script:lastFolderScan = Get-Date
        if (Refresh-ActiveSessions) { $changed = $true }
    }
    foreach ($state in @($sessionStates.Values)) {
        if (Read-AppendedSessionData $state) { $changed = $true }
    }
    if ($changed) { Update-DisplaySnapshot }
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
    try { $trayIcon.Visible = $false; $trayIcon.Dispose() } catch { }
    Remove-Item -LiteralPath $hudHeartbeat -Force -ErrorAction SilentlyContinue
    try { $colorPicker.Close() } catch { }
    try { $settings.Close() } catch { }
    Release-HudMutex
})

$application = [Windows.Application]::new()
$application.Add_DispatcherUnhandledException({
    Write-HudDebug ('Dispatcher error: ' + ($_.Exception | Out-String))
})
Write-HudDebug 'Starting WPF application loop.'
$application.Run($hud) | Out-Null
