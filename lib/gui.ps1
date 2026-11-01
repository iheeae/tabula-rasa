# Tabula Rasa: окно выбора на WPF (есть в Windows PowerShell 5.1 из коробки, внешних библиотек нет).
# Разметка и стили — lib\ui\*.xaml, модель для привязок — lib\ui\model.cs. WPF нужен STA-поток:
# setup.ps1 перезапускает себя с -STA, если запущен иначе.
#   * слева навигация: Программы / Настройки Windows / Файлы по категориям со счётчиками, внизу «Итог»
#   * в центре карточки категории; значки ⚙ (есть Config), мастер, необратимо, сайт, «мой каталог» видны без клика
#   * справа подробности выделенного; у программ с Config — «Установка: с моими настройками / чистая»
#   * в шапке — режим окна «Установка | Снятие настроек» (снятие: lib\configs.ps1) и «Программа» — добавить из winget
#     в собственный каталог (lib\catalog.ps1, окно addapp.xaml)
#   * поиск сверху — сразу по всем разделам; «Сохранения ▾» — свои наборы галочек (lib\data.ps1)
#   * слева внизу «Мои данные»: подключить (вход в GitHub, клон своего приватного репозитория), отправить, отключить и удалить
#   * «Файлы» — релиз files «Моих данных» (lib\files.ps1): список приходит в фоне; без подключения — карточка с кнопкой
#   * тема и акцент — как в Windows
#
# Возвращает @{ Apps; Configs; Tweaks; Files; FileTitles; Name } (для -Console) или $null, если окно закрыли.

$script:PbUiDir = Join-Path $PSScriptRoot 'ui'
. (Join-Path $PSScriptRoot 'data.ps1')
. (Join-Path $PSScriptRoot 'files.ps1')
. (Join-Path $PSScriptRoot 'catalog.ps1')
. (Join-Path $PSScriptRoot 'status.ps1')
. (Join-Path $PSScriptRoot 'run.ps1')
. (Join-Path $PSScriptRoot 'selfremove.ps1')

# ---------- оформление ----------

# тема: светлая/тёмная — по выбору в окне (кнопка в шапке, $script:PbThemePref = light | dark, хранится в ui.json)
# или как в Windows (auto). Цвета — фирменные (Set-UiPalette), не системный акцент: так контраст везде предсказуем.
# Segoe UI Variable, если есть
$script:PbThemePref = $null
$script:PbBrandAccent = '#5146E0'   # фирменный индиго Tabula Rasa (значок, заставка, светлая тема)
function Get-UiTheme {
    if ($null -eq $script:PbThemePref) {
        $script:PbThemePref = 'auto'
        $st = Read-UiState
        if ($st -and $st.Theme -in 'light', 'dark') { $script:PbThemePref = [string]$st.Theme }
    }
    $dark = $false
    try { $dark = (Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' -ErrorAction Stop) -eq 0 } catch { }
    if ($script:PbThemePref -eq 'dark') { $dark = $true } elseif ($script:PbThemePref -eq 'light') { $dark = $false }
    $accent = [Windows.Media.ColorConverter]::ConvertFromString($script:PbBrandAccent)
    # файл шрифта вместо перечисления всех системных шрифтов: то занимало заметную часть старта окна
    $font = if (Test-Path (Join-Path $env:windir 'Fonts\SegUIVar.ttf')) { 'Segoe UI Variable Text' } else { 'Segoe UI' }
    return @{ Dark = $dark; Accent = $accent; Font = $font }
}

# кисти, на которые ссылается theme.xaml (DynamicResource)
function Set-UiPalette ($Res, $Theme) {
    # высокая контрастность: только системные цвета, свои не подмешиваются
    if ([Windows.SystemParameters]::HighContrast) {
        $sc = [Windows.SystemColors]
        $map = @{ Bg = $sc::WindowColor; Surface = $sc::WindowColor; SurfaceHover = $sc::WindowColor; SurfaceStrong = $sc::HighlightColor; NavHover = $sc::WindowColor
                  Border = $sc::WindowTextColor; Control = $sc::ControlColor; ControlHover = $sc::ControlColor; ControlPressed = $sc::ControlColor
                  ControlBorder = $sc::WindowTextColor; ControlStrong = $sc::WindowTextColor; Text = $sc::WindowTextColor; TextMuted = $sc::GrayTextColor
                  PillBg = $sc::WindowColor; Danger = $sc::HotTrackColor; DangerSoft = $sc::WindowColor; ScrollThumb = $sc::ControlDarkColor
                  Accent = $sc::HighlightColor; AccentFg = $sc::HighlightTextColor; AccentText = $sc::HotTrackColor; AccentSoft = $sc::WindowColor; Focus = $sc::WindowTextColor
                  Success = $sc::WindowTextColor; SuccessSoft = $sc::WindowColor; Warning = $sc::WindowTextColor; WarningSoft = $sc::WindowColor }
        foreach ($k in $map.Keys) { $b = New-Object Windows.Media.SolidColorBrush $map[$k]; $b.Freeze(); $Res[$k] = $b.PSObject.BaseObject }
        $Res['ShadowColor'] = [Windows.SystemColors]::WindowTextColor
        $Res['UiFont'] = (New-Object Windows.Media.FontFamily $Theme.Font).PSObject.BaseObject
        return
    }
    # фирменная палитра. Контраст текста к фону — не ниже 4,5:1 во всех сочетаниях (Text/TextMuted/AccentText/статусы
    # на Bg, Surface, SurfaceStrong, PillBg); проверяется в CI по живому окну (tests\smoke.ps1, Find-UiContrastIssues)
    if ($Theme.Dark) {
        $p = @{ Bg = '#0F1015'; Surface = '#17191F'; SurfaceHover = '#1E2028'; SurfaceStrong = '#262933'; NavHover = '#1C1E25'
                Border = '#252832'; Control = '#1D1F27'; ControlHover = '#262933'; ControlPressed = '#1A1C23'; ControlBorder = '#363A46'
                ControlStrong = '#8D94A3'; Text = '#ECEEF3'; TextMuted = '#A1A7B5'; PillBg = '#232630'; ScrollThumb = '#3A3E4A'
                Danger = '#FF8F85'; DangerSoft = '#3A1E1E'; Success = '#5CD18A'; SuccessSoft = '#16301F'; Warning = '#F2B75B'; WarningSoft = '#3A2C14'
                Accent = '#8B83FF'; AccentFg = '#0B0A1F'; AccentText = '#A9A3FF'; AccentSoft = '#2E2E4C'; Focus = '#A9A3FF'; Shadow = '#000000' }
    } else {
        $p = @{ Bg = '#F3F4F7'; Surface = '#FFFFFF'; SurfaceHover = '#F7F8FA'; SurfaceStrong = '#ECEEF3'; NavHover = '#E9EBF0'
                Border = '#E3E6EC'; Control = '#FFFFFF'; ControlHover = '#F4F5F8'; ControlPressed = '#ECEEF3'; ControlBorder = '#D5D9E1'
                ControlStrong = '#868D9C'; Text = '#15171E'; TextMuted = '#5A6170'; PillBg = '#EEF0F4'; ScrollThumb = '#C3C8D1'
                Danger = '#C4271B'; DangerSoft = '#FCE9E7'; Success = '#146C34'; SuccessSoft = '#E3F4E8'; Warning = '#8F5400'; WarningSoft = '#FDF1DC'
                Accent = $script:PbBrandAccent; AccentFg = '#FFFFFF'; AccentText = '#4338CA'; AccentSoft = '#E7E5FB'; Focus = '#5146E0'; Shadow = '#1B1F2A' }
    }
    # BaseObject: иначе в словарь попадает обёртка PSObject и WPF видит строку вместо кисти
    foreach ($k in $p.Keys) {
        $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($p[$k])); $b.Freeze()
        $Res[$k] = $b.PSObject.BaseObject
    }
    $Res['ShadowColor'] = ([Windows.Media.ColorConverter]::ConvertFromString($p.Shadow)).PSObject.BaseObject
    $Res['UiFont'] = (New-Object Windows.Media.FontFamily $Theme.Font).PSObject.BaseObject
}

# значок окна: монограмма «TR» на плашке цвета акцента. Рисуется на лету — бинарных файлов в репозитории нет
function New-UiIcon ($Res, [int]$Size = 64) {
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $r = $Size * 0.22
    $dc.DrawRoundedRectangle($Res['Accent'], $null, (New-Object Windows.Rect 0, 0, $Size, $Size), $r, $r)
    $tf = New-Object Windows.Media.Typeface (New-Object Windows.Media.FontFamily 'Segoe UI'), 'Normal', 'Bold', 'Normal'
    $ft = New-Object Windows.Media.FormattedText 'TR', ([Globalization.CultureInfo]::InvariantCulture), 'LeftToRight', $tf, ($Size * 0.56), $Res['AccentFg']
    $g = $ft.BuildGeometry((New-Object Windows.Point 0, 0))
    $b = $g.Bounds
    $g.Transform = New-Object Windows.Media.TranslateTransform (($Size - $b.Width) / 2 - $b.X), (($Size - $b.Height) / 2 - $b.Y)
    $dc.DrawGeometry($Res['AccentFg'], $null, $g)
    $dc.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $Size, $Size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $frame = [Windows.Media.Imaging.BitmapFrame]::Create($bmp)
    $frame.Freeze()
    return $frame
}

# model.cs компилируется один раз: сборка лежит в %LOCALAPPDATA%\tabula-rasa\cache\model-<sha256 исходника>.dll
# (это своя сборка из исходника репозитория, не внешняя DLL). Исходник изменился — другое имя, старая не используется.
# Не вышло (нет прав на папку, сборка повреждена) — компиляция в память, как раньше
function Import-PbModel ([string]$Cache = (Join-Path $env:LOCALAPPDATA 'tabula-rasa\cache')) {
    $src = Join-Path $script:PbUiDir 'model.cs'
    $dll = $null
    try {
        $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.Substring(0, 16).ToLower()
        $dll = Join-Path $Cache "model-$hash-$($PSVersionTable.PSVersion.Major).dll"
        if (-not (Test-Path -LiteralPath $dll)) {
            New-Item -ItemType Directory -Path $Cache -Force | Out-Null
            Add-Type -Path $src -OutputAssembly $dll -OutputType Library -ErrorAction Stop
            # прежние версии сборки (уже загруженные другим окном удалятся в следующий раз)
            foreach ($old in (Get-ChildItem -LiteralPath $Cache -Filter 'model-*.dll' | Where-Object { $_.FullName -ne $dll })) { Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue }
        }
        if (-not ('PcBase.Item' -as [type])) { [void][Reflection.Assembly]::LoadFrom($dll) }
    } catch {
        if ($dll -and -not ('PcBase.Item' -as [type])) { Remove-Item -LiteralPath $dll -Force -ErrorAction SilentlyContinue }   # битая — собрать заново в следующий раз
    }
    if (-not ('PcBase.Item' -as [type])) { Add-Type -Path $src }
}

function Read-Xaml ([string]$Name) {
    $fs = [IO.File]::OpenRead((Join-Path $script:PbUiDir $Name))
    try { return [Windows.Markup.XamlReader]::Load($fs) } finally { $fs.Dispose() }
}

# один раз на процесс: модель, DPI, WPF, общие ресурсы. Возвращает тему.
function Initialize-Ui {
    if ($script:PbUiTheme) { return $script:PbUiTheme }
    if (-not ('PcBase.Item' -as [type])) { Import-PbModel }
    [PcBase.Native]::EnableDpiAwareness()
    [PcBase.Native]::SetAppId('iheeae.tabula-rasa')
    [AppContext]::SetSwitch('Switch.System.Windows.DoNotScaleForDpiChanges', $false)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    # Application нужен, чтобы стили видели и всплывающие меню/подсказки; Run() не зовём, окна — через ShowDialog
    $app = [Windows.Application]::Current
    if (-not $app) {
        $app = New-Object Windows.Application; $app.ShutdownMode = 'OnExplicitShutdown'
        # ошибка в обработчике окна (кнопка, таймер фоновой задачи) не роняет программу: запись в журнал, сообщение,
        # окно остаётся открытым. Без этого исключение закрывало окно раньше, чем его можно было прочитать
        $app.add_DispatcherUnhandledException({
            param($sender, $e)
            $e.Handled = $true
            Write-PbUiError $e.Exception
        })
    }
    $theme = Get-UiTheme
    $res = New-Object Windows.ResourceDictionary
    $res.MergedDictionaries.Add((Read-Xaml 'theme.xaml'))
    Set-UiPalette $res $theme
    $app.Resources = $res
    $theme.Icon = New-UiIcon $res
    $script:PbUiTheme = $theme
    return $theme
}

# ошибка окна: полный текст — в журнал выполнения и в logs\ui-error_<дата>.txt, коротко — системным сообщением
# (оно не зависит от состояния WPF и ждёт нажатия). Повтор одной и той же ошибки не показывается
function Write-PbUiError ($Exception) {
    $ex = $Exception
    while ($ex.InnerException -and ($ex -is [Management.Automation.MethodInvocationException] -or $ex -is [Reflection.TargetInvocationException])) { $ex = $ex.InnerException }
    $where = ''
    if ($ex -is [Management.Automation.RuntimeException] -and $ex.ErrorRecord) {
        $r = $ex.ErrorRecord
        $where = "$($r.InvocationInfo.PositionMessage)`r`n$($r.ScriptStackTrace)"
    }
    $text = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $($ex.GetType().FullName): $($ex.Message)`r`n$where`r`n$($Exception.ToString())`r`n"
    Write-Host "  ОШИБКА ОКНА: $($ex.Message)" -ForegroundColor Red
    Write-Host $where
    $file = $null
    try {
        New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null
        $file = Join-Path $script:PB.LogDir "ui-error_$($script:PB.Stamp).txt"
        [IO.File]::AppendAllText($file, $text + "`r`n", (New-Object Text.UTF8Encoding $false))
    } catch { }
    if (-not $script:PbUiErrors) { $script:PbUiErrors = @{} }
    $key = $ex.Message
    if ($script:PbUiErrors.ContainsKey($key)) { return }
    $script:PbUiErrors[$key] = $true
    if ($env:TR_SMOKE) { return }   # проверка окна в CI: без сообщений, ошибки читаются из файла
    try {
        [void][Windows.MessageBox]::Show("В окне Tabula Rasa произошла ошибка. Работа продолжается, но результат последнего действия может быть неполным.`n`n$($ex.Message)`n`nПодробности: $file",
            'Tabula Rasa: ошибка', 'OK', 'Warning')
    } catch { }
}

# ---------- проверка вида (tests\smoke.ps1 в CI): снимок окна и контраст всех видимых текстов ----------

# контраст по WCAG 2.1 между двумя цветами
function Get-UiContrast ($A, $B) {
    $l = { param($c) $f = { param($v) $x = $v / 255; if ($x -le 0.03928) { $x / 12.92 } else { [Math]::Pow(($x + 0.055) / 1.055, 2.4) } }
           0.2126 * (& $f $c.R) + 0.7152 * (& $f $c.G) + 0.0722 * (& $f $c.B) }
    $x = & $l $A; $y = & $l $B
    return ([Math]::Max($x, $y) + 0.05) / ([Math]::Min($x, $y) + 0.05)
}

# цвет $Top с прозрачностью $Alpha (0–1) поверх непрозрачного $Under
function Join-UiColor ($Top, [double]$Alpha, $Under) {
    [Windows.Media.Color]::FromRgb([byte]($Top.R * $Alpha + $Under.R * (1 - $Alpha)), [byte]($Top.G * $Alpha + $Under.G * (1 - $Alpha)), [byte]($Top.B * $Alpha + $Under.B * (1 - $Alpha)))
}

# фон под элементом: кисти Border / Panel / Control вверх по дереву, полупрозрачные смешиваются; $Fallback — фон окна
function Get-UiBackColor ($El, $Fallback) {
    $layers = New-Object System.Collections.ArrayList
    $p = [Windows.Media.VisualTreeHelper]::GetParent($El)
    while ($p) {
        $b = $null
        if ($p -is [Windows.Controls.Border]) { $b = $p.Background }
        elseif ($p -is [Windows.Controls.Panel]) { $b = $p.Background }
        if ($b -is [Windows.Media.SolidColorBrush] -and $b.Color.A -gt 0) {
            [void]$layers.Add(@{ C = $b.Color; A = ($b.Color.A / 255.0) * $b.Opacity })
            if ($b.Color.A -eq 255 -and $b.Opacity -ge 1) { break }
        }
        $p = [Windows.Media.VisualTreeHelper]::GetParent($p)
    }
    $c = $Fallback
    for ($i = $layers.Count - 1; $i -ge 0; $i--) { $c = Join-UiColor $layers[$i].C $layers[$i].A $c }
    return $c
}

# тексты с недостаточным контрастом: обычный текст — 4,5:1, крупный (от 24 px или от 18,7 px полужирный) и значки — 3:1.
# Отключённые элементы не проверяются (WCAG их не требует)
function Find-UiContrastIssues ($Root, $Fallback) {
    $out = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count) {
        $v = $stack.Pop()
        $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($v)
        for ($i = 0; $i -lt $n; $i++) { $stack.Push([Windows.Media.VisualTreeHelper]::GetChild($v, $i)) }
        if ($v -isnot [Windows.Controls.TextBlock]) { continue }
        if (-not $v.IsVisible -or -not $v.IsEnabled -or $v.ActualWidth -lt 1 -or -not $v.Text) { continue }
        $fgb = $v.Foreground
        if ($fgb -isnot [Windows.Media.SolidColorBrush]) { continue }
        $bg = Get-UiBackColor $v $Fallback
        $op = 1.0; $q = $v
        while ($q) { if ($q -is [Windows.UIElement]) { $op *= $q.Opacity }; $q = [Windows.Media.VisualTreeHelper]::GetParent($q) }
        $fg = Join-UiColor $fgb.Color (($fgb.Color.A / 255.0) * $fgb.Opacity * $op) $bg
        $ratio = Get-UiContrast $fg $bg
        $icon = [string]$v.FontFamily -match 'Icons|MDL2'
        $large = $v.FontSize -ge 24 -or ($v.FontSize -ge 18.6 -and $v.FontWeight.ToOpenTypeWeight() -ge 600)
        $need = if ($icon -or $large) { 3.0 } else { 4.5 }
        if ($ratio -lt $need) {
            $t = ([string]$v.Text -replace '\s+', ' '); if ($t.Length -gt 50) { $t = $t.Substring(0, 50) + '…' }
            [void]$out.Add(("{0:N2}:1 (нужно {1}) текст {2} на фоне {3}: «{4}»" -f $ratio, $need, $fg, $bg, $t))
        }
    }
    return @($out | Select-Object -Unique)
}

# снимок элемента в PNG; фон окна подкладывается снизу (он бывает прозрачным)
function Save-UiShot ($El, $Back, [string]$Path) {
    $w = [int][Math]::Ceiling($El.ActualWidth); $h = [int][Math]::Ceiling($El.ActualHeight)
    if ($w -lt 1 -or $h -lt 1) { return }
    $rect = New-Object Windows.Rect 0, 0, $w, $h
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.DrawRectangle((New-Object Windows.Media.SolidColorBrush $Back), $null, $rect)
    $dc.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $bmp.Render($El)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($Path)
    try { $enc.Save($fs) } finally { $fs.Dispose() }
}

function New-UiWindow ([string]$Xaml, $Theme) {
    $w = Read-Xaml $Xaml
    $w.Icon = $Theme.Icon
    $dark = [bool]$Theme.Dark
    $w.add_SourceInitialized({ param($s) [PcBase.Native]::SetDarkTitleBar((New-Object Windows.Interop.WindowInteropHelper $s).Handle, $dark) }.GetNewClosure())
    return $w
}

# сообщение / подтверждение в стиле окна. $Lines — строки или @{ Text; Tone = 'danger'|'muted'|'strong' }.
# Возвращает $true, если нажата главная кнопка. С -WithInput — поле ввода, возвращает введённое или $null.
function Show-UiMessage {
    param($Owner, [string]$Title, $Lines, [string]$Primary = 'ОК', [string]$Secondary, [switch]$SafeDefault,
        [switch]$WithInput, [string]$InputValue)
    $theme = Initialize-Ui
    $d = New-UiWindow 'dialog.xaml' $theme
    if ($Owner) { $d.Owner = $Owner } else { $d.WindowStartupLocation = 'CenterScreen' }
    $d.FindName('Head').Text = $Title
    $body = $d.FindName('Body')
    foreach ($l in @($Lines)) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,4,0,0'; $tb.LineHeight = 20
        if ($l -is [hashtable]) {
            $tb.Text = $l.Text
            switch ($l.Tone) {
                'danger' { $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Danger') }
                'muted'  { $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextMuted') }
                'strong' { $tb.FontWeight = 'SemiBold' }
            }
            if ($l.Gap) { $tb.Margin = '0,16,0,0' }
        } else { $tb.Text = [string]$l }
        [void]$body.Children.Add($tb)
    }
    $bp = $d.FindName('Primary'); $bs = $d.FindName('Secondary')
    $bp.Content = $Primary
    $bp.add_Click({ $d.DialogResult = $true })
    if ($Secondary) { $bs.Content = $Secondary; $bs.IsCancel = $true } else { $bs.Visibility = 'Collapsed'; $bp.IsCancel = $true }
    $box = $d.FindName('Input')
    if ($WithInput) {
        $box.Visibility = 'Visible'; $box.Text = $InputValue; $bp.IsDefault = $true
        $d.add_ContentRendered({ [void]$box.Focus(); $box.SelectAll() })
        if (-not $d.ShowDialog()) { return $null }
        return $box.Text
    }
    $d.add_ContentRendered({ if ($SafeDefault -and $Secondary) { [void]$bs.Focus() } else { [void]$bp.Focus() } })
    return [bool]$d.ShowDialog()
}

# пароль (Э9, временный автоматический вход): SecureString или $null (отмена, пусто). Пароль не попадает в строки
function Read-UiPassword {
    param($Owner, [string]$Title, $Lines)
    $theme = Initialize-Ui
    $d = New-UiWindow 'dialog.xaml' $theme
    if ($Owner) { $d.Owner = $Owner } else { $d.WindowStartupLocation = 'CenterScreen' }
    $d.FindName('Head').Text = $Title
    $body = $d.FindName('Body')
    foreach ($l in @($Lines)) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,4,0,0'; $tb.LineHeight = 20; $tb.Text = [string]$l
        [void]$body.Children.Add($tb)
    }
    $box = New-Object Windows.Controls.PasswordBox
    $box.Margin = '0,16,0,0'
    [Windows.Automation.AutomationProperties]::SetName($box, 'Пароль')
    [void]$body.Children.Add($box)
    $bp = $d.FindName('Primary'); $bs = $d.FindName('Secondary')
    $bp.Content = 'Продолжить'; $bp.IsDefault = $true
    $bp.add_Click({ $d.DialogResult = $true })
    $bs.Content = 'Отмена'; $bs.IsCancel = $true
    $d.add_ContentRendered({ [void]$box.Focus() })
    $ok = [bool]$d.ShowDialog()
    $sec = if ($ok -and $box.SecurePassword.Length) { $box.SecurePassword } else { $null }   # SecurePassword — копия
    $box.Clear()
    return $sec
}

# обратный отсчёт (Э9, перезагрузка для продолжения): $true — время вышло или нажата главная кнопка, $false — отменено
function Show-UiCountdown {
    param($Owner, [string]$Title, $Lines, [int]$Seconds = 60, [string]$Primary = 'Сейчас', [string]$Secondary = 'Отменить',
        [string]$Format = 'Осталось {0} с')
    $theme = Initialize-Ui
    $d = New-UiWindow 'dialog.xaml' $theme
    if ($Owner) { $d.Owner = $Owner } else { $d.WindowStartupLocation = 'CenterScreen' }
    $d.FindName('Head').Text = $Title
    $body = $d.FindName('Body')
    foreach ($l in @($Lines)) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,4,0,0'; $tb.LineHeight = 20
        if ($l -is [hashtable]) { $tb.Text = $l.Text; if ($l.Tone -eq 'muted') { $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextMuted') } }
        else { $tb.Text = [string]$l }
        [void]$body.Children.Add($tb)
    }
    $count = New-Object Windows.Controls.TextBlock
    $count.Margin = '0,16,0,0'; $count.FontWeight = 'SemiBold'; $count.FontSize = 20
    $count.Text = $Format -f $Seconds
    [void]$body.Children.Add($count)
    $bp = $d.FindName('Primary'); $bs = $d.FindName('Secondary')
    $bp.Content = $Primary; $bp.add_Click({ $d.DialogResult = $true })
    $bs.Content = $Secondary; $bs.IsCancel = $true
    $st = @{ Left = $Seconds }
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(1)
    $t.add_Tick({
        $st.Left--
        $count.Text = $Format -f [Math]::Max(0, $st.Left)
        if ($st.Left -le 0) { $t.Stop(); $d.DialogResult = $true }
    })
    # по умолчанию — «Отменить»: случайный Enter не перезагружает компьютер раньше времени
    $d.add_ContentRendered({ [void]$bs.Focus(); $t.Start() })
    $r = [bool]$d.ShowDialog()
    $t.Stop()
    return $r
}

function Get-Plural ([int]$N, [string]$One, [string]$Few, [string]$Many) {
    $m10 = $N % 10; $m100 = $N % 100
    if ($m10 -eq 1 -and $m100 -ne 11) { return $One }
    if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return $Few }
    return $Many
}

function New-Fact ([string]$Label, [string]$Value, [string]$Tone = '') {
    $f = New-Object PcBase.Fact
    $f.Label = $Label; $f.Value = $Value; $f.Tone = $Tone
    return $f
}

# значки категорий слева (Segoe Fluent Icons / MDL2); неизвестная категория — общий значок
$script:PbCatIcons = @{
    'Основа' = [char]0xE80F; 'Повседневное' = [char]0xE8F1; 'Разработка' = [char]0xE943; 'Сеть и ИБ' = [char]0xE968; 'Система' = [char]0xE770
    'Игры' = [char]0xE7FC; 'Мой каталог' = [char]0xE734; 'Приватность' = [char]0xE72E; 'Проводник' = [char]0xE8B7; 'Панель задач' = [char]0xE7C4
    'Пуск' = [char]0xE8FC; 'Мусор' = [char]0xE74D; 'Среда' = [char]0xE756; 'Мои файлы' = [char]0xE8B7
}
function Get-CatIcon ([string]$Name) { if ($script:PbCatIcons.ContainsKey($Name)) { [string]$script:PbCatIcons[$Name] } else { [string][char]0xE9CE } }

# спокойная палитра плиток-монограмм: цвет выбирается по Id и от запуска к запуску не меняется
# плитки-монограммы: насыщенные тона, белая буква — не ниже 5:1 (было 3,9:1 на светлых)
$script:PbMonoColors = @('#4F46E5', '#7C3AED', '#B4237A', '#C2410C', '#B45309', '#4D7C0F', '#047857', '#0F766E', '#0E7490', '#1D4ED8', '#6D28D9', '#BE123C', '#57534E', '#475569')
function Get-MonoBrush ([string]$Id) {
    $h = 0; foreach ($c in $Id.ToCharArray()) { $h = ($h * 31 + [int]$c) % 1000003 }
    $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($script:PbMonoColors[$h % $script:PbMonoColors.Count]))
    $b.Freeze(); return $b.PSObject.BaseObject
}

# значок установленной программы из её exe (путь — DisplayIcon в реестре Uninstall); не вышло — $null, остаётся монограмма
function Get-ExeIcon ([string]$Path) {
    try {
        $p = ($Path -replace ',\s*-?\d+$', '').Trim('"', ' ')
        if (-not $p -or -not (Test-Path -LiteralPath $p) -or $p -notmatch '\.(exe|ico|dll)$') { return $null }
        Add-Type -AssemblyName System.Drawing
        $ico = [Drawing.Icon]::ExtractAssociatedIcon($p)
        if (-not $ico) { return $null }
        $src = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ico.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        $src.Freeze(); $ico.Dispose()
        return $src
    } catch { return $null }
}

# программа каталога (встроенного или собственного) → пункт окна
function New-AppItem ($A, [string]$CatKey, [string]$Cat) {
    $it = New-Object PcBase.Item
    $it.Key = 'app:' + $A.Id; $it.Kind = 'app'; $it.Id = $A.Id; $it.Name = $A.Name
    $it.Desc = $A.Desc; $it.FullDesc = $A.Desc
    $it.CatKey = $CatKey; $it.CatName = "Программы · $Cat"; $it.GroupTitle = $it.CatName
    $it.Interactive = [bool]$A.Interactive; $it.IsWeb = $A.Source -eq 'web'; $it.CanRemove = $A.Source -eq 'winget'; $it.OpenSource = [bool]$A.OpenSource; $it.IsMine = [bool]$A.Mine
    $it.HasTile = $true; $it.Monogram = ([string]$A.Name).Substring(0, 1).ToUpper(); $it.MonoBrush = Get-MonoBrush $A.Id
    if ($A.Config -and $A.Config.Import) {
        $it.HasConfig = $true; $it.ConfigName = 'с моими настройками'; $it.ConfigFile = $A.Config.File
        $it.ConfigDesc = "Переносится: $($A.Config.Desc)$(if ($A.Config.Skip) { " Не переносится: $($A.Config.Skip)" })"
    }
    $it.SearchText = @($A.Name, $A.Desc, $A.Id, $A.WingetId, $Cat, $A.Note, $(if ($A.OpenSource) { 'open source' }), $(if ($A.Mine) { 'мой каталог' })) -join "`n"
    if ($A.Source -eq 'web') {
        $it.Facts.Add((New-Fact 'Источник' 'Официальный сайт: актуальная версия, запускается только с действительной подписью издателя'))
        $it.Facts.Add((New-Fact 'Страница загрузки' $A.PageUrl 'mono'))
    } else { $it.Facts.Add((New-Fact 'Источник' "winget: $($A.WingetId)" 'mono')) }
    if ($A.Mine) { $it.Facts.Add((New-Fact 'Каталог' 'Собственный каталог в «Моих данных» (catalog\apps.psd1)')) }
    if ($A.Note) { $it.Facts.Add((New-Fact 'Примечание' $A.Note)) }
    if ($A.Interactive) { $it.Facts.Add((New-Fact 'Установка' 'Тихая установка невозможна: откроется мастер установки.')) }
    if ($A.License) { $it.Facts.Add((New-Fact 'Лицензия' $A.License)) }
    if ($A.Manual) { $it.Facts.Add((New-Fact 'Вручную после установки' $A.Manual)) }
    return $it
}

# файл из релиза files (Get-PbFiles): имя — подпись, id — имя ассета
function New-FileItem ($File, [string]$CatKey, [string]$Group) {
    $it = New-Object PcBase.Item
    $it.Key = 'file:' + $File.Name; $it.Kind = 'file'; $it.Id = $File.Name; $it.Name = $File.Title
    $sz = Format-PbSize $File.Size
    $dt = if ($File.Updated) { $File.Updated.ToLocalTime().ToString('dd.MM.yyyy') } else { '' }
    $it.Desc = $sz + $(if ($dt) { " · загружен $dt" })
    $it.FullDesc = 'Файл будет загружен в папку «Рабочий стол\tabula-rasa-files» и проверен по контрольной сумме SHA-256. Установка не выполняется: файл запускается вручную.'
    $it.CatKey = $CatKey; $it.CatName = $Group; $it.GroupTitle = $Group
    $it.SearchText = @($File.Title, $File.Name, 'файлы') -join "`n"
    $it.Facts.Add((New-Fact 'Размер' $sz))
    if ($dt) { $it.Facts.Add((New-Fact 'Загружен в релиз' $dt)) }
    $it.Facts.Add((New-Fact 'Имя в релизе' $File.Name 'mono'))
    if ($File.Sha256) { $it.Facts.Add((New-Fact 'SHA-256' $File.Sha256 'mono')) }
    else { $it.Facts.Add((New-Fact 'SHA-256' 'GitHub не указал контрольную сумму этого файла, поэтому сверка после загрузки не выполняется.' 'danger')) }
    $it.Facts.Add((New-Fact 'Действие' 'Только загрузка, без установки'))
    return $it
}

# ---------- «Добавить программу»: поиск в winget (в фоне) → выбор → @{ Name; WingetId; Desc; Category } или $null ----------

function Show-AddAppDialog {
    param($Owner, [hashtable]$Known, [string[]]$Categories)
    $theme = Initialize-Ui
    $d = New-UiWindow 'addapp.xaml' $theme
    if ($Owner) { $d.Owner = $Owner }
    $c = @{}
    foreach ($n in 'Query', 'Find', 'Status', 'Results', 'Pick', 'PickName', 'PickId', 'PickInfo', 'PickDesc', 'PickCat', 'PickCats', 'Add', 'Cancel') { $c[$n] = $d.FindName($n) }
    $rows = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $c.Results.ItemsSource = $rows
    $st = @{ Job = $null; Kind = $null; ShowId = $null; Info = @{}; Result = $null }
    $c.PickCats.Text = "Существующие: $((@($Categories) + $script:PbUserCategory | Select-Object -Unique) -join ', ')."
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)

    # фоновая задача: search (строка запроса) или show (winget id)
    function Start-Job2 ([string]$Kind, [string]$Arg) {
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root, $Kind, $Arg)
            . (Join-Path $Root 'lib\common.ps1'); . (Join-Path $Root 'lib\data.ps1'); . (Join-Path $Root 'lib\catalog.ps1')
            Update-PbPath
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget не найден. Установите App Installer из Microsoft Store или запустите Tabula Rasa через загрузчик.' }
            if ($Kind -eq 'search') { Search-PbWinget $Arg } else { Get-PbWingetShow $Arg }
        })
        foreach ($a in @($script:PB.Root, $Kind, $Arg)) { [void]$ps.AddArgument($a) }
        $st.Job = @{ Ps = $ps; Handle = $ps.BeginInvoke(); Kind = $Kind; Arg = $Arg }
        $timer.Start()
    }

    function Start-Search {
        $q = $c.Query.Text.Trim()
        if (-not $q -or $st.Job) { return }
        $rows.Clear(); $c.Pick.Visibility = 'Collapsed'; $c.Add.IsEnabled = $false
        $c.Status.Text = "Поиск «$q» в winget…"; $c.Find.IsEnabled = $false
        Start-Job2 'search' $q
    }

    function Update-PickInfo {
        $it = $c.Results.SelectedItem
        if (-not $it) { return }
        $parts = @()
        if ($it.Key) { $parts += "Версия $($it.Key)" }
        $inf = $st.Info[$it.Id]
        if ($inf) {
            if ($inf.Publisher) { $parts += "Издатель: $($inf.Publisher)" }
            if ($inf.License) { $parts += "Лицензия: $($inf.License)" }
            if ($inf.Homepage) { $parts += $inf.Homepage }
            if (-not $c.PickDesc.Text -and $inf.Description) { $t = $inf.Description; if ($t.Length -gt 300) { $t = $t.Substring(0, 300).TrimEnd() + '…' }; $c.PickDesc.Text = $t }
        } elseif ($st.Job -and $st.Job.Kind -eq 'show') { $parts += 'Загрузка сведений…' }
        else { $parts += "Издатель: $(($it.Id -split '\.')[0])" }
        if ($it.IsChecked) { $parts += "Уже в каталоге: «$($Known[$it.Id.ToLower()])»" }
        $c.PickInfo.Text = $parts -join "`n"
    }

    $timer.add_Tick({
        $j = $st.Job
        if (-not $j -or -not $j.Handle.IsCompleted) { return }
        $timer.Stop()
        $res = $null; $err = $null
        try { $res = @($j.Ps.EndInvoke($j.Handle) | ForEach-Object { $_.PSObject.BaseObject }) }
        catch { $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        $j.Ps.Dispose(); $st.Job = $null
        if ($j.Kind -eq 'search') {
            $c.Find.IsEnabled = $true
            if ($err) { $c.Status.Text = "Поиск не выполнен: $err" }
            else {
                foreach ($r in $res) {
                    $it = New-Object PcBase.Item
                    $it.Kind = 'found'; $it.Id = $r.Id; $it.Name = $r.Name; $it.Key = $r.Version
                    $it.IsChecked = $Known.ContainsKey($r.Id.ToLower())   # уже в каталоге
                    $it.Desc = "$($r.Id)$(if ($r.Version) { " · $($r.Version)" })$(if ($it.IsChecked) { ' · уже в каталоге' })"
                    $rows.Add($it)
                }
                $c.Status.Text = if ($rows.Count) { "Найдено: $($rows.Count). Выберите программу." } else { 'Ничего не найдено. Название вводится на английском, например notepad plus, 7zip, obs.' }
            }
        } else {
            if (-not $err -and $res) { $st.Info[$j.Arg] = $res[-1] } else { $st.Info[$j.Arg] = @{} }
            Update-PickInfo
        }
        # выбор сменился, пока шла задача, — сведения о новой программе
        $sel = $c.Results.SelectedItem
        if (-not $st.Job -and $sel -and -not $st.Info.ContainsKey($sel.Id)) { Start-Job2 'show' $sel.Id }
    })

    $c.Find.add_Click({ Start-Search })
    $c.Results.add_SelectionChanged({
        $it = $c.Results.SelectedItem
        if (-not $it) { $c.Pick.Visibility = 'Collapsed'; $c.Add.IsEnabled = $false; return }
        $c.Pick.Visibility = 'Visible'
        $c.PickName.Text = $it.Name; $c.PickId.Text = $it.Id
        $c.PickDesc.Text = ''
        if (-not $c.PickCat.Text) { $c.PickCat.Text = $script:PbUserCategory }
        $c.Add.IsEnabled = -not $it.IsChecked
        if (-not $st.Job -and -not $st.Info.ContainsKey($it.Id)) { Start-Job2 'show' $it.Id }
        Update-PickInfo
    })
    $c.Add.add_Click({
        $it = $c.Results.SelectedItem
        if (-not $it -or $it.IsChecked) { return }
        $st.Result = @{ Name = $it.Name; WingetId = $it.Id; Desc = $c.PickDesc.Text.Trim(); Category = $c.PickCat.Text.Trim() }
        $d.DialogResult = $true
    })
    # Enter в поле поиска — «Найти», а не «Добавить»
    $c.Query.add_GotFocus({ $c.Find.IsDefault = $true })
    $d.add_ContentRendered({ [void]$c.Query.Focus() })
    $d.add_Closed({ $timer.Stop(); if ($st.Job) { try { [void]$st.Job.Ps.BeginStop($null, $null) } catch { } } })
    if (-not $d.ShowDialog()) { return $null }
    return $st.Result
}

# ---------- анимации, фон окна, запоминание окна ----------

# смена категории: появление и сдвиг на 8 px за 180 мс; выключено, если в Windows отключены анимации, и в проверке
# окна (tests\smoke.ps1): снимок посреди появления — полупрозрачный текст и ложные замечания по контрасту
function Invoke-UiFade ($El) {
    if ($env:TR_SMOKE -or -not [Windows.SystemParameters]::ClientAreaAnimation) { return }
    $d = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(180))
    $ease = New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
    $op = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, $d
    $tt = New-Object Windows.Media.TranslateTransform
    $El.RenderTransform = $tt
    $mv = New-Object Windows.Media.Animation.DoubleAnimation 8, 0, $d
    $mv.EasingFunction = $ease
    $El.BeginAnimation([Windows.UIElement]::OpacityProperty, $op)
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $mv)
}

# размер, положение, развёрнутость, последний раздел: %LOCALAPPDATA%\tabula-rasa\ui.json
function Get-UiStatePath { Join-Path $env:LOCALAPPDATA 'tabula-rasa\ui.json' }
function Read-UiState {
    $p = Get-UiStatePath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return (Get-Content $p -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}
function Save-UiState ($Win, [string]$Nav) {
    try {
        $b = if ($Win.WindowState -eq 'Normal') { New-Object Windows.Rect $Win.Left, $Win.Top, $Win.ActualWidth, $Win.ActualHeight } else { $Win.RestoreBounds }
        $j = [ordered]@{ Left = [int]$b.Left; Top = [int]$b.Top; Width = [int]$b.Width; Height = [int]$b.Height; Max = $Win.WindowState -eq 'Maximized'; Nav = $Nav
                         Theme = $(if ($script:PbThemePref) { $script:PbThemePref } else { 'auto' }) }
        New-Item -ItemType Directory -Path (Split-Path (Get-UiStatePath)) -Force | Out-Null
        [IO.File]::WriteAllText((Get-UiStatePath), ($j | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
    } catch { }
}
# применить, только если окно целиком помещается на рабочих столах (монитор могли отключить)
function Restore-UiState ($Win, $State) {
    if (-not $State -or $State.Width -lt $Win.MinWidth -or $State.Height -lt $Win.MinHeight) { return }
    $v = New-Object Windows.Rect ([Windows.SystemParameters]::VirtualScreenLeft), ([Windows.SystemParameters]::VirtualScreenTop),
        ([Windows.SystemParameters]::VirtualScreenWidth), ([Windows.SystemParameters]::VirtualScreenHeight)
    $r = New-Object Windows.Rect $State.Left, $State.Top, $State.Width, $State.Height
    if (-not $v.Contains($r)) { return }
    $Win.WindowStartupLocation = 'Manual'
    $Win.Left = $State.Left; $Win.Top = $State.Top; $Win.Width = $State.Width; $Win.Height = $State.Height
    if ($State.Max) { $Win.WindowState = 'Maximized' }
}

# ---------- «Удалить Tabula Rasa с этого компьютера» (lib\selfremove.ps1) ----------
# Два подтверждения: список того, что удалится (с отметками), затем «Удалить безвозвратно?» с «Отмена» по умолчанию.
# $true — удаление запущено, окно нужно закрыть
function Show-SelfRemoveDialog ($Owner) {
    $theme = Initialize-Ui
    $d = New-UiWindow 'dialog.xaml' $theme
    $d.Owner = $Owner; $d.Width = 600
    $d.FindName('Head').Text = 'Удалить Tabula Rasa с этого компьютера'
    $body = $d.FindName('Body'); $bp = $d.FindName('Primary'); $bs = $d.FindName('Secondary')
    $intro = New-Object Windows.Controls.TextBlock
    $intro.TextWrapping = 'Wrap'; $intro.Margin = '0,4,0,12'; $intro.LineHeight = 20
    $intro.Text = 'Программа удалится вместе с отмеченными данными. Всё, что она сделала, останется: установленные программы, применённые настройки Windows и программ.'
    [void]$body.Children.Add($intro)
    $boxes = @{}
    foreach ($p in @(Get-PbSelfRemoveParts)) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.IsChecked = $true; $cb.IsEnabled = -not $p.Fixed; $cb.Margin = '0,8,0,0'
        $sp = New-Object Windows.Controls.StackPanel
        $t1 = New-Object Windows.Controls.TextBlock; $t1.Text = $p.Name; $t1.FontWeight = 'SemiBold'; [void]$sp.Children.Add($t1)
        $t2 = New-Object Windows.Controls.TextBlock; $t2.Text = $p.Desc; $t2.TextWrapping = 'Wrap'; $t2.Margin = '0,2,0,0'
        $t2.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextMuted'); [void]$sp.Children.Add($t2)
        if (@($p.Paths).Count) {
            $t3 = New-Object Windows.Controls.TextBlock; $t3.Text = (@($p.Paths) -join "`n"); $t3.TextWrapping = 'Wrap'; $t3.FontFamily = 'Consolas'; $t3.FontSize = 11
            $t3.Margin = '0,2,0,0'; $t3.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextMuted'); [void]$sp.Children.Add($t3)
        }
        $cb.Content = $sp
        [void]$body.Children.Add($cb)
        $boxes[$p.Key] = $cb
    }
    $bp.Content = 'Далее…'; $bs.Content = 'Отмена'; $bs.IsCancel = $true
    $bp.add_Click({ $d.DialogResult = $true })
    $d.add_ContentRendered({ [void]$bs.Focus() })
    if (-not $d.ShowDialog()) { return $false }
    $keys = @($boxes.Keys | Where-Object { $boxes[$_].IsChecked })
    $names = @(Get-PbSelfRemoveParts | Where-Object { $keys -contains $_.Key } | ForEach-Object { "• $($_.Name)" })
    $ok = Show-UiMessage -Owner $Owner -Title 'Удалить Tabula Rasa безвозвратно?' -Primary 'Удалить' -Secondary 'Отмена' -SafeDefault -Lines @(
        'Будет удалено:', ($names -join "`n"),
        @{ Text = 'Окно закроется. Удаление завершится через несколько секунд, по окончании появится сообщение. Вернуть удалённое можно только новой установкой Tabula Rasa.'; Tone = 'muted'; Gap = $true })
    if (-not $ok) { return $false }
    try { [void](Start-PbSelfRemove $keys) }
    catch { [void](Show-UiMessage -Owner $Owner -Title 'Не удалось начать удаление' -Lines @(@{ Text = $_.Exception.Message; Tone = 'danger' })); return $false }
    return $true
}

# ---------- «Откат изменений»: журналы изменений → Invoke-PbUndo (lib\run.ps1) в фоне ----------

function Show-UndoDialog ($Owner) {
    $theme = Initialize-Ui
    $d = New-UiWindow 'dialog.xaml' $theme
    $d.Owner = $Owner; $d.Width = 560
    $d.FindName('Head').Text = 'Откат изменений'
    $body = $d.FindName('Body'); $bp = $d.FindName('Primary'); $bs = $d.FindName('Secondary')
    $logs = @(Get-PbChangeLogs)
    $tb = New-Object Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,4,0,8'
    $tb.Text = if ($logs.Count) { 'Выберите журнал изменений. Изменения реестра, служб, задач и PATH из него будут отменены в обратном порядке.' } else { 'Журналов изменений нет: прогонов с изменениями на этом компьютере не было.' }
    [void]$body.Children.Add($tb)
    $list = New-Object Windows.Controls.ListBox
    $list.MaxHeight = 260; $list.Margin = '0,0,0,8'
    foreach ($l in $logs) {
        $li = New-Object Windows.Controls.ListBoxItem
        $li.Content = "$($l.Date.ToString('dd.MM.yyyy HH:mm'))   ·   изменений: $($l.Count)"; $li.Tag = $l.Path; $li.Padding = '8,6'
        [void]$list.Items.Add($li)
    }
    if ($logs.Count) { $list.SelectedIndex = 0; [void]$body.Children.Add($list) }
    $note = New-Object Windows.Controls.TextBlock
    $note.TextWrapping = 'Wrap'; $note.Text = $script:PbUndoLimits; $note.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextMuted')
    [void]$body.Children.Add($note)
    $bp.Content = 'Откатить'; $bp.IsEnabled = [bool]$logs.Count
    $bs.Content = 'Закрыть'; $bs.IsCancel = $true
    $state = @{ Job = $null }
    $timer = New-Object Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.add_Tick({
        $j = $state.Job
        if (-not $j.Handle.IsCompleted) { return }
        $timer.Stop()
        $res = @(); try { $res = @($j.Ps.EndInvoke($j.Handle) | ForEach-Object { $_.PSObject.BaseObject }) } catch { $res = @(@{ Ok = $false; Text = $_.Exception.Message }) }
        $j.Ps.Dispose()
        $ok = @($res | Where-Object { $_.Ok }).Count; $bad = @($res | Where-Object { -not $_.Ok })
        $body.Children.Clear()
        $t = New-Object Windows.Controls.TextBlock; $t.TextWrapping = 'Wrap'
        $t.Text = "Отменено изменений: $ok.$(if ($bad.Count) { " Не удалось: $($bad.Count)." }) Проводник и панель задач применят изменения после повторного входа или перезагрузки."
        [void]$body.Children.Add($t)
        foreach ($b in @($bad | Select-Object -First 8)) {
            $e = New-Object Windows.Controls.TextBlock; $e.TextWrapping = 'Wrap'; $e.Margin = '0,4,0,0'; $e.Text = "• $($b.Text)"
            $e.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Danger'); [void]$body.Children.Add($e)
        }
        $bp.Visibility = 'Collapsed'; $bs.IsEnabled = $true
    })
    $bp.add_Click({
        $file = [string]$list.SelectedItem.Tag
        if (-not $file) { return }
        if (-not (Show-UiMessage -Owner $d -Title 'Откатить изменения?' -Primary 'Откатить' -Secondary 'Назад' -SafeDefault -Lines @("Журнал: $file", @{ Text = $script:PbUndoLimits; Tone = 'muted' }))) { return }
        $bp.IsEnabled = $false; $bs.IsEnabled = $false; $list.IsEnabled = $false; $tb.Text = 'Откат выполняется…'
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({ param($Root, $File) . (Join-Path $Root 'lib\common.ps1'); . (Join-Path $Root 'lib\run.ps1'); Invoke-PbUndo $File })
        [void]$ps.AddArgument($script:PB.Root); [void]$ps.AddArgument($file)
        $state.Job = @{ Ps = $ps; Handle = $ps.BeginInvoke() }
        $timer.Start()
    })
    $d.add_Closing({ param($s, $e) if ($state.Job -and -not $state.Job.Handle.IsCompleted) { $e.Cancel = $true } })
    [void]$d.ShowDialog()
}

# ---------- главное окно ----------

function Show-SelectionDialog {
    param(
        $Apps, $Tweaks,
        [hashtable]$Initial,         # сохранение, с которым открыть окно (Read-SaveFile)
        [string[]]$Notices,          # что сказать при открытии (переезд папок и т. п.)
        [bool]$IsDomain = $false,
        [bool]$RunInWindow = $true,  # план, прогон и итог — в окне (по умолчанию); $false — вернуть выбор, прогон в консоли (-Console)
        [string]$Title = 'Tabula Rasa',
        $Resume                      # Э9: незавершённый прогон (Read-PbResume) — окно сразу продолжает его на экране прогона
    )

    $theme = Initialize-Ui
    $win = New-UiWindow 'main.xaml' $theme
    $ctl = @{}
    foreach ($n in 'TabInstall', 'TabCapture', 'InstallPane', 'InstallBar', 'CapturePane', 'CaptureHint', 'CaptureList', 'CaptureCard', 'CaptureCardIcon',
        'CaptureCardTitle', 'CaptureCardText', 'CaptureCardBtn', 'CaptureDetail', 'CaptureDetailHint', 'CaptureSummary', 'CaptureBtn',
        'SearchBox', 'AddAppBtn', 'RemoveMine', 'Logo', 'HostChips', 'Search', 'SearchKey', 'SearchClear', 'SetBtn', 'SetBtnText', 'Nav', 'NavBottom', 'ListTitle', 'ListHint', 'CatButtons', 'CatCheck',
        'HeadLeft', 'MoreBtn', 'ThemeBtn', 'ThemeGlyph', 'TabSwitch', 'AddAppText', 'FilterBar', 'FilterMissing', 'FilterUpdates', 'MarkUpdates', 'StatusScan', 'InstallPane',
        'RunPane', 'RunTitle', 'RunHint', 'RunProgress', 'RunBanner', 'RunBannerText', 'RunList', 'ManualBox', 'ManualList', 'LogToggle', 'RunLog',
        'RunBack', 'RunSkip', 'RunStop', 'RunRetry', 'RunOpenLog', 'RunOpenReport', 'RunMore', 'RunSideCol', 'RunSide', 'RunReboot', 'RunApply', 'RunClose', 'RunStatus',
        'List', 'ListEmpty', 'DetailHint', 'Detail', 'PcNameLabel', 'PcName', 'PcNameFixed', 'PcNameCur', 'Summary', 'SaveBtn', 'OkBtn',
        'Notice', 'NoticeIcon', 'NoticeText', 'NoticeClose', 'DataIcon', 'DataStatus', 'DataBtn', 'DataLogin', 'DataCode', 'DataOpen',
        'FilesCard', 'FilesCardIcon', 'FilesCardTitle', 'FilesCardText', 'FilesCardBtn') {
        $ctl[$n] = $win.FindName($n)
    }
    # 1200×800, но не больше рабочей области (1080p на 150 % — это 1280×~700)
    $wa = [Windows.SystemParameters]::WorkArea
    $win.Width = [Math]::Max($win.MinWidth, [Math]::Min(1200, $wa.Width - 48))
    $win.Height = [Math]::Max($win.MinHeight, [Math]::Min(800, $wa.Height - 48))
    $win.Title = $Title
    $ctl.Logo.Source = $theme.Icon
    # чипы шапки: при нехватке места «в домене» → значок с подсказкой, затем ОС → в подсказку к имени, затем имя — с многоточием
    function New-Chip ([string]$Text, [string]$Tip, [string]$Icon, [double]$Max = [double]::PositiveInfinity) {
        $c = New-Object PcBase.Chip; $c.Text = $Text; $c.Tip = $Tip; $c.Icon = $Icon; $c.MaxWidth = $Max; return $c
    }
    function Measure-UiText ([string]$T) {
        $ft = New-Object Windows.Media.FormattedText $T, ([Globalization.CultureInfo]::CurrentUICulture), 'LeftToRight',
            (New-Object Windows.Media.Typeface $win.FontFamily, 'Normal', 'Normal', 'Normal'), 14, ([Windows.Media.Brushes]::Black)
        return $ft.WidthIncludingTrailingWhitespace
    }
    $os = "Windows $($script:PB.Os)"
    function Update-HostChips {
        $avail = $ctl.HeadLeft.ActualWidth - 140   # значок и название
        $pad = 24                                   # поля и отступ пилюли
        $wName = (Measure-UiText $env:COMPUTERNAME) + $pad; $wOs = (Measure-UiText $os) + $pad; $wDom = (Measure-UiText 'в домене') + $pad
        $domIcon = [string][char]0xE7EF
        if ($avail -ge $wName + $wOs + $(if ($IsDomain) { $wDom } else { 0 })) { $chips = @((New-Chip $env:COMPUTERNAME 'Имя компьютера'), (New-Chip $os 'Версия Windows')) + @(if ($IsDomain) { New-Chip 'в домене' 'Компьютер в домене: имя не меняется' }) }
        elseif ($avail -ge $wName + $wOs + 36) { $chips = @((New-Chip $env:COMPUTERNAME 'Имя компьютера'), (New-Chip $os 'Версия Windows')) + @(if ($IsDomain) { New-Chip '' 'Компьютер в домене: имя не меняется' $domIcon }) }
        elseif ($avail -ge $wName + 36) { $chips = @(New-Chip $env:COMPUTERNAME "$env:COMPUTERNAME · $os$(if ($IsDomain) { ' · в домене' })") + @(if ($IsDomain) { New-Chip '' 'Компьютер в домене: имя не меняется' $domIcon }) }
        else { $chips = @(New-Chip $env:COMPUTERNAME "$env:COMPUTERNAME · $os$(if ($IsDomain) { ' · в домене' })" '' ([Math]::Max(48, $avail))) }
        $ctl.HostChips.ItemsSource = $chips
    }
    $ctl.HeadLeft.add_SizeChanged({ Update-HostChips })
    # узкое окно: «Программа» — только значком, поиск уже
    $win.add_SizeChanged({
        $narrow = $win.ActualWidth -lt 1200
        $ctl.AddAppText.Visibility = if ($narrow) { 'Collapsed' } else { 'Visible' }
        $ctl.SearchBox.Width = if ($narrow) { 240 } else { 300 }
    })

    # --- модель: пункты и навигация ---
    $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $nav = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $cats = [ordered]@{}            # CatKey -> NavEntry
    $first = @{}                    # раздел -> первая категория (Ctrl+1/2/3)
    $secLabel = @{ apps = 'Программы'; tweaks = 'Настройки Windows'; files = 'Файлы из «Моих данных» загружаются на компьютер без установки' }
    function Add-Nav ([string]$Kind, [string]$Section, [string]$Name, [string]$Key) {
        $e = New-Object PcBase.NavEntry
        $e.Kind = $Kind; $e.Section = $Section; $e.Name = $Name; $e.Key = $Key; $e.Icon = Get-CatIcon $Name
        $nav.Add($e)
        if ($Kind -eq 'cat') { $cats[$Key] = $e; if (-not $first[$Section]) { $first[$Section] = $e } }
        return $e
    }

    # список программ меняется на лету (собственный каталог), поэтому — ArrayList, а не параметр
    $appList = New-Object System.Collections.ArrayList
    foreach ($a in @($Apps)) { [void]$appList.Add($a) }
    [void](Add-Nav 'header' 'apps' 'ПРОГРАММЫ')
    foreach ($grp in ($Apps | Group-Object { $_.Category })) {
        $ck = 'apps|' + $grp.Name
        [void](Add-Nav 'cat' 'apps' $grp.Name $ck)
        foreach ($a in $grp.Group) { $items.Add((New-AppItem $a $ck $grp.Name)) }
    }

    [void](Add-Nav 'header' 'tweaks' 'НАСТРОЙКИ WINDOWS')
    foreach ($grp in ($Tweaks | Group-Object { $_.Group })) {
        $ck = 'tweaks|' + $grp.Name
        [void](Add-Nav 'cat' 'tweaks' $grp.Name $ck)
        foreach ($t in $grp.Group) {
            $it = New-Object PcBase.Item
            $it.Key = 'tweak:' + $t.Id; $it.Kind = 'tweak'; $it.Id = $t.Id; $it.Name = $t.Name
            $it.Desc = $t.Desc; $it.FullDesc = $t.Desc
            $it.CatKey = $ck; $it.CatName = "Настройки Windows · $($grp.Name)"; $it.GroupTitle = $it.CatName
            $it.Irreversible = [bool]$t.Irreversible
            $it.SearchText = @($t.Name, $t.Desc, $t.Id, $grp.Name, $t.Manual) -join "`n"
            if ($t.Irreversible) { $it.Facts.Add((New-Fact 'Необратимо' 'Не отменяется через undo.ps1, только точкой восстановления.' 'danger')) }
            else { $it.Facts.Add((New-Fact 'Отмена' 'Отменяется через undo.ps1 или «⋯ → Откат изменений» в окне.')) }
            if ($t.Manual) { $it.Facts.Add((New-Fact 'Вручную после применения' $t.Manual)) }
            $items.Add($it)
        }
    }

    # --- зависимости (Э8): поле Requires каталога. Отметил программу — нужное ей отмечается само (AutoAdded,
    # с уведомлением); снял нужное — предупреждение; в сохранение пишется только отмеченное пользователем ---
    $reqMap = @{}
    foreach ($x in @(@($Apps) + @($Tweaks))) { if ($x.Requires) { $reqMap[$x.Id] = @($x.Requires) } }
    $depItem = @{}
    foreach ($it in $items) { if ($it.Kind -in 'app', 'tweak') { $depItem[$it.Id] = $it } }
    function Get-ReqClosure ([string]$Id) {
        $seen = @{}; $queue = New-Object System.Collections.Queue
        foreach ($r in @($reqMap[$Id])) { if ($r) { $queue.Enqueue($r) } }
        while ($queue.Count) {
            $r = $queue.Dequeue()
            if ($seen.ContainsKey($r) -or $r -eq $Id) { continue }
            $seen[$r] = $true
            foreach ($n in @($reqMap[$r])) { if ($n) { $queue.Enqueue($n) } }
        }
        return @($seen.Keys)
    }
    function Get-Dependents ([string]$Id) { @($reqMap.Keys | Where-Object { (Get-ReqClosure $_) -contains $Id } | ForEach-Object { $depItem[$_] } | Where-Object { $_ }) }
    foreach ($id in @($reqMap.Keys)) {
        $it = $depItem[$id]; if (-not $it) { continue }
        $names = @($reqMap[$id] | ForEach-Object { $depItem[$_] } | Where-Object { $_ } | ForEach-Object { $_.Name })
        if ($names.Count) { $it.Facts.Add((New-Fact 'Требует' (($names -join ', ') + '. Отмечается вместе с этим пунктом.'))) }
    }
    foreach ($it in @($depItem.Values)) {
        $for = @(Get-Dependents $it.Id | ForEach-Object { $_.Name })
        if ($for.Count) { $it.Facts.Add((New-Fact 'Нужен для' ($for -join ', '))) }
    }

    # файлы: релиз files «Моих данных»; пункты появятся, когда фоновая задача получит список (Start-FilesJob)
    [void](Add-Nav 'header' 'files' 'ФАЙЛЫ')
    $fk = 'files|release'
    $fileGroup = 'Файлы · Мои файлы'
    [void](Add-Nav 'cat' 'files' 'Мои файлы' $fk)
    $navSummary = New-Object PcBase.NavEntry
    $navSummary.Kind = 'summary'; $navSummary.Name = 'Итог'; $navSummary.Key = 'summary'; $navSummary.Icon = [string][char]0xE9D5
    $navBottom = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $navBottom.Add($navSummary)

    # --- состояние окна ---
    # Mode: cat — категория слева, search — результаты поиска, summary — экран «Итог»
    # Files: off — «Мои данные» не подключены, loading, ok, none — нет релиза files, empty, error (FilesError)
    # WantFiles — файлы из открытого сохранения, которые ещё не в списке (список не пришёл или их нет в релизе)
    $ui = @{ Mode = 'cat'; Cat = $null; Nav = $null; Words = @(); Busy = $false; Bulk = $false; SaveName = $null; Result = $null; Name = $null
             Job = $null; PushAgain = $false; CodeShown = $null
             Files = 'off'; FilesRepo = $null; FilesError = $null; FilesJob = $null; WantFiles = @()
             Public = $null; Capture = $null; CaptureJob = $null }
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($items)
    $groupBy = New-Object Windows.Data.PropertyGroupDescription 'GroupTitle'

    function Test-Search ($o) {
        foreach ($w in $ui.Words) { if ($o.SearchText.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false } }
        return $true
    }
    # фильтры по статусу программ: «не установленные» и «есть обновления» (оба — объединение); твики и файлы не фильтруются
    function Test-StatusFilter ($o) {
        if ($o.Kind -ne 'app' -or -not ($ctl.FilterMissing.IsChecked -or $ctl.FilterUpdates.IsChecked)) { return $true }
        return ($ctl.FilterMissing.IsChecked -and $o.StatusKind -eq 'missing') -or ($ctl.FilterUpdates.IsChecked -and $o.StatusKind -eq 'update')
    }
    function Test-Visible ($o) {
        if (-not (Test-StatusFilter $o)) { return $false }
        if ($ui.Mode -eq 'search') { return (Test-Search $o) }
        if ($ui.Mode -eq 'summary') { return $o.IsPicked }
        return $o.CatKey -eq $ui.Cat
    }
    $view.Filter = [Predicate[object]]{ param($o) Test-Visible $o }

    # выбор для прогона: IsPicked — установленная (IsLocked) входит, только если с ней что-то делается.
    # -ForSave — для сохранения: всё отмеченное, включая установленные (набор переносится на другие компьютеры)
    function Get-Chosen ([switch]$ForSave) {
        $on = @{}
        foreach ($it in $items) { if (($ForSave -and $it.IsChecked -and -not $it.AutoAdded) -or (-not $ForSave -and $it.IsPicked)) { $on[$it.Key] = $it } }
        $appIn = { param($A) $o = $on['app:' + $A.Id]; $o -and ($ForSave -or -not $o.IsLocked -or $o.Action -in 'update', 'reinstall') }
        return @{
            Apps     = @($appList | Where-Object { & $appIn $_ } | ForEach-Object { $_.Id })
            Configs  = @($appList | Where-Object { $_.Config -and $_.Config.Import -and $on.ContainsKey('app:' + $_.Id) -and $on['app:' + $_.Id].ConfigOn } | ForEach-Object { $_.Id })
            Tweaks   = @($Tweaks | Where-Object { $on.ContainsKey('tweak:' + $_.Id) } | ForEach-Object { $_.Id })
            # действия над установленными (Э7): обновить, переустановить, удалить
            Upgrades = @($items | Where-Object { -not $ForSave -and $_.Kind -eq 'app' -and $_.IsLocked -and $_.Action -eq 'update' } | ForEach-Object { $_.Id })
            Reinstall = @($items | Where-Object { -not $ForSave -and $_.Kind -eq 'app' -and $_.IsLocked -and $_.Action -eq 'reinstall' } | ForEach-Object { $_.Id })
            Remove   = @($items | Where-Object { -not $ForSave -and $_.Kind -eq 'app' -and $_.IsLocked -and $_.Action -eq 'remove' } | ForEach-Object { $_.Id })
            # пока списка нет, файлы из сохранения не теряются: они уйдут и в новое сохранение, и в прогон
            Files    = @(@($items | Where-Object { $_.Kind -eq 'file' -and $_.IsChecked } | ForEach-Object { $_.Id }) + @($ui.WantFiles) | Sort-Object -Unique)
        }
    }

    # счётчики «выбрано/всего» слева и сводка внизу
    function Update-Counts {
        $sel = @{}; $tot = @{}; $n = 0
        foreach ($it in $items) {
            $tot[$it.CatKey]++
            if ($it.IsPicked) { $sel[$it.CatKey]++; $n++ }
        }
        foreach ($k in $cats.Keys) {
            $s = [int]$sel[$k]; $t = [int]$tot[$k]
            $cats[$k].CountText = if ($t) { "$s/$t" } else { '' }
            $cats[$k].IsFull = $t -gt 0 -and $s -eq $t
        }
        $navSummary.CountText = if ($n) { "$n" } else { '' }
        Update-CatCheck

        $c = Get-Chosen
        $parts = @("$($c.Apps.Count) $(Get-Plural $c.Apps.Count 'программа' 'программы' 'программ')$(if ($c.Configs.Count) { " (⚙ $($c.Configs.Count))" })",
            "$($c.Tweaks.Count) $(Get-Plural $c.Tweaks.Count 'настройка' 'настройки' 'настроек')")
        if ($c.Files.Count) { $parts += "$($c.Files.Count) $(Get-Plural $c.Files.Count 'файл' 'файла' 'файлов')" }
        $ctl.Summary.Text = $parts -join ' · '
        $ctl.Summary.ToolTip = "Выбрано: программ $($c.Apps.Count), из них с моими настройками $($c.Configs.Count); настроек Windows $($c.Tweaks.Count); файлов $($c.Files.Count)"
    }

    # подсветка категорий с совпадениями, пока идёт поиск
    function Update-NavHits {
        $on = $ui.Mode -eq 'search'
        $hits = @{}
        if ($on) { foreach ($it in $items) { if (Test-Search $it) { $hits[$it.CatKey]++ } } }
        foreach ($k in $cats.Keys) {
            $cats[$k].IsHit = $on -and $hits[$k] -gt 0
            $cats[$k].IsDim = $on -and -not $hits[$k]
        }
        $navSummary.IsDim = $on
    }

    function Update-View {
        $view.GroupDescriptions.Clear()
        if ($ui.Mode -ne 'cat') { $view.GroupDescriptions.Add($groupBy) }
        $view.Refresh()
        $n = $view.Count
        $card = $ui.Mode -eq 'cat' -and $ui.Cat -eq $fk -and $ui.Files -ne 'ok'
        $ctl.CatButtons.Visibility = if ($ui.Mode -eq 'cat' -and -not $card) { 'Visible' } else { 'Collapsed' }
        $appsHere = $ui.Mode -eq 'search' -or ($ui.Mode -eq 'cat' -and $ui.Cat -like 'apps|*')
        $ctl.FilterBar.Visibility = if ($appsHere) { 'Visible' } else { 'Collapsed' }
        Update-CatCheck
        switch ($ui.Mode) {
            'search' {
                $ctl.ListTitle.Text = "Поиск: «$($ctl.Search.Text.Trim())»"
                $ctl.ListHint.Text = "Найдено: $n  ·  выберите категорию слева, чтобы перейти к ней; Esc — очистить поиск"
                $ctl.ListEmpty.Text = 'Ничего не найдено. Поиск выполняется по названию, описанию, идентификатору, winget-ID и категории.'
            }
            'summary' {
                $ctl.ListTitle.Text = 'Итог'
                $ctl.ListHint.Text = 'Все отмеченные пункты по разделам. Снимите отметку, чтобы исключить пункт'
                $ctl.ListEmpty.Text = 'Пока ничего не выбрано.'
            }
            default {
                $e = $cats[$ui.Cat]
                $ctl.ListTitle.Text = $e.Name
                $ctl.ListHint.Text = $secLabel[$e.Section]
                $ctl.ListEmpty.Text = 'В этой категории нет пунктов.'
            }
        }
        $ctl.ListEmpty.Visibility = if ($n -or $card) { 'Collapsed' } else { 'Visible' }
        $ctl.FilesCard.Visibility = if ($card) { 'Visible' } else { 'Collapsed' }
        $ctl.List.Visibility = if ($card) { 'Collapsed' } else { 'Visible' }   # карточка «Файлов» вместо списка, а не поверх
        if ($n) { $ctl.List.ScrollIntoView($view.GetItemAt(0)) }
    }

    function Open-Nav ($e) {
        $ui.Nav = $e
        if ($e.Kind -eq 'summary') { $ui.Mode = 'summary' } else { $ui.Mode = 'cat'; $ui.Cat = $e.Key }
        Update-NavHits
        Update-View
        Invoke-UiFade $ctl.List
    }

    # отметка в навигации: категории — в верхнем списке, «Итог» — в нижнем; $null — снять везде (идёт поиск)
    function Set-NavMark ($e) {
        $ui.Busy = $true
        $ctl.Nav.SelectedItem = if ($e -and $e.Kind -eq 'cat') { $e } else { $null }
        $ctl.NavBottom.SelectedItem = if ($e -and $e.Kind -eq 'summary') { $e } else { $null }
        $ui.Busy = $false
    }

    # перейти как кликом (через SelectionChanged) и поставить фокус на пункт
    function Select-Nav ($e) {
        $lb = if ($e.Kind -eq 'summary') { $ctl.NavBottom } else { $ctl.Nav }
        $lb.SelectedItem = $e
        $c = $lb.ItemContainerGenerator.ContainerFromItem($e)
        if ($c) { [void]$c.Focus() }
    }

    # трёхпозиционная галочка категории: все / часть (null) / ни одного
    function Update-CatCheck {
        if ($ui.Mode -ne 'cat') { return }
        $list = @($items | Where-Object { $_.CatKey -eq $ui.Cat -and (Test-StatusFilter $_) })
        $on = @($list | Where-Object { $_.IsChecked }).Count
        $ctl.CatCheck.IsChecked = if (-not $on) { $false } elseif ($on -eq $list.Count) { $true } else { $null }
    }

    function Set-Checked ($List, [bool]$On) {
        $ui.Bulk = $true
        foreach ($it in @($List)) { $it.IsChecked = $On }
        $ui.Bulk = $false
        Update-Counts
    }

    # загрузка сохранения заменяет текущий выбор целиком. Возвращает, сколько id из него нет в каталоге этого ПК
    function Set-Selection ([hashtable]$Sel) {
        $known = @{}
        foreach ($it in $items) { $known["$($it.Kind):$($it.Id)"] = $true }
        $miss = @($Sel.Apps | Where-Object { -not $known["app:$_"] }).Count + @($Sel.Tweaks | Where-Object { -not $known["tweak:$_"] }).Count
        # файлы — по имени ассета или по подписи (так находятся и старые сохранения с именами файлов)
        $files = @($items | Where-Object { $_.Kind -eq 'file' })
        $want = @($Sel.Files | Where-Object { $f = $_; -not @($files | Where-Object { $_.Id -eq $f -or $_.Name -eq $f }).Count })
        if ($ui.Files -eq 'ok') { $miss += $want.Count; $ui.WantFiles = @() } else { $ui.WantFiles = $want }   # список ещё не пришёл
        $ui.Bulk = $true
        foreach ($it in $items) {
            $on = switch ($it.Kind) {
                'app'   { $Sel.Apps -contains $it.Id }
                'tweak' { $Sel.Tweaks -contains $it.Id }
                'file'  { $Sel.Files -contains $it.Id -or $Sel.Files -contains $it.Name }
            }
            $it.IsChecked = [bool]$on
            if ($it.HasConfig) { $it.ConfigOn = [bool]$on -and ($Sel.Configs -contains $it.Id) }
            $it.AutoAdded = $false
        }
        # зависимости в сохранении не хранятся — достраиваются при загрузке
        foreach ($it in @($depItem.Values | Where-Object { $_.IsPicked -and $reqMap.ContainsKey($_.Id) })) { Update-Deps $it -Quiet }
        $ui.Bulk = $false
        Update-Counts
        if ($ui.Mode -ne 'cat') { Update-NavHits; Update-View }
        return $miss
    }

    # зависимости после изменения одного пункта (Э8). Отмечен — нужное ему отмечается (AutoAdded) с уведомлением;
    # снят — предупреждение, если он нужен отмеченным, и снимаются автоотмеченные, которые больше никому не нужны
    function Update-Deps ($Changed, [switch]$Quiet) {
        $ui.InDeps = $true
        try {
            if ($Changed.IsPicked) {
                $added = @()
                foreach ($d in (Get-ReqClosure $Changed.Id)) {
                    $di = $depItem[$d]
                    if ($di -and -not $di.IsChecked) { $di.AutoAdded = $true; $di.IsChecked = $true; $added += $di.Name }
                }
                if ($added.Count -and -not $Quiet) {
                    Show-Notice "Добавлено: $($added -join ', '). $(if ($added.Count -eq 1) { 'Требуется' } else { 'Требуются' }) для «$($Changed.Name)»."
                }
            } else {
                $need = @(Get-Dependents $Changed.Id | Where-Object { $_.IsPicked } | ForEach-Object { $_.Name })
                if ($need.Count -and -not $Quiet -and $Changed.CanToggle) {
                    Show-Notice "«$($Changed.Name)» не будет установлен, но он требуется для: $($need -join ', '). Без него $(if ($need.Count -eq 1) { 'программа может работать' } else { 'они могут работать' }) неправильно." 'warn'
                }
                foreach ($d in (Get-ReqClosure $Changed.Id)) {
                    $di = $depItem[$d]
                    if ($di -and $di.AutoAdded -and $di.IsChecked -and -not @(Get-Dependents $d | Where-Object { $_.IsPicked }).Count) { $di.IsChecked = $false; $di.AutoAdded = $false }
                }
            }
        } finally { $ui.InDeps = $false }
        Update-NeededBy
    }
    function Update-NeededBy {
        foreach ($it in @($depItem.Values)) {
            $n = (@(Get-Dependents $it.Id | Where-Object { $_.IsPicked } | ForEach-Object { $_.Name }) -join ', ')
            if ($it.NeededBy -ne $n) { $it.NeededBy = $n }
        }
    }

    # уведомление над списком: ok — акцентом, warn — красным
    function Show-Notice ([string]$Text, [string]$Tone = 'ok') {
        $warn = $Tone -eq 'warn'
        $ctl.NoticeText.Text = $Text
        $ctl.NoticeIcon.Text = if ($warn) { [string][char]0xE7BA } else { [string][char]0xE73E }
        $ctl.Notice.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($warn) { 'DangerSoft' } else { 'AccentSoft' }))
        $ctl.Notice.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $(if ($warn) { 'Danger' } else { 'AccentText' }))
        $ctl.NoticeIcon.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($warn) { 'Danger' } else { 'AccentText' }))
        $ctl.Notice.Visibility = 'Visible'
    }

    function Set-SaveName ([string]$Name) {
        $ui.SaveName = $Name
        $ctl.SetBtnText.Text = if ($Name) { $Name } else { 'Профили' }
    }

    function Import-Save ([string]$Path) {
        try { $s = Read-SaveFile $Path }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось открыть профиль' -Lines @($Path, @{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        $miss = Set-Selection $s
        Set-SaveName $s.Name
        $msg = "Открыто «$($s.Name)»"
        if ($s.Machine) { $msg += " (компьютер $($s.Machine), $($s.Created.ToString('dd.MM.yyyy HH:mm')))" }
        if ($miss) { Show-Notice "$msg. Пропущено пунктов, отсутствующих в каталоге этого компьютера (удалены или не поддерживаются этой версией Windows): $miss." 'warn' }
        else { Show-Notice $msg }
    }

    # пока идёт фоновая отправка или подключение, git своих данных трогать нельзя
    function Test-DataBusy {
        if (-not $ui.Job) { return $false }
        $t = 'Выполняется синхронизация с GitHub. Повторите действие через несколько секунд.'
        Show-Notice $t 'warn'
        $ctl.CaptureSummary.Text = $t   # уведомление над списком в режиме «Снятие настроек» не видно
        return $true
    }

    function Save-Current {
        if (Test-DataBusy) { return }
        $c = Get-Chosen -ForSave
        $where = if (Test-PbDataConnected) { "Профиль будет записан в «Мои данные» ($($script:PB.DataRoot)) и отправлен в GitHub. Он станет доступен на всех компьютерах." }
                 else { "Профиль будет записан на этом компьютере ($(Get-PbLocalSaveDir)). После подключения «Моих данных» его можно перенести." }
        $def = if ($ui.SaveName) { $ui.SaveName } else { 'Мой набор' }
        $name = Show-UiMessage -Owner $win -Title 'Сохранить профиль' -WithInput -InputValue $def -Primary 'Сохранить' -Secondary 'Отмена' `
            -Lines @("Отмечено: $($ctl.Summary.Text)", @{ Text = $where; Tone = 'muted' })
        if ($null -eq $name) { return }
        $name = $name.Trim()
        if (-not $name) { return }
        if (@(Get-PbSaves | Where-Object { $_.Name -eq $name }).Count -and $name -ne $ui.SaveName) {
            if (-not (Show-UiMessage -Owner $win -Title "«$name» уже существует" -Lines @('Заменить профиль текущим выбором?') -Primary 'Заменить' -Secondary 'Назад' -SafeDefault)) { return }
        }
        try { [void](Save-PbSave $name $c) }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось сохранить' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        Set-SaveName $name
        if (Test-PbDataConnected) { Show-Notice "Сохранено «$name» в «Мои данные». Отправка в GitHub…"; Start-DataJob 'push' }
        else { Show-Notice "Сохранено «$name» на этом компьютере." }
        Update-DataBox
    }

    function Rename-Save ([string]$Path) {
        if (Test-DataBusy) { return }
        $old = (Read-SaveFile $Path).Name
        $new = Show-UiMessage -Owner $win -Title 'Переименовать' -WithInput -InputValue $old -Primary 'Переименовать' -Secondary 'Отмена' -Lines @("Сохранение «$old»")
        if ($null -eq $new -or -not $new.Trim() -or $new.Trim() -eq $old) { return }
        $new = $new.Trim()
        try { [void](Rename-PbSave $Path $new) }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось переименовать' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        if ($ui.SaveName -eq $old) { Set-SaveName $new }
        Show-Notice "Сохранение «$old» переименовано в «$new»."
        if (Test-PbDataConnected) { Start-DataJob 'push' }
    }

    function Remove-Save ([string]$Path) {
        if (Test-DataBusy) { return }
        $name = (Read-SaveFile $Path).Name
        $lines = @("Сохранение «$name» будет удалено.")
        if (Test-PbDataConnected) { $lines += @{ Text = 'Сохранение будет удалено и из репозитория на GitHub, но останется в его истории.'; Tone = 'muted' } }
        if (-not (Show-UiMessage -Owner $win -Title 'Удалить профиль?' -Lines $lines -Primary 'Удалить' -Secondary 'Назад' -SafeDefault)) { return }
        try { Remove-PbSave $Path }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось удалить' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        if ($ui.SaveName -eq $name) { Set-SaveName $null }
        Show-Notice "Сохранение «$name» удалено."
        if (Test-PbDataConnected) { Start-DataJob 'push' }
    }

    function New-MenuText ([string]$Text, [string]$Style) {
        $mi = New-Object Windows.Controls.MenuItem
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = $Text; $tb.TextWrapping = 'Wrap'; $tb.MaxWidth = 320
        if ($Style) { $tb.Style = $win.FindResource($Style) }
        $mi.Header = $tb; $mi.IsHitTestVisible = $false; $mi.Focusable = $false
        return $mi
    }

    function New-IconButton ([string]$Glyph, [string]$Tag, [string]$Tip) {
        $b = New-Object Windows.Controls.Button
        $b.Style = $win.FindResource('IconButton'); $b.Tag = $Tag; $b.ToolTip = $Tip
        [Windows.Automation.AutomationProperties]::SetName($b, $Tip)   # кнопка-значок: имя для экранного диктора
        $g = New-Object Windows.Controls.TextBlock
        $g.Style = $win.FindResource('Glyph'); $g.Text = $Glyph; $g.FontSize = 14; $g.IsHitTestVisible = $false
        $b.Content = $g
        return $b
    }

    # «Сохранения ▾»: свои сохранения (имя, дата, с какого ПК, переименовать, удалить), сохранить текущее, открыть файл
    function Fill-SaveMenu {
        $m = $ctl.SetBtn.ContextMenu
        $m.Items.Clear()
        $saves = @(Get-PbSaves)
        [void]$m.Items.Add((New-MenuText $(if (Test-PbDataConnected) { 'В МОИХ ДАННЫХ' } else { 'НА ЭТОМ ПК' }) 'SectionLabel'))
        if (-not $saves.Count) {
            [void]$m.Items.Add((New-MenuText 'Профилей нет. Чтобы сохранить текущий выбор, используйте «Сохранить как профиль…».' 'Muted'))
        }
        foreach ($s in $saves) {
            $mi = New-Object Windows.Controls.MenuItem
            $mi.Tag = $s.Path
            $g = New-Object Windows.Controls.Grid
            $g.MinWidth = 300
            foreach ($w in '*', 'Auto', 'Auto') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w; $g.ColumnDefinitions.Add($cd) }
            $sp = New-Object Windows.Controls.StackPanel
            $sp.VerticalAlignment = 'Center'
            $t1 = New-Object Windows.Controls.TextBlock
            $t1.Text = $s.Name; $t1.FontWeight = 'SemiBold'; $t1.TextTrimming = 'CharacterEllipsis'; $t1.MaxWidth = 260
            $t2 = New-Object Windows.Controls.TextBlock
            $t2.Style = $win.FindResource('Caption')
            $t2.Text = $s.Created.ToString('dd.MM.yyyy HH:mm') + $(if ($s.Machine) { " · $($s.Machine)" })
            [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2)
            $b1 = New-IconButton ([string][char]0xE70F) "?ren|$($s.Path)" 'Переименовать'
            $b2 = New-IconButton ([string][char]0xE74D) "?del|$($s.Path)" 'Удалить'
            [Windows.Controls.Grid]::SetColumn($b1, 1); [Windows.Controls.Grid]::SetColumn($b2, 2)
            $b1.Margin = '8,0,0,0'
            [void]$g.Children.Add($sp); [void]$g.Children.Add($b1); [void]$g.Children.Add($b2)
            $mi.Header = $g
            [void]$m.Items.Add($mi)
        }
        [void]$m.Items.Add((New-Object Windows.Controls.Separator))
        foreach ($p in @(@('Сохранить как профиль…   Ctrl+S', '?save'), @('Открыть файл…', '?open'))) {
            $mi = New-Object Windows.Controls.MenuItem
            $mi.Header = $p[0]; $mi.Tag = $p[1]
            [void]$m.Items.Add($mi)
        }
    }

    # --- Мои данные ---
    function Update-ConfigAvail {
        $on = Test-PbDataConnected
        foreach ($it in $items) {
            if (-not ($it.HasConfig -and $it.ConfigFile)) { continue }
            $ok = [bool](Find-PbConfig $it.ConfigFile)
            $it.ConfigAvailable = $ok
            $it.ConfigHint = if ($ok) { '' }
                elseif ($on) { "В «Моих данных» нет файла configs\$($it.ConfigFile). Настройки снимаются на настроенном компьютере на вкладке «Снятие настроек»." }
                else { 'Сохранённые настройки недоступны: подключите «Мои данные» (слева внизу).' }
        }
    }

    # кнопка справа (⋯, …) или отдельной строкой на всю ширину («Подключить», «Отмена»)
    function Set-DataBtnWide ([bool]$Wide) {
        [Windows.Controls.Grid]::SetRow($ctl.DataBtn, [int]$Wide)
        [Windows.Controls.Grid]::SetColumn($ctl.DataBtn, $(if ($Wide) { 0 } else { 2 }))
        [Windows.Controls.Grid]::SetColumnSpan($ctl.DataBtn, $(if ($Wide) { 3 } else { 1 }))
        $ctl.DataBtn.Margin = if ($Wide) { '0,10,0,0' } else { '8,0,0,0' }
    }

    function Update-DataBox {
        $tone = 'TextMuted'
        Set-DataBtnWide ([bool]($ui.Job -and $ui.Job.Action -eq 'connect') -or -not (Test-PbDataConnected))
        if ($ui.Job) {
            $ctl.DataStatus.Text = if ($ui.Job.Sync.Step) { $ui.Job.Sync.Step } else { 'синхронизация с GitHub…' }
            $ctl.DataBtn.Content = if ($ui.Job.Action -eq 'connect') { 'Отмена' } else { '…' }
            $ctl.DataBtn.IsEnabled = $ui.Job.Action -eq 'connect'
        } else {
            $st = Get-PbDataState
            $ctl.DataBtn.IsEnabled = $true
            if (-not $st.Connected) {
                $ctl.DataStatus.Text = 'не подключены'
                $ctl.DataBtn.Content = 'Подключить'
                $ctl.DataBtn.ToolTip = 'Вход в GitHub и подключение приватного репозитория: профили и настройки программ на всех компьютерах'
            } else {
                $tone = if ($st.Pending -or $ui.Public) { 'Danger' } else { 'AccentText' }
                $ctl.DataStatus.Text = "$(if ($st.Repo) { $st.Repo } else { 'подключены' })$(if ($ui.Public) { ' · публичный' })$(if ($st.Pending) { " · не отправлено: $($st.Pending)" })"
                $g = New-Object Windows.Controls.TextBlock
                $g.Style = $win.FindResource('Glyph'); $g.Text = [string][char]0xE712; $g.FontSize = 14
                $ctl.DataBtn.Content = $g
                [Windows.Automation.AutomationProperties]::SetName($ctl.DataBtn, 'Действия с «Моими данными»')
                $ctl.DataBtn.ToolTip = "Мои данные: $($script:PB.DataRoot)$(if ($st.Repo) { " ← $($st.Repo)" })"
            }
        }
        $ctl.DataStatus.ToolTip = $ctl.DataStatus.Text
        if ($ui.Files -eq 'off') { Update-FilesCard }
        if ($ctl.CapturePane.Visibility -eq 'Visible' -and -not (Test-PbDataConnected)) { Update-Capture }
        $ctl.DataIcon.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $tone)
    }

    # фоновая работа с GitHub (connect / push) в отдельном runspace: окно не замерзает, ход — через $Sync
    $jobTimer = New-Object Windows.Threading.DispatcherTimer
    $jobTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    function Start-DataJob ([string]$Action) {
        if ($ui.Job) { if ($Action -eq 'push') { $ui.PushAgain = $true }; return }
        $sync = [hashtable]::Synchronized(@{ Step = ''; Code = $null; Url = $null; Pid = $null })
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root, $DataRoot, $Sync, $Action)
            . (Join-Path $Root 'lib\common.ps1'); . (Join-Path $Root 'lib\data.ps1')
            $script:PB.Root = $Root; $script:PB.DataRoot = $DataRoot
            switch ($Action) { 'connect' { Connect-PbData $Sync } 'push' { Push-PbData } }
        })
        foreach ($a in @($script:PB.Root, $script:PB.DataRoot, $sync, $Action)) { [void]$ps.AddArgument($a) }
        $ui.Job = @{ Ps = $ps; Handle = $ps.BeginInvoke(); Sync = $sync; Action = $Action }
        $jobTimer.Start()
        Update-DataBox
    }

    function Complete-DataJob ($Job, $Result, [string]$Err) {
        $ctl.DataLogin.Visibility = 'Collapsed'; $ui.CodeShown = $null
        if ($Job.Action -eq 'push') {
            $res = if ($Err) { 'offline' } else { [string](@($Result)[-1]) }
            $ui.Public = if ($res -eq 'public') { Get-PbDataRepo } else { $null }
            if ($res -eq 'public') { Show-Notice (Get-PbPublicWarning $ui.Public) 'warn' }
            elseif ($res -eq 'ok') { $ctl.NoticeText.Text = $ctl.NoticeText.Text -replace ' Отправка в GitHub…$', ' Отправлено в GitHub.' -replace '^Синхронизация с GitHub…$', '«Мои данные» синхронизированы с GitHub.' }
            else { Show-Notice 'Нет связи с GitHub. Изменения сохранены на этом компьютере и будут отправлены при следующем запуске.' 'warn' }
            Update-DataBox
            if ($ui.PushAgain) { $ui.PushAgain = $false; Start-DataJob 'push' }
            return
        }
        Update-DataBox
        if ($Err) { [void](Show-UiMessage -Owner $win -Title 'Не удалось подключить «Мои данные»' -Lines @(@{ Text = $Err; Tone = 'muted' })); return }
        Update-ConfigAvail
        Start-FilesJob
        $login = @($Result)[-1]
        Show-Notice "«Мои данные» подключены: $login, $($script:PB.DataRoot)."
        if ($Job.Sync.Public) { $ui.Public = $Job.Sync.Public; Show-Notice (Get-PbPublicWarning $ui.Public) 'warn'; Update-DataBox }
        # разметка, затем перенос локальных сохранений; отправка — одна, в конце (git занят, пока идёт фоновая задача)
        $push = Initialize-DataLayout
        Update-Capture
        $local = @(Get-PbSaves -LocalOnly)
        if (-not $local.Count -or (Test-PbDataReadOnly)) { if ($push) { Start-DataJob 'push' }; return }
        $names = ($local | ForEach-Object { "• $($_.Name)" }) -join "`n"
        $ok = Show-UiMessage -Owner $win -Title 'Перенести профили?' -Primary 'Перенести' -Secondary 'Оставить' -Lines @(
            "На этом компьютере есть профили, созданные без подключения: $($local.Count).", $names,
            @{ Text = 'Профили будут перенесены в «Мои данные» и отправлены в GitHub. При совпадении имени к нему добавляется номер.'; Tone = 'muted'; Gap = $true })
        if (-not $ok) { if ($push) { Start-DataJob 'push' }; return }
        try { $n = Move-PbLocalSaves; Show-Notice "Перенесено в «Мои данные»: $n. Отправка в GitHub…"; Start-DataJob 'push' }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось перенести профили' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); if ($push) { Start-DataJob 'push' } }
    }

    $jobTimer.add_Tick({
        $j = $ui.Job
        if (-not $j) { $jobTimer.Stop(); return }
        # вход в GitHub: показать код и один раз открыть страницу
        if ($j.Sync.Code -and $ui.CodeShown -ne $j.Sync.Code) {
            $ui.CodeShown = $j.Sync.Code
            $ctl.DataCode.Text = $j.Sync.Code; $ctl.DataLogin.Visibility = 'Visible'
            try { [Windows.Clipboard]::SetText($j.Sync.Code) } catch { }
            if ($j.Sync.Url) { Start-Process $j.Sync.Url }
        }
        if (-not $j.Handle.IsCompleted) { Update-DataBox; return }
        $jobTimer.Stop()
        $res = $null; $err = $null
        try { $res = $j.Ps.EndInvoke($j.Handle) }
        catch { $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        $j.Ps.Dispose(); $ui.Job = $null
        Complete-DataJob $j $res $err
    })

    # --- Файлы: список из релиза files в фоне (сеть — только в фоне, окно не ждёт) ---
    $filesTimer = New-Object Windows.Threading.DispatcherTimer
    $filesTimer.Interval = [TimeSpan]::FromMilliseconds(250)

    # карточка вместо списка: не подключены, загрузка, нет файлов, ошибка
    function Update-FilesCard {
        $btn = $null; $glyph = 0xE8B7
        switch ($ui.Files) {
            'off' {
                $title = 'Подключите «Мои данные»'
                $text = 'Файлы хранятся в релизе files приватного репозитория «Моих данных» на GitHub. Чтобы увидеть свои файлы, подключите «Мои данные».'
                $btn = if ($ui.Job -and $ui.Job.Action -eq 'connect') { '' } else { 'Подключить «Мои данные»' }
                $glyph = 0xE72E
            }
            'loading' { $title = 'Загрузка списка файлов…'; $text = "Репозиторий $($ui.FilesRepo)."; $glyph = 0xE895 }
            'none' {
                $title = 'Файлов пока нет'
                $text = "В репозитории $($ui.FilesRepo) нет релиза files. Файлы добавляются на компьютере, где они хранятся: powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\tools\upload-files.ps1 <файлы>"
                $btn = 'Обновить'
            }
            'empty' {
                $title = 'Файлов пока нет'
                $text = "Релиз files в репозитории $($ui.FilesRepo) пуст. Файлы добавляются на компьютере, где они хранятся: powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\tools\upload-files.ps1 <файлы>"
                $btn = 'Обновить'
            }
            'error' { $title = 'Не удалось получить список файлов'; $text = $ui.FilesError; $btn = 'Повторить'; $glyph = 0xE7BA }
            default { $title = ''; $text = '' }
        }
        $ctl.FilesCardTitle.Text = $title; $ctl.FilesCardText.Text = $text
        $ctl.FilesCardIcon.Text = [string][char]$glyph
        $ctl.FilesCardBtn.Content = $btn
        $ctl.FilesCardBtn.Visibility = if ($btn) { 'Visible' } else { 'Collapsed' }
    }

    # заменить пункты-файлы списком из релиза ($List) и перейти в состояние $State
    function Set-FileItems ([string]$State, $List) {
        $ui.Files = $State
        $want = @($ui.WantFiles)
        foreach ($it in @($items | Where-Object { $_.Kind -eq 'file' })) {
            if ($it.IsChecked) { $want += $it.Id }   # отмеченное раньше переживает обновление списка
            [void]$items.Remove($it)
        }
        $ui.Bulk = $true
        # @($null) в 5.1 — массив из одного элемента: без фильтра появлялся пустой файл «0 Б», пока «Мои данные» не подключены
        foreach ($f in @($List | Where-Object { $_ })) {
            $it = New-FileItem $f $fk $fileGroup
            $it.IsChecked = ($want -contains $f.Name -or $want -contains $f.Title)
            $it.add_PropertyChanged($onChange)
            $items.Add($it)
        }
        $ui.Bulk = $false
        if ($State -eq 'ok' -or $State -eq 'empty' -or $State -eq 'none') {
            $lost = @($want | Where-Object { $w = $_; -not @($List | Where-Object { $_.Name -eq $w -or $_.Title -eq $w }).Count } | Sort-Object -Unique)
            $ui.WantFiles = @()
            if ($lost.Count) { Show-Notice "Файлов из профиля нет в релизе files, они пропущены: $($lost -join ', ')." 'warn' }
        } else { $ui.WantFiles = @($want | Sort-Object -Unique) }
        Update-FilesCard
        Update-Counts
        Update-NavHits
        Update-View
    }

    function Start-FilesJob {
        if ($ui.FilesJob) { return }
        $repo = Get-PbDataRepo
        if (-not $repo) { Set-FileItems 'off'; return }
        $ui.FilesRepo = $repo
        Set-FileItems 'loading'
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root, $DataRoot, $Repo)
            . (Join-Path $Root 'lib\common.ps1'); . (Join-Path $Root 'lib\data.ps1'); . (Join-Path $Root 'lib\files.ps1')
            $script:PB.Root = $Root; $script:PB.DataRoot = $DataRoot
            Update-PbPath
            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI не найден. Подключите «Мои данные» заново: GitHub CLI будет установлен.' }
            Get-PbFiles $Repo
        })
        foreach ($a in @($script:PB.Root, $script:PB.DataRoot, $repo)) { [void]$ps.AddArgument($a) }
        $ui.FilesJob = @{ Ps = $ps; Handle = $ps.BeginInvoke() }
        $filesTimer.Start()
    }

    $filesTimer.add_Tick({
        $j = $ui.FilesJob
        if (-not $j -or -not $j.Handle.IsCompleted) { return }
        $filesTimer.Stop()
        $res = $null; $err = $null
        try { $res = @($j.Ps.EndInvoke($j.Handle))[-1]; if ($res) { $res = $res.PSObject.BaseObject } }
        catch { $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        $j.Ps.Dispose(); $ui.FilesJob = $null
        # пока шёл запрос, «Мои данные» могли отключить
        if (-not (Test-PbDataConnected)) { Set-FileItems 'off'; return }
        if ($err -or -not $res) { $ui.FilesError = if ($err) { $err } else { 'Пустой ответ GitHub CLI.' }; Set-FileItems 'error'; return }
        if (-not $res.ReleaseId) { Set-FileItems 'none'; return }
        if (-not $res.Files.Count) { Set-FileItems 'empty'; return }
        Set-FileItems 'ok' $res.Files
    })

    $ctl.FilesCardBtn.add_Click({
        if ($ui.Files -eq 'off') { if (-not $ui.Job) { Connect-Data } }
        else { Start-FilesJob }
    })

    # разметка репозитория данных: новый — создать; чужой без манифеста — спросить и добавить недостающее;
    # старее движка — миграция; новее — только чтение. $true — есть коммит, нужна отправка
    function Initialize-DataLayout {
        if (-not (Test-PbDataConnected)) { return $false }
        $repo = Get-PbDataRepo
        try {
            switch (Get-PbDataLayout) {
                'empty' {
                    Install-PbDataLayout (Get-PbLayoutPlan -Fresh)
                    Show-Notice "В репозитории $repo создана разметка Tabula Rasa: README, saves, configs, catalog, .gitignore."
                    return $true
                }
                'foreign' {
                    $plan = @(Get-PbLayoutPlan)
                    $ok = Show-UiMessage -Owner $win -Title 'Добавить разметку Tabula Rasa?' -Primary 'Добавить' -Secondary 'Не сейчас' -Lines @(
                        "В репозитории $repo нет файла tabula-rasa.json, но есть другие файлы. Будет добавлено только недостающее:",
                        ((Format-PbLayoutPlan $plan | ForEach-Object { "• $_" }) -join "`n"),
                        @{ Text = 'Существующие файлы и папки не удаляются, не переносятся и не перезаписываются. Изменения фиксируются одним коммитом «Разметка Tabula Rasa».'; Tone = 'muted'; Gap = $true })
                    if (-not $ok) { return $false }
                    Install-PbDataLayout $plan
                    Show-Notice "Разметка Tabula Rasa добавлена в $repo."
                    return $true
                }
                'old' { Update-PbDataLayout; return $true }
                'new' { Show-Notice 'Разметка «Моих данных» создана более новой версией Tabula Rasa. Изменения в «Моих данных» не сохраняются, пока программа не обновлена.' 'warn' }
                'broken' { Show-Notice "Файл tabula-rasa.json в репозитории $repo не читается. Исправьте или удалите его, чтобы Tabula Rasa восстановила разметку." 'warn' }
            }
        } catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось создать разметку «Моих данных»' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })) }
        return $false
    }

    function Connect-Data {
        $ok = Show-UiMessage -Owner $win -Title 'Подключить «Мои данные»?' -Primary 'Подключить' -Secondary 'Отмена' -Lines @(
            'Вход в GitHub выполняется в браузере по одноразовому коду.',
            "Профили и настройки программ хранятся в приватном репозитории tabula-rasa-private на GitHub и доступны на всех компьютерах. Если репозитория нет, он будет создан. Локальная копия: $($script:PB.DataRoot).",
            @{ Text = 'Без подключения доступны все функции, кроме личных профилей и настроек программ. Чтобы удалить личные данные с компьютера, выберите «Отключить и удалить с этого компьютера».'; Tone = 'muted'; Gap = $true })
        if ($ok) { Start-DataJob 'connect' }
    }

    function Disconnect-Data {
        if (Test-DataBusy) { return }
        $st = Get-PbDataState
        $lines = @('С этого компьютера будет удалено:') + @(Get-PbEraseList | ForEach-Object { "• $_" })
        if ($st.Pending) { $lines += @{ Text = "Изменения, не отправленные в GitHub ($($st.Pending)), будут потеряны. Чтобы сохранить их, сначала выберите «Отправить сейчас»."; Tone = 'danger'; Gap = $true } }
        $lines += @{ Text = 'Данные на GitHub не удаляются. На другом компьютере их можно подключить снова.'; Tone = 'muted'; Gap = $true }
        if (-not (Show-UiMessage -Owner $win -Title 'Отключить и удалить с этого компьютера?' -Lines $lines -Primary 'Удалить' -Secondary 'Назад' -SafeDefault)) { return }
        $fail = @(Disconnect-PbData)
        $ui.Public = $null
        Update-ConfigAvail; Update-DataBox
        Set-FileItems 'off'
        Update-Capture
        if ($ui.SaveName -and -not @(Get-PbSaves | Where-Object { $_.Name -eq $ui.SaveName }).Count) { Set-SaveName $null }
        if ($fail.Count) { Show-Notice ('Удалено не всё: ' + ($fail -join '; ')) 'warn' } else { Show-Notice '«Мои данные» отключены. Данные, вход в GitHub и токены удалены с этого компьютера.' }
    }

    # --- Снятие настроек: программы этого компьютера → временная папка → просмотр изменений → «Мои данные» ---
    $capItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $capTimer = New-Object Windows.Threading.DispatcherTimer
    $capTimer.Interval = [TimeSpan]::FromMilliseconds(250)

    function Set-CaptureCard ([string]$Title, [string]$Text, [string]$Btn, [int]$Glyph = 0xE946) {
        $ctl.CaptureCard.Visibility = if ($Title) { 'Visible' } else { 'Collapsed' }
        $ctl.CaptureList.Visibility = if ($Title) { 'Collapsed' } else { 'Visible' }
        $ctl.CaptureCardTitle.Text = $Title; $ctl.CaptureCardText.Text = $Text
        $ctl.CaptureCardIcon.Text = [string][char]$Glyph
        $ctl.CaptureCardBtn.Content = $Btn
        $ctl.CaptureCardBtn.Visibility = if ($Btn) { 'Visible' } else { 'Collapsed' }
    }

    function Update-CaptureSummary {
        if ($ui.CaptureJob) { return }
        $n = @($capItems | Where-Object { $_.IsChecked }).Count
        $ctl.CaptureBtn.IsEnabled = $n -gt 0 -and (Test-PbDataConnected)
        $ctl.CaptureBtn.Content = if ($n) { "Снять выбранное ($n)" } else { 'Снять выбранное' }
    }

    # список: только программы, чьи настройки есть на этом компьютере; отметки переживают обновление
    function Update-Capture {
        $was = @($capItems | Where-Object { $_.IsChecked } | ForEach-Object { $_.Id })
        $capItems.Clear()
        $all = @(Get-PbCaptureApps $appList)
        $here = @($all | Where-Object { $_.Installed })
        $miss = @($all | Where-Object { -not $_.Installed } | ForEach-Object { $_.App.Name })
        $ctl.CaptureHint.Text = "Настройки программ этого компьютера сохраняются в «Моих данных» и применяются на других компьютерах при установке «с моими настройками». Найдено на этом компьютере: $($here.Count) из $($all.Count)." +
            $(if ($miss.Count) { " Не найдены: $($miss -join ', ')." })
        if (-not (Test-PbDataConnected)) {
            Set-CaptureCard 'Подключите «Мои данные», чтобы сохранять настройки' 'Снятые настройки хранятся в приватном репозитории «Моих данных» на GitHub и доступны на всех компьютерах.' $(if ($ui.Job -and $ui.Job.Action -eq 'connect') { '' } else { 'Подключить «Мои данные»' }) 0xE72E
            Update-CaptureSummary; return
        }
        if (Test-PbDataReadOnly) { Set-CaptureCard 'Обновите Tabula Rasa' 'Разметка «Моих данных» создана более новой версией программы. Пока программа не обновлена, настройки не сохраняются.' '' 0xE7BA; Update-CaptureSummary; return }
        if (-not $here.Count) { Set-CaptureCard 'Нет программ для снятия настроек' 'На этом компьютере не найдены настройки программ, которые поддерживают снятие.' ''; Update-CaptureSummary; return }
        Set-CaptureCard '' '' ''
        foreach ($c in $here) {
            $a = $c.App
            $it = New-Object PcBase.Item
            $it.Key = 'cap:' + $a.Id; $it.Kind = 'capture'; $it.Id = $a.Id; $it.Name = $a.Name
            $it.Facts.Add((New-Fact 'Снимается' $a.Config.Desc))
            $it.Facts.Add((New-Fact 'Не снимается' "$($a.Config.Skip) Строки и ключи, похожие на пароли, токены и ключи, вырезаются; перед записью показываются изменения."))
            $it.Facts.Add((New-Fact 'На этом компьютере' (Get-PbConfigSource $a.Config) 'mono'))
            $rel = 'configs\' + ($a.Config.File -replace '\\.*$', '')
            $it.Facts.Add((New-Fact 'В «Моих данных»' $rel 'mono'))
            $last = Get-PbDataLastChange $rel
            $lastText = if ($last -and $last.Date) { $last.Date.ToLocalTime().ToString('dd.MM.yyyy HH:mm') + $(if ($last.Machine) { ", компьютер $($last.Machine)" }) } else { 'ещё не снимались' }
            $it.Facts.Add((New-Fact 'Последнее снятие' $lastText))
            $it.Desc = "$($a.Config.Desc) Последнее снятие: $lastText."
            $it.IsChecked = $was -contains $a.Id
            $it.add_PropertyChanged({ Update-CaptureSummary })
            $capItems.Add($it)
        }
        Update-CaptureSummary
    }

    function Start-Capture {
        if ($ui.CaptureJob -or (Test-DataBusy)) { return }
        if (Test-PbDataReadOnly) { Update-Capture; return }
        $ids = @($capItems | Where-Object { $_.IsChecked } | ForEach-Object { $_.Id })
        $sel = @($appList | Where-Object { $ids -contains $_.Id })
        if (-not $sel.Count) { return }
        $stage = Join-Path $env:TEMP "tabula-rasa\capture\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root, $Apps, $Stage)
            . (Join-Path $Root 'lib\common.ps1'); . (Join-Path $Root 'lib\configs.ps1')
            Invoke-PbCapture $Apps $Stage
        })
        foreach ($a in @($script:PB.Root, $sel, $stage)) { [void]$ps.AddArgument($a) }
        $ui.CaptureJob = @{ Ps = $ps; Handle = $ps.BeginInvoke(); Stage = $stage }
        $ctl.CaptureBtn.IsEnabled = $false; $ctl.CaptureBtn.Content = 'Снятие…'
        $ctl.CaptureSummary.Text = 'Снятие настроек во временную папку…'
        $capTimer.Start()
    }

    # что изменится → подтверждение → копия в DataRoot\configs, коммит «Настройки: … (компьютер)», отправка в фоне
    function Complete-Capture ($Results, [string]$Stage) {
        $target = Join-Path $script:PB.DataRoot 'configs'
        $lines = @(); $changed = @(); $names = @()
        foreach ($r in @($Results)) {
            if ($r.Error) { $lines += @{ Text = "$($r.Name): $($r.Error)"; Tone = 'danger' }; continue }
            $ch = @(Compare-PbCapture $Stage $r.Files $target | Where-Object { $_.State -ne 'same' })
            if (-not $ch.Count) { $lines += "$($r.Name): без изменений"; continue }
            $names += $r.Name; $changed += @($ch | ForEach-Object { $_.Rel })
            $lines += @{ Text = $r.Name; Tone = 'strong'; Gap = $true }
            foreach ($c in @($ch | Select-Object -First 5)) {
                $lines += "• configs\$($c.Rel): $(if ($c.State -eq 'new') { "новый файл, строк: $($c.Added)" } else { "изменён, +$($c.Added) −$($c.Deleted)" })"
            }
            if ($ch.Count -gt 5) { $lines += "• и ещё файлов: $($ch.Count - 5)" }
            if ($r.Removed.Count) {
                $lines += @{ Text = "Вырезано как секреты: $($r.Removed.Count) ($(@($r.Removed | Select-Object -First 4) -join ', ')$(if ($r.Removed.Count -gt 4) { ', …' }))."; Tone = 'muted' }
            }
        }
        try {
            if (-not $changed.Count) {
                [void](Show-UiMessage -Owner $win -Title 'Изменений нет' -Lines (@($lines) + @{ Text = 'Снятые настройки совпадают с сохранёнными в «Моих данных».'; Tone = 'muted'; Gap = $true }))
                $ctl.CaptureSummary.Text = 'Изменений нет.'
                return
            }
            $ok = Show-UiMessage -Owner $win -Title 'Сохранить настройки в «Мои данные»?' -Primary 'Сохранить' -Secondary 'Отмена' -Lines (@($lines) +
                @{ Text = "Изменения будут зафиксированы коммитом «Настройки: $($names -join ', ') ($env:COMPUTERNAME)» и отправлены в GitHub."; Tone = 'muted'; Gap = $true })
            if (-not $ok) { $ctl.CaptureSummary.Text = 'Снятие отменено, «Мои данные» не изменены.'; return }
            Copy-PbCapture $Stage $changed $target
            Save-PbConfigCommit $names
            $ctl.CaptureSummary.Text = "Сохранено: $($names -join ', '). Отправка в GitHub…"
            Start-DataJob 'push'
            Update-ConfigAvail
        } catch {
            [void](Show-UiMessage -Owner $win -Title 'Не удалось сохранить настройки' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' }))
        } finally {
            Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
            Update-Capture
        }
    }

    $capTimer.add_Tick({
        $j = $ui.CaptureJob
        if (-not $j -or -not $j.Handle.IsCompleted) { return }
        $capTimer.Stop()
        $res = $null; $err = $null
        try { $res = @($j.Ps.EndInvoke($j.Handle) | ForEach-Object { $_.PSObject.BaseObject }) }
        catch { $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        $j.Ps.Dispose(); $ui.CaptureJob = $null
        if ($err) {
            Remove-Item $j.Stage -Recurse -Force -ErrorAction SilentlyContinue
            [void](Show-UiMessage -Owner $win -Title 'Не удалось снять настройки' -Lines @(@{ Text = $err; Tone = 'muted' }))
            Update-Capture; return
        }
        Complete-Capture $res $j.Stage
    })

    $ctl.CaptureList.ItemsSource = $capItems
    $ctl.CaptureList.add_SelectionChanged({
        $it = $ctl.CaptureList.SelectedItem
        $ctl.CaptureDetail.DataContext = $it
        $ctl.CaptureDetail.Visibility = if ($it) { 'Visible' } else { 'Collapsed' }
        $ctl.CaptureDetailHint.Visibility = if ($it) { 'Collapsed' } else { 'Visible' }
    })
    $ctl.CaptureList.add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'Space' -and $ctl.CaptureList.SelectedItem) { $ctl.CaptureList.SelectedItem.IsChecked = -not $ctl.CaptureList.SelectedItem.IsChecked; $e.Handled = $true }
    })
    $ctl.CaptureBtn.add_Click({ Start-Capture })
    $ctl.CaptureCardBtn.add_Click({ if (-not $ui.Job -and -not (Test-PbDataConnected)) { Connect-Data } })

    # режим окна: установка или снятие настроек; выбор в одном режиме не сбрасывает другой
    function Set-WinMode ([string]$Mode) {
        $cap = $Mode -eq 'capture'
        $ctl.InstallPane.Visibility = if ($cap) { 'Collapsed' } else { 'Visible' }
        $ctl.InstallBar.Visibility = if ($cap) { 'Collapsed' } else { 'Visible' }
        $ctl.CapturePane.Visibility = if ($cap) { 'Visible' } else { 'Collapsed' }
        foreach ($c in $ctl.SearchBox, $ctl.AddAppBtn, $ctl.SetBtn) { $c.Visibility = if ($cap) { 'Hidden' } else { 'Visible' } }
        if ($cap) { Update-Capture }
    }
    $ctl.TabInstall.add_Checked({ Set-WinMode 'install' })
    $ctl.TabCapture.add_Checked({ Set-WinMode 'capture' })

    # --- собственный каталог: добавить из winget, удалить ---
    function Get-BuiltinIds { @($appList | Where-Object { -not $_.Mine } | ForEach-Object { $_.Id }) }

    # пункт и, если нужно, новая категория в навигации — перед разделом настроек Windows
    function Add-AppToView ($A) {
        $ck = 'apps|' + $A.Category
        if (-not $cats.Contains($ck)) {
            $e = New-Object PcBase.NavEntry
            $e.Kind = 'cat'; $e.Section = 'apps'; $e.Name = $A.Category; $e.Key = $ck; $e.Icon = Get-CatIcon $A.Category
            $idx = 0
            for ($i = 0; $i -lt $nav.Count; $i++) { if ($nav[$i].Kind -eq 'header' -and $nav[$i].Section -eq 'tweaks') { $idx = $i; break } }
            $nav.Insert($idx, $e); $cats[$ck] = $e
        }
        $it = New-AppItem $A $ck $A.Category
        $it.add_PropertyChanged($onChange)
        $items.Add($it)
        Update-Counts
        Select-Nav $cats[$ck]
        $ctl.List.SelectedItem = $it; $ctl.List.ScrollIntoView($it)
    }

    function Add-MyApp {
        if (-not (Test-PbDataConnected)) {
            $ok = Show-UiMessage -Owner $win -Title 'Подключите «Мои данные»' -Primary 'Подключить' -Secondary 'Отмена' -Lines @(
                'Собственный каталог программ хранится в «Моих данных» и доступен на всех компьютерах. Чтобы добавлять программы, подключите «Мои данные».')
            if ($ok -and -not $ui.Job) { Connect-Data }
            return
        }
        if (Test-PbDataReadOnly) { [void](Show-UiMessage -Owner $win -Title 'Обновите Tabula Rasa' -Lines @('Разметка «Моих данных» создана более новой версией программы. Пока программа не обновлена, каталог не изменяется.')); return }
        if (Test-DataBusy) { return }
        $known = @{}
        foreach ($a in $appList) { if ($a.WingetId) { $known[$a.WingetId.ToLower()] = $a.Name } }
        $catNames = @($appList | ForEach-Object { $_.Category } | Select-Object -Unique)
        $r = Show-AddAppDialog -Owner $win -Known $known -Categories $catNames
        if (-not $r) { return }
        $entry = @{ Id = (New-PbUserAppId $r.WingetId @($appList | ForEach-Object { $_.Id })); Name = $r.Name; Desc = $r.Desc
                    Category = $(if ($r.Category) { $r.Category } else { $script:PbUserCategory }); Source = 'winget'; WingetId = $r.WingetId }
        try { Add-PbUserApp $entry (Get-BuiltinIds) }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось добавить программу' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        $entry.Mine = $true
        [void]$appList.Add($entry)
        Add-AppToView $entry
        Show-Notice "Добавлено в собственный каталог: $($entry.Name). Отправка в GitHub…"
        Start-DataJob 'push'
    }

    function Remove-MyApp ($It) {
        if (-not $It -or -not $It.IsMine -or (Test-DataBusy)) { return }
        if (-not (Show-UiMessage -Owner $win -Title "Удалить «$($It.Name)» из моего каталога?" -Primary 'Удалить' -Secondary 'Назад' -SafeDefault -Lines @(
            'Программа будет удалена из собственного каталога на всех компьютерах. С этого компьютера программа не удаляется.'))) { return }
        try { Remove-PbUserApp $It.Id (Get-BuiltinIds) }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалось удалить программу из каталога' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        $a = @($appList | Where-Object { $_.Id -eq $It.Id }) | Select-Object -First 1
        if ($a) { $appList.Remove($a) }
        $ck = $It.CatKey
        [void]$items.Remove($It)
        if (-not @($items | Where-Object { $_.CatKey -eq $ck }).Count -and $cats.Contains($ck)) {
            [void]$nav.Remove($cats[$ck]); $cats.Remove($ck)
            if ($ui.Cat -eq $ck) { Select-Nav $first['apps'] }
        }
        Update-Counts; Update-View
        Show-Notice "«$($It.Name)» удалена из собственного каталога. Отправка в GitHub…"
        Start-DataJob 'push'
    }
    $ctl.AddAppBtn.add_Click({ Add-MyApp })
    $ctl.RemoveMine.add_Click({ Remove-MyApp $ctl.Detail.DataContext })


    # --- события ---
    $onChange = {
        param($s, $e)
        if ($ui.Bulk) { return }
        if ($e.PropertyName -eq 'IsPicked' -and -not $ui.InDeps -and $s.Kind -in 'app', 'tweak') {
            # отметил сам — уже не «автоматически»; зависимости пересчитываются
            if ($s.IsChecked -and $s.CanToggle) { $s.AutoAdded = $false }
            Update-Deps $s
        }
        if ($e.PropertyName -in 'IsChecked', 'ConfigOn', 'IsPicked') { Update-Counts }
    }
    foreach ($it in $items) { $it.add_PropertyChanged($onChange) }

    $onNav = {
        param($s)
        if ($ui.Busy) { return }
        $e = $s.SelectedItem
        if (-not $e -or ($e.Kind -ne 'cat' -and $e.Kind -ne 'summary')) { return }
        Set-NavMark $e
        $pick = $null
        if ($ui.Mode -eq 'search') {
            # из поиска — в категорию: поиск сбрасывается, выделяется первое совпадение в ней
            foreach ($it in $items) { if ($it.CatKey -eq $e.Key -and (Test-Search $it)) { $pick = $it; break } }
            $ui.Busy = $true; $ctl.Search.Text = ''; $ui.Busy = $false
            $ui.Words = @()
        }
        Open-Nav $e
        if ($pick) { $ctl.List.SelectedItem = $pick; $ctl.List.ScrollIntoView($pick) }
    }
    $ctl.Nav.add_SelectionChanged($onNav)
    $ctl.NavBottom.add_SelectionChanged($onNav)

    $ctl.Search.add_TextChanged({
        $ctl.SearchClear.Visibility = if ($ctl.Search.Text) { 'Visible' } else { 'Collapsed' }
        $ctl.SearchKey.Visibility = if ($ctl.Search.Text) { 'Collapsed' } else { 'Visible' }
        if ($ui.Busy) { return }
        $f = $ctl.Search.Text.Trim()
        if ($f) {
            $ui.Words = @($f -split '\s+' | Where-Object { $_ })
            if ($ui.Mode -ne 'search') { $ui.Mode = 'search'; Set-NavMark $null }
        } elseif ($ui.Mode -eq 'search') {
            $ui.Words = @()
            $ui.Mode = if ($ui.Nav.Kind -eq 'summary') { 'summary' } else { 'cat' }
            Set-NavMark $ui.Nav
        }
        Update-NavHits
        Update-View
    })
    $ctl.SearchClear.add_Click({ $ctl.Search.Text = ''; [void]$ctl.Search.Focus() })

    $ctl.List.add_SelectionChanged({
        $it = $ctl.List.SelectedItem
        if ($it) {
            $ctl.Detail.DataContext = $it
            $ctl.Detail.Visibility = 'Visible'; $ctl.DetailHint.Visibility = 'Collapsed'
        } else {
            $ctl.Detail.Visibility = 'Collapsed'; $ctl.DetailHint.Visibility = 'Visible'
        }
    })
    # значок ⚙ в карточке переключает вариант установки
    $ctl.List.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $b = $e.OriginalSource
        if ($b -is [Windows.Controls.Button] -and $b.Tag -eq 'cfg') {
            $it = $b.DataContext
            if (-not $it.ConfigAvailable) { $ctl.List.SelectedItem = $it; $e.Handled = $true; return }
            $it.ConfigOn = -not $it.ConfigOn
            $ctl.List.SelectedItem = $it
            $e.Handled = $true
        }
    })
    $ctl.List.add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'Space' -and $ctl.List.SelectedItem) {
            $ctl.List.SelectedItem.IsChecked = -not $ctl.List.SelectedItem.IsChecked
            $e.Handled = $true
        }
    })

    # «Выбрать всё»: все отмечены — снять всё, иначе — отметить всё (вариант «с моими настройками» не включается)
    $ctl.CatCheck.add_Click({
        $list = @($items | Where-Object { $_.CatKey -eq $ui.Cat -and (Test-StatusFilter $_) })
        $all = $list.Count -and -not @($list | Where-Object { -not $_.IsChecked }).Count
        Set-Checked $list (-not $all)
        Update-CatCheck
    })
    $ctl.FilterMissing.add_Click({ Update-View; Update-NavHits })
    $ctl.FilterUpdates.add_Click({ Update-View; Update-NavHits })
    $ctl.MarkUpdates.add_Click({
        $up = @($items | Where-Object { $_.Kind -eq 'app' -and $_.StatusKind -eq 'update' })
        $ui.Bulk = $true
        foreach ($it in $up) { $it.Action = 'update' }
        $ui.Bulk = $false
        Update-Counts
        Show-Notice "Отмечено обновлений: $($up.Count). Программы будут обновлены через winget."
    })

    $ctl.SetBtn.add_ContextMenuOpening({ Fill-SaveMenu })
    $ctl.SetBtn.add_Click({
        Fill-SaveMenu
        $ctl.SetBtn.ContextMenu.PlacementTarget = $ctl.SetBtn
        $ctl.SetBtn.ContextMenu.IsOpen = $true
    })
    $ctl.SetBtn.ContextMenu.AddHandler([Windows.Controls.MenuItem]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $tag = [string]$e.Source.Tag
        if (-not $tag) { return }
        if ($tag -eq '?save') { Save-Current }
        elseif ($tag -eq '?open') {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'Сохранение Tabula Rasa (*.json)|*.json'
            $d = Get-PbSaveDir; if (Test-Path $d) { $dlg.InitialDirectory = $d }
            if ($dlg.ShowDialog($win)) { Import-Save $dlg.FileName }
        } else { Import-Save $tag }
    })
    # значки «переименовать» / «удалить» внутри пункта меню
    $ctl.SetBtn.ContextMenu.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $tag = [string]$e.OriginalSource.Tag
        if ($tag -notmatch '^\?(ren|del)\|(.+)$') { return }
        $e.Handled = $true
        $act = $Matches[1]; $path = $Matches[2]
        $ctl.SetBtn.ContextMenu.IsOpen = $false
        if ($act -eq 'ren') { Rename-Save $path } else { Remove-Save $path }
    })
    $ctl.SaveBtn.add_Click({ Save-Current })
    $ctl.NoticeClose.add_Click({ $ctl.Notice.Visibility = 'Collapsed' })

    $ctl.DataBtn.add_Click({
        if ($ui.Job -and $ui.Job.Action -eq 'connect') {
            if ($ui.Job.Sync.Pid) { Stop-Process -Id $ui.Job.Sync.Pid -Force -ErrorAction SilentlyContinue }
            return
        }
        if (-not (Test-PbDataConnected)) { Connect-Data; return }
        $m = $ctl.DataBtn.ContextMenu
        $m.Items.Clear()
        $st = Get-PbDataState
        $acts = @()
        if ($st.Pending) { $acts += , @("Отправить сейчас (не отправлено: $($st.Pending))", 'push') } else { $acts += , @('Обновить из GitHub', 'push') }
        $acts += , @("Открыть папку $($script:PB.DataRoot)", 'open')
        if ($st.Repo) { $acts += , @("Открыть репозиторий $($st.Repo) на GitHub", 'web') }
        $acts += , @('Отключить и удалить с этого компьютера…', 'erase')
        foreach ($p in $acts) { $mi = New-Object Windows.Controls.MenuItem; $mi.Header = $p[0]; $mi.Tag = $p[1]; [void]$m.Items.Add($mi) }
        $m.PlacementTarget = $ctl.DataBtn
        $m.IsOpen = $true
    })
    $ctl.DataBtn.ContextMenu.AddHandler([Windows.Controls.MenuItem]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        switch ([string]$e.Source.Tag) {
            'push'  { Show-Notice 'Синхронизация с GitHub…'; Start-DataJob 'push' }
            'open'  { Start-Process explorer.exe $script:PB.DataRoot }
            'web'   { $r = Get-PbDataRepo; if ($r) { Start-Process "https://github.com/$r" } }
            'erase' { Disconnect-Data }
        }
    })
    $ctl.DataOpen.add_Click({ if ($ui.Job -and $ui.Job.Sync.Url) { Start-Process $ui.Job.Sync.Url } })

    # перетащил .json на окно — открыть как сохранение
    $win.AllowDrop = $true
    $win.add_PreviewDragOver({
        param($s, $e)
        $f = @($e.Data.GetData([Windows.DataFormats]::FileDrop))
        $e.Effects = if ($f.Count -eq 1 -and $f[0] -like '*.json') { 'Copy' } else { 'None' }
        $e.Handled = $true
    })
    $win.add_PreviewDrop({
        param($s, $e)
        $f = @($e.Data.GetData([Windows.DataFormats]::FileDrop))
        if ($f.Count -eq 1 -and $f[0] -like '*.json') { $e.Handled = $true; Import-Save $f[0] }
    })
    $win.add_Closed({
        if ($ui.Job -and $ui.Job.Sync.Pid) { Stop-Process -Id $ui.Job.Sync.Pid -Force -ErrorAction SilentlyContinue }
        $filesTimer.Stop(); $capTimer.Stop(); $statusTimer.Stop(); $themeTimer.Stop(); $engineTimer.Stop(); $runTimer.Stop()
        if ($ui.StatusJob -and -not $ui.StatusJob.Handle.IsCompleted) { try { [void]$ui.StatusJob.Ps.BeginStop($null, $null) } catch { } }
        Save-UiState $win $(if ($ui.Nav) { $ui.Nav.Key } else { '' })
        if ($ui.FilesJob) { try { [void]$ui.FilesJob.Ps.BeginStop($null, $null) } catch { } }   # не ждать сеть при закрытии
    })

    # в домене имя не трогаем (Rename-Computer требует доменную учётку) — вместо поля просто текст
    if ($IsDomain) {
        $ctl.PcNameCur.Text = $env:COMPUTERNAME
        $ctl.PcNameFixed.Visibility = 'Visible'
        $ctl.PcNameLabel.Visibility = 'Collapsed'; $ctl.PcName.Visibility = 'Collapsed'
    }
    $ctl.PcName.add_TextChanged({ $ctl.PcName.ClearValue([Windows.Controls.Control]::BorderBrushProperty) })


    # --- статус программ и твиков: фоновая проверка при старте (lib\status.ps1), окно не ждёт ---
    $statusTimer = New-Object Windows.Threading.DispatcherTimer
    $statusTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $ui.Status = @{ Apps = @{}; Tweaks = @{} }
    $ui.IconTried = @{}

    function Set-ItemStatuses {
        $s = $ui.StatusJob.Sync
        if ($s.Apps) {
            foreach ($it in $items) {
                if ($it.Kind -ne 'app' -or -not $s.Apps.ContainsKey($it.Id)) { continue }
                $st = $s.Apps[$it.Id]
                if ($it.StatusKind -ne $st.Kind -or $it.StatusText -ne $st.Text) { $it.StatusKind = $st.Kind; $it.StatusText = $st.Text }
                # Э7: установленная — отмечена и заблокирована; не установлена — снова свободна; unknown — как было
                $ui.InDeps = $true   # блокировка по статусу — не действие пользователя: зависимости не трогаются
                if ($st.Kind -in 'installed', 'update') { $it.IsLocked = $true } elseif ($st.Kind -eq 'missing') { $it.IsLocked = $false }
                $ui.InDeps = $false
                if ($st.Icon -and -not $it.IconSource -and -not $ui.IconTried[$it.Id]) { $ui.IconTried[$it.Id] = $true; $it.IconSource = Get-ExeIcon $st.Icon }
            }
            $ui.Status.Apps = $s.Apps
        }
        if ($s.Tweaks) {
            foreach ($it in $items) {
                if ($it.Kind -ne 'tweak' -or -not $s.Tweaks.ContainsKey($it.Id)) { continue }
                $k = $s.Tweaks[$it.Id]
                $it.StatusKind = $k; $it.StatusText = $script:PbTweakStatusText[$k]
            }
            $ui.Status.Tweaks = $s.Tweaks
        }
        $up = @($items | Where-Object { $_.Kind -eq 'app' -and $_.StatusKind -eq 'update' }).Count
        $ctl.MarkUpdates.Content = "Отметить обновления ($up)"
        $ctl.MarkUpdates.Visibility = if ($up) { 'Visible' } else { 'Collapsed' }
        Update-NeededBy
    }

    function Start-StatusJob {
        if ($ui.StatusJob) { return }
        $sync = [hashtable]::Synchronized(@{ Apps = $null; Tweaks = $null; WingetError = $null; Done = $false })
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root, $Apps, $Os, $Sync)
            . (Join-Path $Root 'lib\common.ps1'); . (Join-Path $Root 'lib\catalog.ps1'); . (Join-Path $Root 'lib\status.ps1')
            $script:PB.Root = $Root; $script:PB.Os = $Os
            Update-SessionPath
            . (Join-Path $Root 'catalog\tweaks.ps1')   # скриптблоки твиков — свои, этого runspace
            $tw = @($Tweaks | Where-Object { $_.Os -contains $Os })
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { $Sync.WingetError = 'winget не найден' }
            Start-PbStatusScan $Apps $tw $Sync
        })
        # программы — только данные (без скриптблоков); значки — по DisplayIcon
        $data = @($appList | ForEach-Object { @{ Id = $_.Id; Name = $_.Name; WingetId = $_.WingetId; Source = $_.Source; Detect = $_.Detect } })
        foreach ($a in @($script:PB.Root, $data, $script:PB.Os, $sync)) { [void]$ps.AddArgument($a) }
        $ui.StatusJob = @{ Ps = $ps; Handle = $ps.BeginInvoke(); Sync = $sync }
        $ctl.StatusScan.Text = 'Проверка установленных программ…'
        $statusTimer.Start()
    }

    $statusTimer.add_Tick({
        $j = $ui.StatusJob
        if (-not $j) { $statusTimer.Stop(); return }
        Set-ItemStatuses
        if (-not $j.Handle.IsCompleted) { return }
        $statusTimer.Stop()
        try { [void]$j.Ps.EndInvoke($j.Handle) } catch { $j.Sync.WingetError = $_.Exception.Message }
        $j.Ps.Dispose()
        Set-ItemStatuses
        $appItems = @($items | Where-Object { $_.Kind -eq 'app' })
        $inst = @($appItems | Where-Object { $_.StatusKind -in 'installed', 'update' }).Count
        $up = @($appItems | Where-Object { $_.StatusKind -eq 'update' }).Count
        $ctl.StatusScan.Text = if ($j.Sync.WingetError) { "Установлено: $inst. Обновления не проверены: $($j.Sync.WingetError)." } else { "Установлено: $inst из $($appItems.Count), обновлений: $up." }
        Update-View
    })

    # --- план, прогон, итог — экран RunPane ---
    $runSteps = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $runView = [Windows.Data.CollectionViewSource]::GetDefaultView($runSteps)
    $runView.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'PhaseName'))
    $ctl.RunList.ItemsSource = $runSteps
    $manualItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $ctl.ManualList.ItemsSource = $manualItems
    $runTimer = New-Object Windows.Threading.DispatcherTimer
    $runTimer.Interval = [TimeSpan]::FromMilliseconds(300)

    function Set-RunButtons ([string]$State) {
        $vis = @{ RunBack = @('plan', 'done'); RunApply = @('plan'); RunSkip = @('run'); RunStop = @('run'); RunRetry = @(); RunOpenLog = @('run')
                  RunOpenReport = @('done'); RunMore = @('done'); RunReboot = @('done'); RunClose = @('done') }
        foreach ($k in $vis.Keys) { $ctl[$k].Visibility = if ($vis[$k] -contains $State) { 'Visible' } else { 'Collapsed' } }
        # журнал — только во время прогона и в итоге; на экране плана он пуст
        $ctl.LogToggle.Visibility = if ($State -eq 'plan') { 'Collapsed' } else { 'Visible' }
        # на экране плана колонки журнала нет: шаги — на всю ширину
        $ctl.RunSideCol.Width = if ($State -eq 'plan') { New-Object Windows.GridLength 0 } else { New-Object Windows.GridLength 360 }
        $ctl.RunSide.Visibility = if ($State -eq 'plan') { 'Collapsed' } else { 'Visible' }
        if ($State -eq 'plan') { $ctl.RunLog.Visibility = 'Collapsed'; $ctl.LogToggle.Content = 'Показать журнал' }
        # во время прогона выбор и режимы не трогаются
        foreach ($c in $ctl.TabInstall, $ctl.TabCapture, $ctl.SearchBox, $ctl.AddAppBtn, $ctl.SetBtn, $ctl.MoreBtn) { $c.IsEnabled = $State -ne 'run' }
        # прогон ждёт перезагрузки (Э9): новый прогон до неё смешал бы два — назад к выбору нельзя, пока не отказались от продолжения
        if ($State -eq 'done' -and $ui.ResumePending) { $ctl.RunBack.Visibility = 'Collapsed' }
    }

    function Show-Pane ([string]$Which) {
        $run = $Which -eq 'run'
        $ctl.RunPane.Visibility = if ($run) { 'Visible' } else { 'Collapsed' }
        # «Установка | Снятие настроек» — только при выборе: переключение с экрана плана или прогона ломало окно
        $ctl.TabSwitch.Visibility = if ($run) { 'Hidden' } else { 'Visible' }
        # поиск, «Программа» и «Профили» к плану и прогону не относятся — на этих экранах их нет
        foreach ($c in $ctl.SearchBox, $ctl.AddAppBtn, $ctl.SetBtn) { $c.Visibility = if ($run) { 'Collapsed' } else { 'Visible' } }
        $ctl.InstallPane.Visibility = if (-not $run -and -not $ctl.TabCapture.IsChecked) { 'Visible' } else { 'Collapsed' }
        $ctl.InstallBar.Visibility = $ctl.InstallPane.Visibility
        $ctl.CapturePane.Visibility = if (-not $run -and $ctl.TabCapture.IsChecked) { 'Visible' } else { 'Collapsed' }
    }

    function Set-RunSteps ($Plan) {
        $runSteps.Clear()
        foreach ($p in $Plan) {
            $r = New-Object PcBase.RunStep
            $r.Key = $p.Key; $r.PhaseName = $p.PhaseName; $r.Name = $p.Name; $r.Note = $p.Note; $r.Irreversible = [bool]$p.Irreversible
            $r.State = $p.State; $r.Detail = $p.Detail
            $runSteps.Add($r)
        }
    }

    # проверка имени и пустого выбора; @{ Sel; Name } или $null
    function Get-RunChoice {
        $name = if ($IsDomain) { '' } else { $ctl.PcName.Text.Trim() }
        if ($name -and ($name -notmatch '^[A-Za-z0-9-]{1,15}$' -or $name -match '^\d+$')) {
            $ctl.PcName.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Danger')
            [void](Show-UiMessage -Owner $win -Title 'Недопустимое имя компьютера' -Lines @('Допустимы латинские буквы, цифры и дефис, не более 15 символов; имя не может состоять только из цифр. Оставьте поле пустым, чтобы не менять имя.'))
            [void]$ctl.PcName.Focus()
            return $null
        }
        $c = Get-Chosen
        if (-not $c.Apps.Count -and -not $c.Tweaks.Count -and -not $c.Files.Count -and -not $c.Configs.Count -and -not @($c.Remove).Count -and -not $name) {
            [void](Show-UiMessage -Owner $win -Title 'Ничего не выбрано' -Lines @('Отметьте хотя бы одну программу, настройку или файл либо укажите новое имя компьютера.'))
            return $null
        }
        $c.Name = if ($name) { $name.ToUpper() } else { $null }
        $c.FileTitles = @($c.Files | ForEach-Object { $f = $_; $t = @($items | Where-Object { $_.Kind -eq 'file' -and $_.Id -eq $f } | ForEach-Object { $_.Name }); if ($t) { $t[0] } else { $f } })
        return $c
    }

    # подтверждение перед применением: счётчики, список необратимого, имя компьютера
    function Confirm-Apply ($C) {
        $irr = @($Tweaks | Where-Object { $_.Irreversible -and $C.Tweaks -contains $_.Id } | ForEach-Object { $_.Name })
        $irr += @($appList | Where-Object { @($C.Remove) -contains $_.Id } | ForEach-Object { "Удалить программу $($_.Name)" })
        $lines = @("Программ: $($C.Apps.Count)$(if ($C.Upgrades.Count) { ", из них обновлений: $($C.Upgrades.Count)" })$(if (@($C.Reinstall).Count) { ", переустановок: $(@($C.Reinstall).Count)" })$(if ($C.Configs.Count) { ", с моими настройками: $($C.Configs.Count)" })$(if (@($C.Remove).Count) { ", удалить: $(@($C.Remove).Count)" })",
            "Настроек Windows: $($C.Tweaks.Count)")
        if ($irr.Count) {
            $lines += @{ Text = "Необратимые изменения ($($irr.Count)). Они не отменяются через undo.ps1, только точкой восстановления:"; Tone = 'danger'; Gap = $true }
            $lines += @{ Text = (($irr | ForEach-Object { "• $_" }) -join "`n"); Tone = 'danger' }
            $lines += @{ Text = 'Если точку восстановления создать не удастся (защита системы отключена политикой), перед ними будет задан вопрос.'; Tone = 'muted' }
        }
        if ($C.Files.Count) { $lines += "Файлов: $($C.Files.Count) (загрузка в «Рабочий стол\tabula-rasa-files»)" }
        $lines += if ($C.Name) { "Имя компьютера: $env:COMPUTERNAME → $($C.Name)" } else { "Имя компьютера: $env:COMPUTERNAME (без изменений)" }
        $lines += @{ Text = 'Изменения будут применены сразу. Перед применением создаётся точка восстановления; отмена — «⋯ → Откат изменений» или undo.ps1.'; Tone = 'muted'; Gap = $true }
        return (Show-UiMessage -Owner $win -Title "Применить к $($env:COMPUTERNAME)?" -Lines $lines -Primary 'Применить' -Secondary 'Назад' -SafeDefault)
    }

    # Э9: перезагрузки посреди прогона ожидаются — предупредить и предложить временный автоматический вход.
    # Не ожидаются — ничего не спрашивается. $false — вернуться к плану, прогон не начинается
    function Confirm-Reboots ($C) {
        $fc = @(Get-PbRebootForecast (Get-PbRunPlan $C $appList $Tweaks $ui.Status) $appList $Tweaks)
        if (-not $fc.Count) { return $true }
        $head = 'Компьютер будет перезагружен'
        $lines = @("Во время прогона потребуется перезагрузка: $($fc -join '; '). После неё прогон продолжится с того же места.",
            @{ Text = 'Перед перезагрузкой окно 60 секунд показывает обратный отсчёт; перезагрузку можно отменить. Несохранённые данные в других программах будут потеряны.'; Tone = 'muted' })
        $sup = Get-PbAutoLogonSupport
        if ($sup.Already) {
            $lines += @{ Text = 'На компьютере настроен автоматический вход: после перезагрузки прогон продолжится без участия пользователя.'; Gap = $true }
            return (Show-UiMessage -Owner $win -Title $head -Lines $lines -Primary 'Продолжить' -Secondary 'Назад' -SafeDefault)
        }
        if (-not $sup.Ok) {
            $lines += @{ Text = "Автоматический вход недоступен. $($sup.Reason) После перезагрузки нужно войти в Windows, иначе прогон не продолжится."; Tone = 'strong'; Gap = $true }
            return (Show-UiMessage -Owner $win -Title $head -Lines $lines -Primary 'Продолжить' -Secondary 'Назад' -SafeDefault)
        }
        $lines += @{ Text = 'Чтобы прогон продолжился без вас, Tabula Rasa может на время прогона входить в Windows автоматически. Для этого нужен пароль вашей учётной записи Windows.'; Gap = $true }
        $lines += @{ Text = 'Пароль проверяется и хранится в зашифрованном системном хранилище Windows (LSA), не в файлах и не в реестре. По окончании или отмене прогона он удаляется, параметры входа возвращаются к прежним, а компьютер блокируется.'; Tone = 'muted' }
        while ($true) {
            if (Show-UiMessage -Owner $win -Title $head -Lines $lines -Primary 'Входить автоматически…' -Secondary 'Входить вручную') {
                $sec = Read-UiPassword -Owner $win -Title 'Пароль Windows' -Lines @("Пароль учётной записи $env:USERDOMAIN\$env:USERNAME. Он используется только для входа после перезагрузок этого прогона.")
                if (-not $sec) { continue }
                try {
                    $rc = Test-PbLogonPassword $sec
                    if ($rc -ne 0) {
                        $why = switch ($rc) { 1326 { 'Пароль неверный.' } 1327 { 'Учётная запись без пароля или с ограничениями входа: автоматический вход для неё недоступен.' } default { "Windows не приняла пароль (код $rc)." } }
                        [void](Show-UiMessage -Owner $win -Title 'Пароль не подошёл' -Lines @($why))
                        continue
                    }
                    Enable-PbAutoLogon $sec
                } catch {
                    [void](Show-UiMessage -Owner $win -Title 'Автоматический вход не настроен' -Lines @("$($_.Exception.Message)", 'После перезагрузки нужно будет войти в Windows вручную.'))
                } finally { $sec.Dispose() }
                return $true
            }
            return (Show-UiMessage -Owner $win -Title 'Вход вручную' -Primary 'Продолжить' -Secondary 'Назад' -SafeDefault -Lines @(
                'После каждой перезагрузки нужно войти в Windows: прогон продолжится только после входа.',
                @{ Text = 'Если отойти от компьютера, он будет ждать на экране входа.'; Tone = 'muted' }))
        }
    }

    # план в окне: те же шаги, что выполнит прогон, с пометками «будет пропущено», «необратимо»
    function Show-Plan ($C) {
        $plan = Get-PbRunPlan $C $appList $Tweaks $ui.Status
        $ui.PlanSel = $C
        Set-RunSteps $plan
        $ctl.RunTitle.Text = 'План'
        $irr = @($plan | Where-Object { $_.Irreversible }).Count
        $skip = @($plan | Where-Object { $_.Note -match 'пропущено' }).Count
        $sum = Get-PbPlanSummary $plan
        $ctl.RunHint.Text = "Шагов: $($plan.Count)$(if ($skip) { ", будет пропущено: $skip" })$(if ($irr) { ", необратимых: $irr" })$(if ($sum) { "; $sum" }). Изменения пока не вносились."
        $ctl.RunProgress.Visibility = 'Collapsed'; $ctl.RunBanner.Visibility = 'Collapsed'; $ctl.ManualBox.Visibility = 'Collapsed'
        $ctl.RunStatus.Text = 'Чтобы выполнить план, нажмите «Применить…».'
        Set-RunButtons 'plan'
        Show-Pane 'run'
    }

    function Add-RunLog ([string]$Line) {
        $ctl.RunLog.AppendText($Line + "`r`n")
        $ctl.RunLog.ScrollToEnd()
        try { [IO.File]::AppendAllText($ui.RunLogFile, $Line + "`r`n", (New-Object Text.UTF8Encoding $false)) } catch { }
    }

    # прогон в фоновом runspace: каталог и твики загружаются там же (скриптблоки привязаны к своему runspace)
    # $Resume — незавершённый прогон (Э9): тот же Stamp, журналы дописываются, шаги восстанавливаются из состояния
    function Start-Run ($C, $Resume) {
        # у каждого прогона — свой журнал изменений; продолжение после перезагрузки — тот же прогон
        $stamp = if ($Resume) { [string]$Resume.Stamp } else { Get-Date -Format 'yyyy-MM-dd_HHmmss' }
        New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null
        $ui.RunLogFile = Join-Path $script:PB.LogDir "run_$stamp.log"
        $ui.RunStamp = $stamp
        $ui.ResumePending = $false
        $sync = [hashtable]::Synchronized(@{ Status = $ui.Status; Steps = $null; Current = $null; SkipCurrent = $false; StopAfter = $false
            Ask = $null; Answer = $null; Done = $false; NeedReboot = $false; Manual = @(); ResumePending = $false; Boots = 0 })
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root, $DataRoot, $LogDir, $Stamp, $Sel, $Sync, $Resume)
            foreach ($f in 'common', 'data', 'files', 'catalog', 'configs', 'status', 'run') { . (Join-Path $Root "lib\$f.ps1") }
            $script:PB.Root = $Root; $script:PB.DataRoot = $DataRoot; $script:PB.LogDir = $LogDir; $script:PB.Stamp = $Stamp
            Get-EnvInfo
            $Apps = (Import-PowerShellDataFile (Join-Path $Root 'catalog\apps.psd1')).Apps
            $Apps = @($Apps) + @((Read-PbUserCatalog @($Apps | ForEach-Object { $_.Id })).Apps)
            $Apps = @($Apps | Where-Object { -not $_.Os -or $_.Os -contains $script:PB.Os })
            . (Join-Path $Root 'catalog\tweaks.ps1')
            $Tweaks = @($Tweaks | Where-Object { $_.Os -contains $script:PB.Os })
            $plan = Get-PbRunPlan $Sel $Apps $Tweaks $Sync.Status
            if ($Resume) { Restore-PbResumeSteps $plan $Resume }
            $Sync.Steps = $plan
            Invoke-PbRun $plan $Sel $Apps $Tweaks $Sync $Resume
        })
        foreach ($a in @($script:PB.Root, $script:PB.DataRoot, $script:PB.LogDir, $stamp, $C, $sync, $Resume)) { [void]$ps.AddArgument($a) }
        $ui.Run = @{ Ps = $ps; Handle = $ps.BeginInvoke(); Sync = $sync; Sel = $C; LogPos = 0; Built = $false }
        $ctl.RunTitle.Text = if ($Resume) { 'Выполнение: продолжение после перезагрузки' } else { 'Выполнение' }
        $ctl.RunHint.Text = "Компьютер $env:COMPUTERNAME. Окно можно свернуть: по окончании кнопка на панели задач замигает."
        $ctl.RunLog.Clear(); $manualItems.Clear()
        # журнал до перезагрузки — в окне выше продолжения
        if ($Resume -and (Test-Path -LiteralPath $ui.RunLogFile)) { try { $ctl.RunLog.AppendText([IO.File]::ReadAllText($ui.RunLogFile)) } catch { } }
        $ctl.RunProgress.Value = 0; $ctl.RunProgress.Visibility = 'Visible'
        $ctl.RunBanner.Visibility = 'Collapsed'; $ctl.ManualBox.Visibility = 'Collapsed'
        $ctl.RunStop.IsEnabled = $true; $ctl.RunStop.Content = 'Остановить после текущего'
        $ctl.RunStatus.Text = 'Подготовка…'
        if (-not $win.TaskbarItemInfo) { $win.TaskbarItemInfo = New-Object Windows.Shell.TaskbarItemInfo }
        $win.TaskbarItemInfo.ProgressState = 'Indeterminate'
        Set-RunButtons 'run'
        Show-Pane 'run'
        Add-RunLog $(if ($Resume) { "Продолжение прогона $stamp после перезагрузки, компьютер $env:COMPUTERNAME" } else { "Tabula Rasa, прогон $stamp, компьютер $env:COMPUTERNAME" })
        $runTimer.Start()
    }

    $runTimer.add_Tick({
        $r = $ui.Run
        if (-not $r) { $runTimer.Stop(); return }
        $s = $r.Sync
        # строки Write-Host из прогона (поток Information) → журнал в окне и run_<дата>.log
        $info = $r.Ps.Streams.Information
        while ($r.LogPos -lt $info.Count) { Add-RunLog ([string]$info[$r.LogPos].MessageData); $r.LogPos++ }
        if ($s.Steps -and -not $r.Built) { Set-RunSteps $s.Steps; $r.Built = $true }
        if ($r.Built) {
            $i = 0; $done = 0; $cur = $null
            foreach ($p in $s.Steps) {
                $v = $runSteps[$i]; $i++
                if ($v.State -ne $p.State) { $v.State = $p.State }
                if ($v.Detail -ne $p.Detail) { $v.Detail = $p.Detail }
                if ($p.State -in 'done', 'same', 'skip', 'error') { $done++ } elseif ($p.State -eq 'run') { $cur = $p }
            }
            $total = [Math]::Max(1, $runSteps.Count)
            $ctl.RunProgress.Value = $done / $total
            $win.TaskbarItemInfo.ProgressState = 'Normal'; $win.TaskbarItemInfo.ProgressValue = $done / $total
            if ($cur) { $ctl.RunStatus.Text = "Шаг $([Math]::Min($done + 1, $total)) из $($runSteps.Count): $($cur.Name)" }
        }
        # вопрос из прогона (нет точки восстановления и т. п.) — диалог в окне вместо Read-Host
        if ($s.Ask -and $null -eq $s.Answer -and -not $ui.Asking) {
            $ui.Asking = $true
            $q = $s.Ask
            $ans = Show-UiMessage -Owner $win -Title 'Нужно решение' -Primary 'Выполнить' -Secondary 'Пропустить' -SafeDefault -Lines (@($q.Text) + @(@($q.Items) | ForEach-Object { "• $_" }))
            $s.Answer = [bool]$ans
            $ui.Asking = $false
        }
        if (-not $r.Handle.IsCompleted) { return }
        $runTimer.Stop()
        $err = $null
        try { [void]$r.Ps.EndInvoke($r.Handle) } catch { $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        while ($r.LogPos -lt $info.Count) { Add-RunLog ([string]$info[$r.LogPos].MessageData); $r.LogPos++ }
        $r.Ps.Dispose()
        if ($err) { Add-RunLog "ОШИБКА: $err" }
        Complete-Run $err
    })

    function Complete-Run ([string]$Err) {
        $r = $ui.Run; $s = $r.Sync
        $bad = @($runSteps | Where-Object { $_.State -eq 'error' }).Count
        $skip = @($runSteps | Where-Object { $_.State -eq 'skip' }).Count
        $ctl.RunTitle.Text = if ($Err) { 'Прогон прерван' } elseif ($bad) { "Готово, ошибок: $bad" } else { 'Готово' }
        $same = @($runSteps | Where-Object { $_.State -eq 'same' }).Count
        $ctl.RunHint.Text = "Выполнено шагов: $(@($runSteps | Where-Object { $_.State -eq 'done' }).Count) из $($runSteps.Count)$(if ($same) { ", уже было настроено: $same" })$(if ($skip) { ", пропущено: $skip" })$(if ($bad) { ", с ошибкой: $bad" }). Журналы: $($script:PB.LogDir)."
        if ($Err) { $ctl.RunHint.Text += " Прогон прерван: $Err" }
        $ctl.RunProgress.Value = 1
        $win.TaskbarItemInfo.ProgressState = if ($bad -or $Err) { 'Error' } else { 'None' }
        $ui.ResumePending = [bool]$s.ResumePending
        $ctl.RunBanner.Visibility = if ($s.NeedReboot -or $ui.ResumePending) { 'Visible' } else { 'Collapsed' }
        $ctl.RunBannerText.Text = 'Для завершения изменений нужна перезагрузка компьютера. Перезагрузить его можно кнопкой «Перезагрузить» внизу окна.'
        if ($ui.ResumePending) {
            $wait = @($runSteps | Where-Object { $_.State -eq 'reboot' }).Count
            $ctl.RunTitle.Text = 'Ожидает перезагрузки'
            $ctl.RunHint.Text = "Выполнено шагов: $(@($runSteps | Where-Object { $_.State -in 'done', 'same' }).Count) из $($runSteps.Count). После перезагрузки: $wait$(if ($bad) { ", с ошибкой: $bad" }). Журналы: $($script:PB.LogDir)."
            $ctl.RunBannerText.Text = if (Test-PbAutoLogonEnabled) { 'Прогон продолжится после перезагрузки: вход в Windows выполнится автоматически.' }
                else { 'Прогон продолжится после перезагрузки и входа в Windows.' }
        }
        # «выполнить вручную» — галочки, отметки сохраняются рядом с журналами
        $manualItems.Clear()
        $state = Join-Path $script:PB.LogDir "manual_$($ui.RunStamp).json"
        foreach ($m in @($s.Manual)) {
            $it = New-Object PcBase.Item; $it.Name = $m
            $it.add_PropertyChanged({ try { @($manualItems | ForEach-Object { @{ Text = $_.Name; Done = $_.IsChecked } }) | ConvertTo-Json | Set-Content -Path $state -Encoding UTF8 } catch { } })
            $manualItems.Add($it)
        }
        $ctl.ManualBox.Visibility = if ($manualItems.Count) { 'Visible' } else { 'Collapsed' }
        # отчёт (lib\report.ps1): «Документы\Tabula Rasa\Отчёты» и копия в журналах
        $ui.Report = $s.Report
        $ctl.RunStatus.Text = if ($s.Report) { "Отчёт: $($s.Report)" } else { "Отчёт не создан. Журнал выполнения: $($ui.RunLogFile)" }
        Set-RunButtons 'done'
        $ctl.RunRetry.Visibility = if ($bad -and -not $ui.ResumePending) { 'Visible' } else { 'Collapsed' }
        $ctl.RunOpenReport.IsEnabled = [bool]$s.Report
        # нужна перезагрузка — главная кнопка «Перезагрузить», иначе «Закрыть»
        $accent = $win.FindResource('AccentButton')
        if ($s.NeedReboot -or $ui.ResumePending) { $ctl.RunReboot.Style = $accent; $ctl.RunClose.ClearValue([Windows.FrameworkElement]::StyleProperty) }
        else { $ctl.RunClose.Style = $accent; $ctl.RunReboot.ClearValue([Windows.FrameworkElement]::StyleProperty) }
        if (-not $win.IsActive) { [PcBase.Native]::Flash((New-Object Windows.Interop.WindowInteropHelper $win).Handle) }
        $ui.Ran = $true
        $ui.Run = $null
        if ($ui.StatusJob -and $ui.StatusJob.Handle.IsCompleted) { $ui.StatusJob = $null; Start-StatusJob }   # статусы после прогона — заново
        if ($ui.ResumePending) { Invoke-ResumeCountdown }
        # прогон с автоматическим входом закончен: компьютер не остаётся открытым без хозяина
        elseif ($ui.AutoLogonUsed) { $ui.AutoLogonUsed = $false; Start-Process rundll32.exe 'user32.dll,LockWorkStation' }
    }

    # Э9: 60 с до перезагрузки; отменили — итог остаётся на экране, перезагрузить можно кнопкой, продолжение не отменяется
    function Invoke-ResumeCountdown {
        $auto = Test-PbAutoLogonEnabled
        $wait = @($runSteps | Where-Object { $_.State -eq 'reboot' }).Count
        $go = Show-UiCountdown -Owner $win -Title 'Перезагрузка для продолжения прогона' -Seconds 60 -Primary 'Перезагрузить сейчас' -Secondary 'Отменить' `
            -Format 'Перезагрузка через {0} с' -Lines @(
                "Шагов, которые выполнятся после перезагрузки: $wait.",
                $(if ($auto) { 'После перезагрузки вход в Windows выполнится автоматически, и прогон продолжится сам.' } else { 'После перезагрузки войдите в Windows: прогон продолжится автоматически.' }),
                @{ Text = 'Сохраните открытые документы в других программах.'; Tone = 'muted' })
        if ($go -and $ui.ResumePending) { Restart-PbForResume }
    }

    # «Повторить упавшее»: новый прогон только из шагов с ошибкой
    function Get-RetryChoice {
        $keys = @($runSteps | Where-Object { $_.State -eq 'error' } | ForEach-Object { $_.Key })
        $p = $ui.LastSel
        $sel = @{ Apps = @(); Tweaks = @(); Configs = @(); Files = @(); FileTitles = @(); Name = $null; Upgrades = @($p.Upgrades); Reinstall = @($p.Reinstall); Remove = @() }
        foreach ($k in $keys) {
            switch -Regex ($k) {
                '^app:(.+)$' { $sel.Apps += $Matches[1] }
                '^remove:(.+)$' { $sel.Remove += $Matches[1] }
                '^tweak:(.+)$' { $sel.Tweaks += $Matches[1] }
                '^config:(.+)$' { $sel.Configs += $Matches[1] }
                '^files$' { $sel.Files = @($p.Files); $sel.FileTitles = @($p.FileTitles) }
                '^rename$' { $sel.Name = $p.Name }
            }
        }
        return $sel
    }

    $ctl.RunApply.add_Click({
        if (-not (Confirm-Apply $ui.PlanSel)) { return }
        if (-not (Confirm-Reboots $ui.PlanSel)) { return }
        $ui.LastSel = $ui.PlanSel
        Start-Run $ui.PlanSel
    })
    $ctl.RunBack.add_Click({ $runSteps.Clear(); Show-Pane 'select'; Set-RunButtons 'plan' })
    $ctl.RunSkip.add_Click({ if ($ui.Run) { $ui.Run.Sync.SkipCurrent = $true; $ctl.RunStatus.Text = 'Текущий шаг будет пропущен…' } })
    $ctl.RunStop.add_Click({
        if (-not $ui.Run) { return }
        $ui.Run.Sync.StopAfter = $true
        $ctl.RunStop.IsEnabled = $false; $ctl.RunStop.Content = 'Остановится после текущего шага'
    })
    $ctl.RunRetry.add_Click({
        $sel = Get-RetryChoice
        if (-not (Confirm-Apply $sel)) { return }
        if (-not (Confirm-Reboots $sel)) { return }
        Start-Run $sel
    })
    $ctl.RunOpenLog.add_Click({ Start-Process explorer.exe $script:PB.LogDir })
    # через explorer.exe: браузер открывается от имени пользователя, а не с правами администратора, как у этого процесса
    $ctl.RunOpenReport.add_Click({ if ($ui.Report -and (Test-Path -LiteralPath $ui.Report)) { Start-Process explorer.exe "`"$($ui.Report)`"" } })
    function Open-ReportFolder {
        if ($ui.Report -and (Test-Path -LiteralPath $ui.Report)) { Start-Process explorer.exe "/select,`"$($ui.Report)`"" }
        else { $d = Get-PbReportDir; if (-not (Test-Path $d)) { $d = $script:PB.LogDir }; Start-Process explorer.exe "`"$d`"" }
    }
    $ctl.RunMore.add_Click({
        $m = $ctl.RunMore.ContextMenu
        $m.Items.Clear()
        $menu = @(, @('Открыть папку с отчётами', 'folder'))   # запятая: массив пар, а не плоский список строк
        if ($ui.ResumePending) { $menu += , @('Не продолжать после перезагрузки…', 'no-resume') }
        $menu += , @('Удалить Tabula Rasa с этого компьютера…', 'remove-self')
        foreach ($p in $menu) {
            $mi = New-Object Windows.Controls.MenuItem; $mi.Header = $p[0]; $mi.Tag = $p[1]; [void]$m.Items.Add($mi)
        }
        $m.PlacementTarget = $ctl.RunMore; $m.IsOpen = $true
    })
    $ctl.RunMore.ContextMenu.AddHandler([Windows.Controls.MenuItem]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        switch ([string]$e.Source.Tag) { 'folder' { Open-ReportFolder } 'no-resume' { Stop-Resume } 'remove-self' { Invoke-SelfRemove } }
    })
    $ctl.RunClose.add_Click({ $win.DialogResult = $true })
    # удаление программы: не во время прогона; запущено — окно закрывается, чтобы скрипт очистки мог удалить папку
    function Invoke-SelfRemove {
        if ($ui.Run) { [void](Show-UiMessage -Owner $win -Title 'Прогон выполняется' -Lines @('Удалить Tabula Rasa можно после окончания прогона.')); return }
        if (Show-SelfRemoveDialog $win) {
            Stop-PbResume   # незавершённый прогон (Э9): задача планировщика и пароль автоматического входа — тоже прочь
            $ui.SelfRemoving = $true
            $win.DialogResult = $true
        }
    }
    $ctl.RunReboot.add_Click({
        if (-not (Show-UiMessage -Owner $win -Title 'Перезагрузить компьютер?' -Primary 'Перезагрузить' -Secondary 'Позже' -SafeDefault -Lines @('Несохранённые данные в других программах будут потеряны.'))) { return }
        if ($ui.ResumePending) { Restart-PbForResume } else { Restart-Computer -Force }
    })
    # отказ от продолжения (Э9): задача планировщика, состояние и пароль автоматического входа удаляются
    function Stop-Resume {
        if (-not (Show-UiMessage -Owner $win -Title 'Не продолжать прогон?' -Primary 'Не продолжать' -Secondary 'Назад' -SafeDefault -Lines @(
            'Шаги, которые ждут перезагрузки, выполнены не будут. Их можно выполнить новым прогоном.',
            @{ Text = 'Пароль автоматического входа, если он был сохранён, удаляется.'; Tone = 'muted' }))) { return }
        Stop-PbResume
        $ui.ResumePending = $false
        foreach ($r in @($runSteps | Where-Object { $_.State -eq 'reboot' })) { $r.State = 'skip'; $r.Detail = 'не продолжено после перезагрузки' }
        $ctl.RunTitle.Text = 'Прогон остановлен'
        $ctl.RunBannerText.Text = 'Прогон не будет продолжен после перезагрузки.'
        $ctl.RunBack.Visibility = 'Visible'
        $ctl.RunReboot.ClearValue([Windows.FrameworkElement]::StyleProperty); $ctl.RunClose.Style = $win.FindResource('AccentButton')
    }
    $ctl.LogToggle.add_Click({
        $show = $ctl.RunLog.Visibility -ne 'Visible'
        $ctl.RunLog.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
        $ctl.LogToggle.Content = if ($show) { 'Скрыть журнал' } else { 'Показать журнал' }
    })
    # пока идёт прогон, окно не закрывается: прерывать установку посередине нельзя
    $win.add_Closing({
        param($sender, $e)
        if ($ui.Run) {
            $e.Cancel = $true
            [void](Show-UiMessage -Owner $win -Title 'Прогон выполняется' -Lines @('Чтобы прервать прогон, нажмите «Остановить после текущего» и дождитесь окончания шага.'))
        }
    })

    # --- «⋯»: откат, о программе, клавиши ---
    function Show-Keys {
        [void](Show-UiMessage -Owner $win -Title 'Клавиши' -Lines @(
            'Ctrl+F — поиск, Esc — очистить поиск', 'Ctrl+1 / 2 / 3 — программы, настройки Windows, файлы', '↑ / ↓ — категории, Пробел — отметить пункт',
            'Ctrl+S — сохранить профиль', 'F1 — этот список'))
    }
    function Show-About {
        $st = Get-PbDataState
        [void](Show-UiMessage -Owner $win -Title 'О программе' -Lines @(
            "Tabula Rasa $(Get-PbEngineVersion)", "Папка программы: $($script:PB.Root)",
            $(if ($ui.EngineBehind) { @{ Text = 'Доступна новая версия. Она будет установлена при следующем запуске Tabula Rasa.'; Tone = 'strong' } } else { 'Новая версия проверяется и устанавливается при каждом запуске.' }),
            $(if ($st.Connected) { "Мои данные: $($st.Repo)$(if ($st.Pending) { ", не отправлено: $($st.Pending)" })" } else { 'Мои данные: не подключены' }),
            "Журналы: $($script:PB.LogDir)",
            @{ Text = 'Исходный код: https://github.com/iheeae/tabula-rasa'; Tone = 'muted'; Gap = $true }))
    }
    $ctl.MoreBtn.add_Click({
        $m = $ctl.MoreBtn.ContextMenu
        $m.Items.Clear()
        $menu = @(@('Откат изменений…', 'undo'), @('О программе', 'about'), @('Клавиши   F1', 'keys'), @('Удалить Tabula Rasa с этого компьютера…', 'remove-self'))
        if ($script:PbThemePref -ne 'auto') { $menu = @(, @('Тема как в Windows', 'theme-auto')) + $menu }
        foreach ($p in $menu) {
            $mi = New-Object Windows.Controls.MenuItem; $mi.Header = $p[0]; $mi.Tag = $p[1]; [void]$m.Items.Add($mi)
        }
        $m.PlacementTarget = $ctl.MoreBtn; $m.IsOpen = $true
    })
    $ctl.MoreBtn.ContextMenu.AddHandler([Windows.Controls.MenuItem]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        switch ([string]$e.Source.Tag) {
            'undo' { Show-UndoDialog $win } 'about' { Show-About } 'keys' { Show-Keys }
            'theme-auto' { $script:PbThemePref = 'auto'; Update-Theme }
            'remove-self' { Invoke-SelfRemove }
        }
    })

    # новая версия движка: проверка в фоне (git fetch), установится при следующем запуске (setup.ps1)
    $engineTimer = New-Object Windows.Threading.DispatcherTimer
    $engineTimer.Interval = [TimeSpan]::FromSeconds(1)
    function Start-EngineCheck {
        if (-not (Get-Command git -ErrorAction SilentlyContinue) -or -not (Test-Path (Join-Path $script:PB.Root '.git'))) { return }
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root)
            & git -C $Root fetch --quiet origin master 2>$null
            if ($LASTEXITCODE -ne 0) { return $false }
            return ((& git -C $Root rev-parse HEAD 2>$null) -ne (& git -C $Root rev-parse origin/master 2>$null))
        })
        [void]$ps.AddArgument($script:PB.Root)
        $ui.EngineJob = @{ Ps = $ps; Handle = $ps.BeginInvoke() }
        $engineTimer.Start()
    }
    $engineTimer.add_Tick({
        $j = $ui.EngineJob
        if (-not $j -or -not $j.Handle.IsCompleted) { return }
        $engineTimer.Stop()
        try { $ui.EngineBehind = [bool](@($j.Ps.EndInvoke($j.Handle))[-1]) } catch { }
        $j.Ps.Dispose(); $ui.EngineJob = $null
        if ($ui.EngineBehind) { Show-Notice 'Доступна новая версия Tabula Rasa. Она будет установлена при следующем запуске.' }
    })

    # тема и акцент Windows меняются на лету: опрос раз в 2 с (обработчик SystemEvents пришёл бы из чужого потока)
    $themeTimer = New-Object Windows.Threading.DispatcherTimer
    $themeTimer.Interval = [TimeSpan]::FromSeconds(2)
    $ui.ThemeKey = "$($theme.Dark)|$($theme.Accent)|$([Windows.SystemParameters]::HighContrast)"
    # тема на лету: смена в Windows (раз в 2 с) или кнопкой в шапке
    function Update-Theme {
        $t = Get-UiTheme
        $k = "$($t.Dark)|$($t.Accent)|$([Windows.SystemParameters]::HighContrast)"
        if ($k -ne $ui.ThemeKey) {
            $ui.ThemeKey = $k
            Set-UiPalette ([Windows.Application]::Current.Resources) $t
            # диалоги берут тему из Initialize-Ui (тёмный заголовок окна) — обновить и её
            if ($script:PbUiTheme) { $script:PbUiTheme.Dark = $t.Dark; $script:PbUiTheme.Accent = $t.Accent }
            $icon = New-UiIcon ([Windows.Application]::Current.Resources)
            $win.Icon = $icon; $ctl.Logo.Source = $icon
            [PcBase.Native]::SetDarkTitleBar((New-Object Windows.Interop.WindowInteropHelper $win).Handle, [bool]$t.Dark)
        }
        # кнопка показывает, на какую тему переключит: в тёмной — солнце, в светлой — луна
        $ctl.ThemeGlyph.Text = if ($t.Dark) { [string][char]0xE706 } else { [string][char]0xE708 }
        $to = if ($t.Dark) { 'светлую' } else { 'тёмную' }
        $ctl.ThemeBtn.ToolTip = "Переключить на $to тему$(if ($script:PbThemePref -eq 'auto') { '. Сейчас — как в Windows' })"
        [Windows.Automation.AutomationProperties]::SetName($ctl.ThemeBtn, "Переключить на $to тему")
    }
    $themeTimer.add_Tick({ Update-Theme })
    $ctl.ThemeBtn.add_Click({
        $script:PbThemePref = if ((Get-UiTheme).Dark) { 'light' } else { 'dark' }
        Update-Theme
    })

    # «Показать план» — план в окне; применение — кнопкой «Применить…» на экране плана после подтверждения.
    # С -Console (RunInWindow = $false) — выбор возвращается в setup.ps1: план и подтверждение — в консоли
    $ctl.OkBtn.add_Click({
        $c = Get-RunChoice
        if (-not $c) { return }
        if (-not $RunInWindow) {
            $ui.Result = $c
            $win.DialogResult = $true
            return
        }
        Show-Plan $c
    })

    # горячие клавиши: Ctrl+F — поиск, Esc — очистить его, Ctrl+1/2/3 — разделы
    $win.add_PreviewKeyDown({
        param($s, $e)
        $ctrl = [Windows.Input.Keyboard]::Modifiers -eq [Windows.Input.ModifierKeys]::Control
        if ($e.Key -eq 'F1') { $e.Handled = $true; Show-Keys; return }
        if ($ctl.TabCapture.IsChecked -or $ctl.RunPane.Visibility -eq 'Visible') { return }   # клавиши каталога — только при выборе
        if ($ctrl -and $e.Key -eq 'F') { [void]$ctl.Search.Focus(); $ctl.Search.SelectAll(); $e.Handled = $true; return }
        if ($ctrl -and $e.Key -eq 'S') { $e.Handled = $true; Save-Current; return }
        if ($e.Key -eq 'Escape' -and $ctl.Search.Text) { $ctl.Search.Text = ''; $e.Handled = $true; return }
        if ($ctrl) {
            $sec = switch ($e.Key) { { $_ -in 'D1', 'NumPad1' } { 'apps' } { $_ -in 'D2', 'NumPad2' } { 'tweaks' } { $_ -in 'D3', 'NumPad3' } { 'files' } }
            if ($sec -and $first[$sec]) { Select-Nav $first[$sec]; $e.Handled = $true }
        }
    })

    # --- старт ---
    $ctl.Nav.ItemsSource = $nav
    $ctl.NavBottom.ItemsSource = $navBottom
    $ctl.List.ItemsSource = $items
    Update-ConfigAvail
    Update-FilesCard
    Update-Counts
    Update-DataBox
    if ($Initial) {
        $miss = Set-Selection $Initial
        Set-SaveName $Initial.Name
        if ($miss) { Show-Notice "Открыто «$($Initial.Name)». Пропущено пунктов, отсутствующих в каталоге этого компьютера: $miss." 'warn' }
    }
    if (@($Notices | Where-Object { $_ }).Count) { Show-Notice (@($Notices | Where-Object { $_ }) -join ' ') 'warn' }
    $saved = Read-UiState
    Restore-UiState $win $saved
    $start = $first['apps']; if (-not $start) { $start = @($cats.Values)[0] }
    if ($saved -and $saved.Nav -and $cats.Contains([string]$saved.Nav)) { $start = $cats[[string]$saved.Nav] }
    $ctl.Nav.SelectedItem = $start
    $win.add_ContentRendered({
        # время от старта процесса до окна — в журнал выполнения (setup.ps1); цель — меньше 2 с
        try { $script:PB.WindowShownSec = [Math]::Round(((Get-Date) - (Get-Process -Id $PID).StartTime).TotalSeconds, 1) } catch { }
        # Topmost нужен, только чтобы окно появилось поверх заставки и окна, из которого запустили; дальше он закрывал бы браузер со страницей входа в GitHub
        $win.Topmost = $false; [void]$win.Activate()
        Select-Nav $ctl.Nav.SelectedItem
        Update-HostChips
        # консоль setup.ps1 не нужна: окно — единственный интерфейс (setup.ps1 -Console её оставляет). Обычно она
        # и так скрыта (setup.ps1 запускает себя скрытым процессом) — это на случай, если Windows всё же её показала
        if ($RunInWindow) { [PcBase.Native]::ShowConsole($false) }
        # заставка (lib\splash.ps1) уступает место окну
        if (Get-Command Close-PbSplash -ErrorAction SilentlyContinue) { Set-PbSplash '' 1; Close-PbSplash }
        Start-FilesJob
        if ($Resume) {
            # продолжение прогона (Э9): сразу экран прогона; статусы и обновления движка — не посреди прогона
            $ui.AutoLogonUsed = Test-PbAutoLogonEnabled
            $ui.LastSel = Get-PbResumeSel $Resume
            Start-Run $ui.LastSel $Resume
        } else {
            Start-StatusJob
            Start-EngineCheck
        }
        Update-Theme
        $themeTimer.Start()
        if (Initialize-DataLayout) { Start-DataJob 'push' }
        # проверка окна в CI (tests\smoke.ps1): дождаться статусов, пройти по разделам, показать план, закрыть
        if ($env:TR_SMOKE) {
            $ui.SmokeStart = Get-Date
            # таймер — в $ui: обработчик Tick выполняется позже, когда переменных этого обработчика уже нет
            $ui.SmokeTimer = New-Object Windows.Threading.DispatcherTimer
            $ui.SmokeTimer.Interval = [TimeSpan]::FromSeconds(1)
            $ui.SmokeTimer.add_Tick({
                try {
                    $sec = ((Get-Date) - $ui.SmokeStart).TotalSeconds
                    $busy = $ui.StatusJob -and -not $ui.StatusJob.Handle.IsCompleted
                    if (-not $ui.SmokeDone) { $env:TR_SMOKE_STEP = "ожидание статусов, $([int]$sec) с" }
                    if ($busy -and $sec -lt 120) { return }
                    if (-not $ui.SmokeDone) {
                        $ui.SmokeDone = $true
                        Write-Host "  smoke: статусы готовы через $([int]$sec) с"
                        $env:TR_SMOKE_STEP = 'разделы'
                        foreach ($n in @($nav | Where-Object { $_.Kind -eq 'cat' })) { $env:TR_SMOKE_STEP = "раздел $($n.Name)"; Select-Nav $n }
                        $env:TR_SMOKE_STEP = 'подробности'
                        $first = @($items | Where-Object { $_.Kind -eq 'app' } | Select-Object -First 1)
                        if ($first) { $ctl.List.SelectedItem = $first[0] }
                        $env:TR_SMOKE_STEP = 'отметки'
                        foreach ($it in @($items | Where-Object { $_.Kind -eq 'tweak' } | Select-Object -First 3)) { $it.IsChecked = $true }
                        foreach ($it in @($items | Where-Object { $_.Kind -eq 'app' -and -not $_.IsLocked } | Select-Object -First 2)) { $it.IsChecked = $true }
                        $env:TR_SMOKE_STEP = 'тема'
                        $ctl.ThemeBtn.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
                        $ctl.ThemeBtn.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
                        # снимки экранов и контраст текста в обеих темах (папка TR_SMOKE_SHOTS)
                        $shots = $env:TR_SMOKE_SHOTS
                        if ($shots) { New-Item -ItemType Directory -Path $shots -Force | Out-Null }
                        $issues = New-Object System.Collections.ArrayList
                        $shot = {
                            param($Name)
                            $win.UpdateLayout()
                            $back = (Get-UiBackColor $ctl.List ([Windows.Media.Colors]::White))
                            $wb = [Windows.Application]::Current.Resources['Bg']; if ($wb) { $back = $wb.Color }
                            foreach ($x in (Find-UiContrastIssues $win.Content $back)) { [void]$issues.Add("$Name — $x") }
                            if ($shots) { Save-UiShot $win.Content $back (Join-Path $shots "$Name.png") }
                        }
                        foreach ($th in 'light', 'dark') {
                            $env:TR_SMOKE_STEP = "снимки, тема $th"
                            $script:PbThemePref = $th; Update-Theme
                            Show-Pane 'select'; Set-RunButtons 'plan'
                            $appCat = @($nav | Where-Object { $_.Kind -eq 'cat' -and $_.Section -eq 'apps' } | Select-Object -First 1)
                            if ($appCat) { Select-Nav $appCat[0] }
                            $sel = @($items | Where-Object { $_.Kind -eq 'app' -and $_.CatKey -eq $ui.Cat -and $_.IsLocked } | Select-Object -First 1)
                            if (-not $sel) { $sel = @($items | Where-Object { $_.Kind -eq 'app' -and $_.CatKey -eq $ui.Cat } | Select-Object -First 1) }
                            if ($sel) { $ctl.List.SelectedItem = $sel[0] }
                            & $shot "$th-1-catalog"
                            $twCat = @($nav | Where-Object { $_.Kind -eq 'cat' -and $_.Section -eq 'tweaks' } | Select-Object -First 1)
                            if ($twCat) { Select-Nav $twCat[0]; $t1 = @($items | Where-Object { $_.CatKey -eq $ui.Cat } | Select-Object -First 1); if ($t1) { $ctl.List.SelectedItem = $t1[0] } }
                            & $shot "$th-2-tweaks"
                            Select-Nav $navSummary
                            & $shot "$th-3-summary"
                            $c = Get-RunChoice
                            if ($c) { Show-Plan $c }
                            & $shot "$th-4-plan"
                            Set-RunButtons 'done'
                            $ctl.RunLog.Visibility = 'Visible'
                            if (-not $ctl.RunLog.Text) { $ctl.RunLog.AppendText(((1..80 | ForEach-Object { "==> строка журнала ${_}: установка программы, ограничение 15 мин" }) -join "`r`n")) }
                            & $shot "$th-5-log"
                            $win.UpdateLayout()
                            if ($ctl.RunLog.ActualHeight -lt 120) { throw "журнал выполнения слишком низкий: $([int]$ctl.RunLog.ActualHeight) px" }
                            # Э9: итог, когда часть шагов ждёт перезагрузки
                            if ($runSteps.Count) {
                                $runSteps[0].State = 'done'
                                $last = $runSteps[$runSteps.Count - 1]; $last.State = 'reboot'; $last.Detail = 'выполнится после перезагрузки: перед установкой нужна перезагрузка'
                            }
                            $ctl.RunTitle.Text = 'Ожидает перезагрузки'
                            $ctl.RunBannerText.Text = 'Прогон продолжится после перезагрузки и входа в Windows.'; $ctl.RunBanner.Visibility = 'Visible'
                            $ui.ResumePending = $true; Set-RunButtons 'done'; $ui.ResumePending = $false
                            & $shot "$th-8-resume"
                            $ctl.RunBanner.Visibility = 'Collapsed'
                            Show-Pane 'select'; Set-RunButtons 'plan'
                            $ctl.TabCapture.IsChecked = $true
                            & $shot "$th-6-capture"
                            $ctl.TabInstall.IsChecked = $true
                            # диалог — без ShowDialog: показать, снять, закрыть
                            $d = New-UiWindow 'dialog.xaml' (Initialize-Ui)
                            $d.Owner = $win; $d.FindName('Head').Text = 'Применить к PC-01?'
                            foreach ($ln in @('Программ: 3, с моими настройками: 1', 'Настроек Windows: 5')) { $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $ln; $tb.Margin = '0,4,0,0'; [void]$d.FindName('Body').Children.Add($tb) }
                            $tb = New-Object Windows.Controls.TextBlock; $tb.Text = 'Изменения будут применены сразу.'; $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextMuted'); [void]$d.FindName('Body').Children.Add($tb)
                            $d.FindName('Primary').Content = 'Применить'; $d.FindName('Secondary').Content = 'Назад'
                            $d.Show(); $d.UpdateLayout()
                            foreach ($x in (Find-UiContrastIssues $d.Content ([Windows.Application]::Current.Resources['Bg'].Color))) { [void]$issues.Add("$th-dialog — $x") }
                            if ($shots) { Save-UiShot $d.Content ([Windows.Application]::Current.Resources['Bg'].Color) (Join-Path $shots "$th-7-dialog.png") }
                            $d.Close()
                            # Э9: пароль для временного автоматического входа (Read-UiPassword) — поле пароля в теме окна
                            $d = New-UiWindow 'dialog.xaml' (Initialize-Ui)
                            $d.Owner = $win; $d.FindName('Head').Text = 'Пароль Windows'
                            $tb = New-Object Windows.Controls.TextBlock; $tb.Text = 'Пароль учётной записи PC-01\user. Он используется только для входа после перезагрузок этого прогона.'; $tb.TextWrapping = 'Wrap'; [void]$d.FindName('Body').Children.Add($tb)
                            $pw = New-Object Windows.Controls.PasswordBox; $pw.Margin = '0,16,0,0'; $pw.Password = 'smoke'; [void]$d.FindName('Body').Children.Add($pw)
                            $d.FindName('Primary').Content = 'Продолжить'; $d.FindName('Secondary').Content = 'Отмена'
                            $d.Show(); $d.UpdateLayout()
                            if ($pw.ActualHeight -lt 30) { throw "поле пароля без стиля: высота $([int]$pw.ActualHeight) px" }
                            foreach ($x in (Find-UiContrastIssues $d.Content ([Windows.Application]::Current.Resources['Bg'].Color))) { [void]$issues.Add("$th-password — $x") }
                            if ($shots) { Save-UiShot $d.Content ([Windows.Application]::Current.Resources['Bg'].Color) (Join-Path $shots "$th-9-password.png") }
                            $pw.Clear(); $d.Close()
                        }
                        $script:PbThemePref = 'auto'; Update-Theme
                        Write-Host "  smoke: снимки готовы, замечаний по контрасту: $($issues.Count)"
                        if ($shots) { [IO.File]::WriteAllLines((Join-Path $shots 'contrast.txt'), [string[]]@($issues), (New-Object Text.UTF8Encoding $false)) }
                        $env:TR_SMOKE_STEP = 'план показан'
                        return
                    }
                    $ui.SmokeTimer.Stop()
                    $env:TR_SMOKE_STEP = 'закрытие'
                    $win.Close()
                } catch {
                    $env:TR_SMOKE_STEP = "ошибка на шаге «$env:TR_SMOKE_STEP»: $($_.Exception.Message) @ строка $($_.InvocationInfo.ScriptLineNumber)"
                    $ui.SmokeTimer.Stop()
                    $win.Close()
                }
            })
            $ui.SmokeTimer.Start()
        }
    })

    $closedOk = $win.ShowDialog()
    if ($RunInWindow) { return @{ RanInWindow = $true; Ran = [bool]$ui.Ran } }
    if (-not $closedOk) { return $null }
    return $ui.Result
}
