# Tabula Rasa: заставка при запуске и окно «Что-то пошло не так».
#
# Подключается в setup.ps1 раньше остального lib\*.ps1 (до проверки обновлений), поэтому ни от чего не зависит:
# своя разметка, своя палитра по теме Windows, без Application и без model.cs. Заставка живёт в отдельном
# STA-потоке со своим Dispatcher: основной поток в это время выполняет шаги старта (git fetch, синхронизация,
# загрузка каталога) и может быть занят — заставка не замирает. Связь — синхронизированный хеш:
# Text (шаг), Progress (0–1), Hidden (спрятать на время диалога), Close.

$script:PbSplash = $null
if ($null -eq $script:PbSpawned) { $script:PbSpawned = $false }   # setup.ps1 запущен скрытым процессом (-Spawned)

# цвета по теме Windows: светлая/тёмная, акцент из DWM; высокая контрастность — системные кисти
function Get-PbSplashXaml {
    $hc = $false
    try { $hc = ([int](Get-ItemPropertyValue 'HKCU:\Control Panel\Accessibility\HighContrast' 'Flags' -ErrorAction Stop) -band 1) -eq 1 } catch { }
    if ($hc) {
        $sys = { param($k) "{DynamicResource {x:Static SystemColors.$($k)BrushKey}}" }
        $c = @{ Bg = (& $sys 'Window'); Border = (& $sys 'WindowText'); Text = (& $sys 'WindowText'); Muted = (& $sys 'GrayText')
                Accent = (& $sys 'Highlight'); AccentFg = (& $sys 'HighlightText'); Track = (& $sys 'Control') }
    } else {
        $dark = $false
        try { $dark = (Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' -ErrorAction Stop) -eq 0 } catch { }
        # тема, выбранная в окне кнопкой в шапке (ui.json), важнее темы Windows
        try {
            $pref = [string]((Get-Content (Join-Path $env:LOCALAPPDATA 'tabula-rasa\ui.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json).Theme)
            if ($pref -eq 'dark') { $dark = $true } elseif ($pref -eq 'light') { $dark = $false }
        } catch { }
        # фирменные цвета Tabula Rasa (как Set-UiPalette в lib\gui.ps1): акцент и текст на нём
        $acc = if ($dark) { '#8B83FF' } else { '#5146E0' }
        $fg = if ($dark) { '#0B0A1F' } else { '#FFFFFF' }
        $c = if ($dark) { @{ Bg = '#17191F'; Border = '#252832'; Text = '#ECEEF3'; Muted = '#A1A7B5'; Track = '#262933' } }
             else { @{ Bg = '#FFFFFF'; Border = '#E3E6EC'; Text = '#15171E'; Muted = '#5A6170'; Track = '#ECEEF3' } }
        $c.Accent = $acc; $c.AccentFg = $fg
    }
    $font = if ($env:windir -and (Test-Path (Join-Path $env:windir 'Fonts\SegUIVar.ttf'))) { 'Segoe UI Variable Text' } else { 'Segoe UI' }
    $x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tabula Rasa" Width="440" SizeToContent="Height" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True"
        Background="Transparent" WindowStartupLocation="CenterScreen" ShowInTaskbar="True" FontFamily="@Font" FontSize="14"
        UseLayoutRounding="True" AutomationProperties.Name="Tabula Rasa: запуск">
  <Border Margin="16" CornerRadius="8" Background="@Bg" BorderBrush="@Border" BorderThickness="1" Padding="24,20,24,22">
    <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="3" Opacity="0.28"/></Border.Effect>
    <StackPanel>
      <DockPanel>
        <Border Width="40" Height="40" CornerRadius="9" Background="@Accent">
          <TextBlock Text="TR" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20" Foreground="@AccentFg" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Margin="14,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="Tabula Rasa" FontSize="20" FontWeight="SemiBold" Foreground="@Text"/>
          <TextBlock Text="Развёртывание и обслуживание компьютера" FontSize="12" Foreground="@Muted"/>
        </StackPanel>
      </DockPanel>
      <TextBlock x:Name="Step" Margin="0,22,0,10" Foreground="@Text" Text="Запуск…" TextTrimming="CharacterEllipsis"/>
      <ProgressBar x:Name="Bar" Height="4" Minimum="0" Maximum="1" Value="0" AutomationProperties.Name="Ход запуска">
        <ProgressBar.Template>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="PART_Track" CornerRadius="2" Background="@Track"/>
              <Border x:Name="PART_Indicator" CornerRadius="2" Background="@Accent" HorizontalAlignment="Left"/>
            </Grid>
          </ControlTemplate>
        </ProgressBar.Template>
      </ProgressBar>
    </StackPanel>
  </Border>
</Window>
'@
    foreach ($k in $c.Keys) { $x = $x.Replace("@$k`"", "$($c[$k])`"") }
    return $x.Replace('@Font"', "$font`"")
}

# поток заставки: окно, таймер 60 мс (шаг, плавный прогресс, спрятать/показать, закрыть), свой цикл сообщений
$script:PbSplashScript = {
    param($Sync, $Xaml)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $w = [Windows.Markup.XamlReader]::Parse($Xaml)
    $step = $w.FindName('Step'); $bar = $w.FindName('Bar')
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(60)
    $t.add_Tick({
        if ($Sync.Close) { $t.Stop(); $w.Close(); return }
        if ($step.Text -ne $Sync.Text) { $step.Text = $Sync.Text }
        $target = [double]$Sync.Progress
        if ($bar.Value -lt $target) { $bar.Value = [Math]::Min($target, $bar.Value + [Math]::Max(0.004, ($target - $bar.Value) * 0.18)) }
        if ($Sync.Hidden -and $w.IsVisible) { $w.Hide() }
        elseif (-not $Sync.Hidden -and -not $w.IsVisible) { $w.Show() }
    })
    $w.add_Closed({ $Sync.Closed = $true; [Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })
    $t.Start()
    $w.Show()
    $Sync.Shown = $true
    [Windows.Threading.Dispatcher]::Run()
}

function Start-PbSplash ([string]$Text = 'Запуск…') {
    if ($script:PbSplash) { return }
    try {
        $sync = [hashtable]::Synchronized(@{ Text = $Text; Progress = 0.0; Hidden = $false; Close = $false; Shown = $false; Closed = $false })
        $rs = [RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        $ps = [PowerShell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript($script:PbSplashScript).AddArgument($sync).AddArgument((Get-PbSplashXaml))
        $script:PbSplash = @{ Sync = $sync; Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke() }
    } catch { $script:PbSplash = $null }
}

# шаг старта: на заставке и в журнале выполнения. $Progress — доля 0–1 (меньше нуля — не менять)
function Set-PbSplash ([string]$Text, [double]$Progress = -1) {
    if ($Text) { Write-Host "  $Text" -ForegroundColor Gray }
    if (-not $script:PbSplash) { return }
    if ($Text) { $script:PbSplash.Sync.Text = $Text }
    if ($Progress -ge 0) { $script:PbSplash.Sync.Progress = $Progress }
}

# спрятать заставку на время диалога (иначе диалог может оказаться под ней) и вернуть
function Set-PbSplashVisible ([bool]$Visible) {
    if ($script:PbSplash) { $script:PbSplash.Sync.Hidden = -not $Visible }
}

# закрыть: окно закрывается в своём потоке; ждать не больше 3 с, чтобы старт не зависел от заставки
function Close-PbSplash {
    $s = $script:PbSplash
    if (-not $s) { return }
    $script:PbSplash = $null
    $s.Sync.Close = $true
    $until = (Get-Date).AddSeconds(3)
    while (-not $s.Handle.IsCompleted -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 50 }
    if ($s.Handle.IsCompleted) {
        try { [void]$s.Ps.EndInvoke($s.Handle) } catch { }
        $s.Ps.Dispose(); $s.Rs.Dispose()
    }
}

# падение программы целиком: окно с причиной и путём к журналу вместо красного текста в скрытой консоли.
# Системное сообщение: оно не зависит от состояния WPF и ждёт нажатия
function Show-PbFatal ($ErrorRecord, [string]$LogPath) {
    Close-PbSplash
    $msg = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    Write-Host "  ОШИБКА: $msg" -ForegroundColor Red
    if ($ErrorRecord.ScriptStackTrace) { Write-Host $ErrorRecord.ScriptStackTrace }
    if ($ErrorRecord.InvocationInfo) { Write-Host $ErrorRecord.InvocationInfo.PositionMessage }
    if (-not $script:PbSpawned) { return }   # консоль (-Console): текста выше достаточно
    $where = if ($LogPath) { "Подробности записаны в журнал выполнения: $LogPath" } else { 'Журнал выполнения не создан.' }
    # системное сообщение, а не окно в стиле программы: после сбоя WPF его окна могут закрываться сразу же
    $open = $false
    if ($env:TR_SMOKE) { return }
    try {
            Add-Type -AssemblyName PresentationFramework
            $text = "Работа Tabula Rasa прервана из-за ошибки.`n`n$msg`n`n$where`n`nИзменения, внесённые до ошибки, записаны в журнал изменений и отменяются через «⋯ → Откат изменений» или undo.ps1."
            $btn = if ($LogPath) { 'YesNo' } else { 'OK' }
            if ($LogPath) { $text += "`n`nОткрыть журнал?" }
            $open = ([Windows.MessageBox]::Show($text, 'Tabula Rasa: что-то пошло не так', $btn, 'Error')) -eq 'Yes'
    } catch { }
    if ($open -and $LogPath -and (Test-Path -LiteralPath $LogPath)) { Start-Process notepad.exe -ArgumentList "`"$LogPath`"" }
}
