# Tabula Rasa: проверки без окна и без сети — разбор вывода winget (русский и английский), свой каталог, фильтр секретов,
# снятие настроек, разметка репозитория данных, имена ассетов. Запуск из корня репозитория:
#   powershell -ExecutionPolicy Bypass -File tests\run.ps1        (или pwsh -File tests/run.ps1)
# Нужен git. Всё пишется во временную папку; сеть, gh и «Мои данные» на этом компьютере не затрагиваются.
# Э9: состояние прогона — во временной папке, задача планировщика и секрет LSA подменены, Winlogon — тестовый ключ в HKCU.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($f in 'common', 'data', 'files', 'catalog', 'configs', 'status', 'run') { . (Join-Path (Join-Path $root 'lib') "$f.ps1") }
$script:PB.Root = $root

$script:Fails = 0; $script:Count = 0
function Check ([string]$Name, [bool]$Ok, $Got) {
    $script:Count++
    if ($Ok) { Write-Host "  ok   $Name" -ForegroundColor Green }
    else {
        $script:Fails++; Write-Host "  FAIL $Name$(if ($null -ne $Got) { " — получено: $($Got | Out-String -Width 200)".TrimEnd() })" -ForegroundColor Red
        # в GitHub Actions — аннотация: видна в сводке прогона без чтения журнала
        if ($env:GITHUB_ACTIONS) { Write-Host "::error title=tests/run.ps1::$Name$(if ($null -ne $Got) { ' — получено: ' + (($Got | Out-String -Width 200) -replace '\r?\n', ' ').Trim() })" }
    }
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tabula-rasa-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
# прогон в конце убирает всё про продолжение (Stop-PbResume): здесь — только во временной папке и без планировщика и LSA
function Set-PbResumeSandbox {
    $script:PbResume.Dir = Join-Path $tmp 'resume'
    $script:PbResume.Winlogon = 'HKCU:\Software\tabula-rasa-tests\' + (Split-Path $tmp -Leaf)
    function script:Register-PbResumeTask { $script:Task9 = 'on' }
    function script:Unregister-PbResumeTask { $script:Task9 = 'off' }
    function script:Test-PbResumeTask { $script:Task9 -eq 'on' }
    function script:Set-PbLogonSecret ($Password) { [void]$script:Secret9.Add('set'); 0 }
    function script:Clear-PbLogonSecret { [void]$script:Secret9.Add('clear'); 0 }
}
$script:Secret9 = New-Object System.Collections.ArrayList
Set-PbResumeSandbox

try {
    # ---------- winget search ----------
    Write-Host 'winget search'
    $en = @(
        "   - `r   \ `r",
        'Name                  Id                          Version Match          Source',
        '-------------------------------------------------------------------------------',
        'Notepad++             Notepad++.Notepad++         8.7.1                  winget',
        'Notepad Next          dail8859.NotepadNext        0.9     Tag: notepad   winget',
        'Notepad Fork          Some.VeryLongIdentifierTha… 1.0                    winget',
        '',
        'Additional entries'
    )
    $r = ConvertFrom-PbWingetTable $en
    Check 'en: две строки, усечённый id отброшен' ($r.Count -eq 2) $r
    Check 'en: имя с пробелом' ($r[1].Name -eq 'Notepad Next' -and $r[1].Id -eq 'dail8859.NotepadNext' -and $r[1].Version -eq '0.9') $r[1]
    $ru = @(
        "`r   / `r",
        'Имя        ИД                   Версия    Совпадение',
        '----------------------------------------------------',
        '7-Zip      7zip.7zip            24.08',
        'NanaZip    M2Team.NanaZip       5.0.1263  Tag: 7zip',
        'PeaZip     Giorgiotani.Peazip   10.0      Tag: 7zip'
    )
    $r = ConvertFrom-PbWingetTable $ru
    Check 'ru: три строки без колонки «Источник»' ($r.Count -eq 3) $r
    Check 'ru: позиции по заголовку' ($r[0].Id -eq '7zip.7zip' -and $r[1].Version -eq '5.0.1263' -and $r[2].Name -eq 'PeaZip') $r
    Check 'нет таблицы — пусто' (@(ConvertFrom-PbWingetTable @('No package found matching input criteria.')).Count -eq 0)
    $m = Merge-PbWingetResults '7-zip' @(@($r[2], $r[1]), @($r[0], $r[1]))
    Check 'сортировка: точное имя первым, дубли убраны' ($m.Count -eq 3 -and $m[0].Id -eq '7zip.7zip' -and $m[1].Id -eq 'Giorgiotani.Peazip') ($m | Select-Object Name, Rank)
    $m = Merge-PbWingetResults 'notepad' @(, @(
        [pscustomobject]@{ Name = 'Notepad++'; Id = 'Notepad++.Notepad++'; Version = '' },
        [pscustomobject]@{ Name = 'Microsoft Windows Notepad'; Id = 'x.y'; Version = '' },
        [pscustomobject]@{ Name = 'notepad'; Id = 'a.b'; Version = '' }))
    Check 'сортировка: точное → начало имени → остальное' (($m.Id -join ',') -eq 'a.b,Notepad++.Notepad++,x.y') $m.Id

    $show = @('Found Notepad++ [Notepad++.Notepad++]', 'Version: 8.7.1', 'Publisher: Notepad++ Team', 'Description:', '  Notepad++ is a free source code editor', '  and Notepad replacement.', 'Homepage: https://notepad-plus-plus.org/', 'License: GPL-3.0')
    $s = ConvertFrom-PbWingetShow $show
    Check 'show en: издатель и многострочное описание' ($s.Publisher -eq 'Notepad++ Team' -and $s.Description -eq 'Notepad++ is a free source code editor and Notepad replacement.') $s
    $s = ConvertFrom-PbWingetShow @('Найдено 7-Zip [7zip.7zip]', 'Версия: 24.08', 'Издатель: Igor Pavlov', 'Описание: Архиватор', 'Лицензия: LGPL-2.1')
    Check 'show ru' ($s.Publisher -eq 'Igor Pavlov' -and $s.Description -eq 'Архиватор' -and $s.License -eq 'LGPL-2.1') $s

    # ---------- свой каталог ----------
    Write-Host 'свой каталог'
    $script:PB.DataRoot = Join-Path $tmp 'data'
    New-Item -ItemType Directory -Path (Join-Path $script:PB.DataRoot 'catalog') -Force | Out-Null
    $builtin = @('git', 'vivaldi')
    Check 'верная запись' ($null -eq (Test-PbUserApp @{ Id = 'my.obs'; Name = 'OBS'; WingetId = 'OBSProject.OBSStudio'; Source = 'winget' } $builtin))
    Check 'web запрещён' ([bool](Test-PbUserApp @{ Id = 'x'; Name = 'X'; WingetId = 'A.B'; Source = 'web' } $builtin))
    Check 'Override запрещён' ([bool](Test-PbUserApp @{ Id = 'x'; Name = 'X'; WingetId = 'A.B'; Override = '/S' } $builtin))
    Check 'id встроенного запрещён' ([bool](Test-PbUserApp @{ Id = 'git'; Name = 'X'; WingetId = 'A.B' } $builtin))
    Check 'скриптблок не строка' ([bool](Test-PbUserApp @{ Id = 'x'; Name = { 'код' }; WingetId = 'A.B' } $builtin))
    Check 'Interactive не bool' ([bool](Test-PbUserApp @{ Id = 'x'; Name = 'X'; WingetId = 'A.B'; Interactive = 'yes' } $builtin))
    $id1 = New-PbUserAppId 'Notepad++.Notepad++' @(); $id2 = New-PbUserAppId 'Notepad++.Notepad++' @($id1)
    Check 'New-PbUserAppId: допустимый и уникальный' ($id1 -eq 'my.notepadpp.notepadpp' -and $id2 -eq "$id1-2" -and -not (Test-PbUserApp @{ Id = $id2; Name = 'N'; WingetId = 'Notepad++.Notepad++' } @($id1))) @($id1, $id2)
    Write-PbUserCatalog @(@{ Id = 'my.obs'; Name = "OBS 'Studio'"; Desc = 'Запись экрана'; Category = 'Медиа'; Source = 'winget'; WingetId = 'OBSProject.OBSStudio'; OpenSource = $true; Mine = $true })
    $c = Read-PbUserCatalog $builtin
    Check 'запись и чтение: кавычки, кириллица, bool' ($c.Apps.Count -eq 1 -and $c.Apps[0].Name -eq "OBS 'Studio'" -and $c.Apps[0].Category -eq 'Медиа' -and $c.Apps[0].OpenSource -eq $true -and $c.Apps[0].Mine) $c
    Check 'файл каталога с BOM' (Test-PbBom (Get-PbUserCatalogPath))
    $p = Get-PbUserCatalogPath
    [IO.File]::WriteAllText($p, "@{ Apps = @(`n @{ Id = 'my.a'; Name = 'A'; WingetId = 'A.A' }`n @{ Id = 'my.b'; Name = 'B'; Source = 'web'; WingetId = 'B.B' }`n @{ Id = 'my.a'; Name = 'A2'; WingetId = 'A.A2' }`n @{ Id = 'my.c'; Name = 'C'; WingetId = 'C.C'; Category = 'Своё' }`n) }", (New-Object Text.UTF8Encoding $true))
    $c = Read-PbUserCatalog $builtin
    Check 'ошибочные пропущены с сообщением' ($c.Apps.Count -eq 2 -and $c.Errors.Count -eq 2 -and $c.Apps[0].Category -eq 'Мой каталог') ($c.Errors)
    [IO.File]::WriteAllText($p, "@{ Apps = @( @{ Id = 'my.a'; Name = 'A'; WingetId = 'A.A'; Note = { Remove-Item C:\ } } ) }", (New-Object Text.UTF8Encoding $true))
    $c = Read-PbUserCatalog $builtin
    Check 'скриптблок в файле — файл не загружается' ($c.Apps.Count -eq 0 -and $c.Errors.Count -eq 1) $c.Errors

    # ---------- фильтр секретов ----------
    Write-Host 'фильтр секретов'
    $rm = New-Object System.Collections.ArrayList
    $j = '{"theme":"dark","github":{"token":"x"},"list":["ok","ghp_0123456789abcdefghijABCDEFGHIJ0123456789"],"nested":{"apiKey":"k","size":11},"Path":"C:\\Users\\user\\AppData\\Local\\Programs\\Microsoft VS Code\\bin\\code.cmd"}' | ConvertFrom-Json
    Remove-PbJsonSecrets $j '' $rm
    Check 'json: token, apiKey и токен в массиве удалены' ($null -eq $j.github.token -and $null -eq $j.nested.apiKey -and $j.nested.size -eq 11 -and @($j.list).Count -eq 1 -and $rm.Count -eq 3) $rm
    Check 'json: путь не принят за токен' ([bool]$j.Path)
    $rm = New-Object System.Collections.ArrayList
    $t = Remove-PbTextSecrets @('[general]', 'theme = dark', 'password=123', '  "github.token": "abc",', 'x = ghp_0123456789abcdefghijABCDEFGHIJ0123456789', 'font = Cascadia') 'a.ini' $rm
    Check 'текст: строки с секретами удалены' (($t -join '|') -eq '[general]|theme = dark|font = Cascadia' -and $rm.Count -eq 3) $t

    # ---------- снятие настроек: Git, временная папка, сравнение ----------
    Write-Host 'снятие настроек'
    $home2 = Join-Path $tmp 'home'; New-Item -ItemType Directory -Path $home2 | Out-Null
    $oldProfile = $env:USERPROFILE; $env:USERPROFILE = $home2
    try {
        $gc = @('[user]', '    name = user', '[credential "https://github.com"]', '    helper = !gh auth git-credential', '[alias]', '    st = status', '[http]', '    extraheader = AUTHORIZATION: basic xyz')
        Write-PbText (Join-Path $home2 '.gitconfig') $gc
        $stage = Join-Path $tmp 'stage'
        $app = @{ Id = 'git'; Name = 'Git'; Config = @{ Export = 'Export-GitConfig' } }
        $res = @(Invoke-PbCapture @($app) $stage)
        $out = @(Get-Content (Join-Path $stage $res[0].Files[0]) -Encoding UTF8)
        Check 'git: без credential и extraheader' (-not $res[0].Error -and ($out -join '|') -eq '[user]|    name = user|[alias]|    st = status|[http]' -and $res[0].Removed.Count -eq 2) @($out, $res[0].Removed, $res[0].Error)
        $target = Join-Path $tmp 'target'
        $cmp = @(Compare-PbCapture $stage $res[0].Files $target)
        Check 'сравнение: новый файл' ($cmp[0].State -eq 'new' -and $cmp[0].Added -eq 5) $cmp[0]
        Copy-PbCapture $stage $res[0].Files $target
        Check 'сравнение: без изменений' ((@(Compare-PbCapture $stage $res[0].Files $target))[0].State -eq 'same')
        Write-PbText (Join-Path $home2 '.gitconfig') ($gc + '    lg = log --oneline')
        $res = @(Invoke-PbCapture @($app) $stage)
        $cmp = @(Compare-PbCapture $stage $res[0].Files $target)
        Check 'сравнение: изменён, +1' ($cmp[0].State -eq 'changed' -and $cmp[0].Added -eq 1 -and $cmp[0].Deleted -eq 0) $cmp[0]
        $res = @(Invoke-PbCapture @(@{ Id = 'npp'; Name = 'Notepad++'; Config = @{ Export = 'Export-NppConfig' } }) $stage)
        Check 'нет настроек — ошибка, без исключения' ([bool]$res[0].Error) $res[0]
        # Vivaldi: только поддерево vivaldi, без синхронизации и токенов; вкладка видит только то, что есть на компьютере
        $oldLa = $env:LOCALAPPDATA; $env:LOCALAPPDATA = Join-Path $tmp 'la'
        try {
            $pd = Join-Path $env:LOCALAPPDATA (Join-Path 'Vivaldi' (Join-Path 'User Data' 'Default'))
            New-Item -ItemType Directory -Path $pd -Force | Out-Null
            '{"profile":{"name":"user"},"vivaldi":{"theme":{"current":"dark"},"sync":{"server":"x"},"mail":{"on":true},"tabs":{"stack":true}}}' | Set-Content (Join-Path $pd 'Preferences') -Encoding UTF8
            $catalog = (Import-PowerShellDataFile (Join-Path (Join-Path $root 'catalog') 'apps.psd1')).Apps
            $cap = @(Get-PbCaptureApps $catalog)
            Check 'вкладка: 19 программ, на «компьютере» есть Git и Vivaldi' ($cap.Count -eq 19 -and (($cap | Where-Object Installed | ForEach-Object { $_.App.Id }) -join ',') -eq 'git,vivaldi') ($cap | ForEach-Object { "$($_.App.Id)=$($_.Installed)" })
            $res = @(Invoke-PbCapture @($catalog | Where-Object { $_.Id -eq 'vivaldi' }) $stage)
            $v = Get-Content (Join-Path $stage $res[0].Files[0]) -Raw -Encoding UTF8 | ConvertFrom-Json
            Check 'vivaldi: тема и вкладки есть, sync и mail вырезаны, profile не взят' ($v.vivaldi.theme.current -eq 'dark' -and $v.vivaldi.tabs.stack -and -not $v.vivaldi.sync -and -not $v.vivaldi.mail -and -not $v.profile -and $res[0].Removed.Count -eq 2) @($v, $res[0].Removed)
        } finally { $env:LOCALAPPDATA = $oldLa }
        Check '{MyDocuments} раскрывается' ((Expand-PbPath '{MyDocuments}\x') -eq ([Environment]::GetFolderPath('MyDocuments') + [IO.Path]::DirectorySeparatorChar + 'x'))
        # применение Git сохраняет вход в GitHub на целевом компьютере
        $script:PB.DataRoot = $target | Split-Path; Rename-Item $target 'configs'
        Write-PbText (Join-Path $home2 '.gitconfig') @('[credential "https://github.com"]', '    helper = target-helper')
        Set-GitConfig
        $after = @(Get-Content (Join-Path $home2 '.gitconfig') -Encoding UTF8)
        Check 'git: применение сохраняет credential компьютера' (($after -contains '    helper = target-helper') -and ($after -contains '    st = status') -and -not ($after -match 'gh auth')) $after
    } finally { $env:USERPROFILE = $oldProfile }

    # ---------- пути профиля, вторая партия, реестр ----------
    Write-Host 'пути профиля и вторая партия'
    $saved = @{}; foreach ($n in 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        $u = 'C:\' + 'Users\user'   # склеено, чтобы проверка на личное (C:\Users\<имя>) не срабатывала на пример
        $env:USERPROFILE = $u; $env:APPDATA = "$u\AppData\Roaming"; $env:LOCALAPPDATA = "$u\AppData\Local"
        $t = @("path=$u\AppData\Roaming\Wireshark\x", ('"p": "' + $u.Replace('\', '\\') + '\\AppData\\Local\\Programs\\code.cmd",'),
            'file = c:/users/user/.ssh/config', "other = $($u)name\x", "home=$u") -join "`n"
        $p = ConvertTo-PbPortablePath $t
        $exp = @('path=%APPDATA%\Wireshark\x', '"p": "%LOCALAPPDATA%\\Programs\\code.cmd",', 'file = %USERPROFILE%/.ssh/config', "other = $($u)name\x", 'home=%USERPROFILE%') -join "`n"
        Check 'пути → переменные: \, \\, /, регистр, чужой профиль не задет' ($p -eq $exp) $p
        $env:USERPROFILE = 'D:\Профили\Пётр'; $env:APPDATA = 'D:\Профили\Пётр\AppData\Roaming'; $env:LOCALAPPDATA = 'D:\Профили\Пётр\AppData\Local'
        Check 'переменные → пути другого компьютера, текст' ((Expand-PbPortablePath 'path=%APPDATA%\Wireshark x=%userprofile%/.ssh') -eq 'path=D:\Профили\Пётр\AppData\Roaming\Wireshark x=D:/Профили/Пётр/.ssh')
        Check 'переменные → пути, JSON' ((Expand-PbPortablePath '"p": "%LOCALAPPDATA%\\Programs"' $true) -eq '"p": "D:\\Профили\\Пётр\\AppData\\Local\\Programs"')
        $env:USERPROFILE = Join-Path $tmp 'u2'; $env:APPDATA = Join-Path $env:USERPROFILE 'Roaming'; $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'Local'

        # снятие: пути заменяются во всех файлах, кодировка UTF-16 сохраняется
        $ws = Join-Path $env:APPDATA 'Wireshark'
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $ws 'profiles') 'Work') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $ws 'preferences'), "gui.fileopen.dir: $(Join-Path $env:USERPROFILE 'caps')`n", (New-Object Text.UTF8Encoding $false))
        [IO.File]::WriteAllText((Join-Path $ws 'recent'), "recent.capture_file: x.pcap`n")
        [IO.File]::WriteAllText((Join-Path (Join-Path (Join-Path $ws 'profiles') 'Work') 'colorfilters'), "@TCP@tcp@[0,0,0]`n")
        [IO.File]::WriteAllText((Join-Path (Join-Path (Join-Path $ws 'profiles') 'Work') 'recent_common'), "x`n")
        $st2 = Join-Path $tmp 'stage2'
        $res = @(Invoke-PbCapture @(@{ Id = 'wireshark'; Name = 'Wireshark'; Config = @{ Export = 'Export-WiresharkConfig' } }) $st2)
        $prefs = Get-Content (Join-Path $st2 (Join-Path 'wireshark' 'preferences')) -Raw -Encoding UTF8
        Check 'wireshark: recent не взяты, профиль взят' (-not $res[0].Error -and $res[0].Files.Count -eq 2 -and -not ($res[0].Files -match 'recent')) $res[0]
        Check 'wireshark: путь профиля заменён на %USERPROFILE%' ($prefs -match '%USERPROFILE%' -and $prefs -notmatch [regex]::Escape($env:USERPROFILE)) $prefs
        $u16 = Join-Path $tmp 'u16.txt'
        [IO.File]::WriteAllText($u16, "a=$($env:APPDATA)\x", (New-Object Text.UnicodeEncoding $false, $true))
        Convert-PbTextFile $u16 { param($t) ConvertTo-PbPortablePath $t }
        $b = [IO.File]::ReadAllBytes($u16)
        Check 'UTF-16 остаётся UTF-16' ($b[0] -eq 0xFF -and $b[1] -eq 0xFE -and (Read-PbTextFile $u16).Text -eq 'a=%APPDATA%\x')

        # применение раскрывает переменные под этот компьютер
        $script:PB.DataRoot = Join-Path $tmp 'data2'
        Copy-PbCapture $st2 $res[0].Files (Join-Path $script:PB.DataRoot 'configs')
        Remove-Item $ws -Recurse -Force
        Set-WiresharkConfig | Out-Null
        $back = Get-Content (Join-Path $ws 'preferences') -Raw -Encoding UTF8
        Check 'wireshark: применение раскрыло путь' ($back -match [regex]::Escape((Join-Path $env:USERPROFILE 'caps'))) $back

        # KeePassXC: пути к базам и Last… вырезаются; SumatraPDF: блоки FileStates и SessionData
        $kp = Join-Path $env:APPDATA 'KeePassXC'; New-Item -ItemType Directory -Path $kp -Force | Out-Null
        Write-PbText (Join-Path $kp 'keepassxc.ini') @('[General]', 'ConfigVersion=2', 'LastDatabases=C:/db.kdbx', 'LastKeyFiles=@Variant(x)', 'LastDir=C:/x', '[Security]', 'LockDatabaseIdle=true')
        $res = @(Invoke-PbCapture @(@{ Id = 'keepassxc'; Name = 'KeePassXC'; Config = @{ Export = 'Export-KeePassXCConfig' } }) $st2)
        $ini = @(Get-Content (Join-Path $st2 $res[0].Files[0]) -Encoding UTF8)
        Check 'keepassxc: Last… вырезаны' (($ini -join '|') -eq '[General]|ConfigVersion=2|[Security]|LockDatabaseIdle=true' -and $res[0].Removed.Count -eq 3) $ini
        $su = Join-Path $env:LOCALAPPDATA 'SumatraPDF'; New-Item -ItemType Directory -Path $su -Force | Out-Null
        Write-PbText (Join-Path $su 'SumatraPDF-settings.txt') @('Theme = Dark', 'FileStates [', '  [', '    FilePath = C:\doc.pdf', '  ]', ']', 'SessionData [', ']', 'ZoomDefault = fit page', 'TimeOfLastUpdateCheck = 0 0')
        $res = @(Invoke-PbCapture @(@{ Id = 'sumatra'; Name = 'SumatraPDF'; Config = @{ Export = 'Export-SumatraConfig' } }) $st2)
        $su2 = @(Get-Content (Join-Path $st2 $res[0].Files[0]) -Encoding UTF8)
        Check 'sumatra: без FileStates, SessionData и служебного' (($su2 -join '|') -eq 'Theme = Dark|ZoomDefault = fit page') $su2

        # реестр: JSON → Set-Reg (подменён: в тестах реестр не трогаем), вырезанное фильтром не пишется
        $script:Calls = New-Object System.Collections.ArrayList
        function Set-Reg { param($Path, $Name, $Value, $Type) [void]$script:Calls.Add("$Path|$Name|$Type|$(@($Value) -join ',')") }
        $rj = Join-Path $tmp 'reg.json'
        [IO.File]::WriteAllText($rj, '{ "Values": { "Theme": { "Kind": "DWord", "Data": 2 }, "Editor": { "Kind": "String", "Data": "%LOCALAPPDATA%\\Programs\\x.exe" }, "Cut": { "Kind": "String" } },
          "Keys": { "Interface": { "Values": { "Big": { "Kind": "QWord", "Data": 5000000000 }, "List": { "Kind": "MultiString", "Data": [ "a", "b" ] }, "Bin": { "Kind": "Binary", "Data": "AQID" } } } } }')
        $n = Import-PbRegJson $rj 'Software\Test'
        Check 'реестр: 5 значений через Set-Reg, вырезанное пропущено' ($n -eq 5 -and $script:Calls.Count -eq 5) $script:Calls
        Check 'реестр: типы и раскрытый путь' (($script:Calls -contains 'HKCU:\Software\Test|Theme|DWord|2') -and ($script:Calls -contains "HKCU:\Software\Test|Editor|String|$($env:LOCALAPPDATA)\Programs\x.exe") -and
            ($script:Calls -contains 'HKCU:\Software\Test\Interface|Big|QWord|5000000000') -and ($script:Calls -contains 'HKCU:\Software\Test\Interface|List|MultiString|a,b') -and
            ($script:Calls -contains 'HKCU:\Software\Test\Interface|Bin|Binary|1,2,3')) $script:Calls
        Remove-Item function:Set-Reg
    } finally { foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) } }

    # ---------- разметка репозитория данных ----------
    Write-Host 'разметка'
    function New-TestRepo ([string]$Name) {
        $d = Join-Path $tmp $Name
        & git init -q $d
        & git -C $d config user.name test; & git -C $d config user.email test@example.com; & git -C $d config core.autocrlf false
        return $d
    }
    $script:PB.DataRoot = New-TestRepo 'fresh'
    [IO.File]::WriteAllText((Join-Path $script:PB.DataRoot 'README.md'), "# tabula-rasa-private`n")
    & git -C $script:PB.DataRoot add -A; & git -C $script:PB.DataRoot commit -q -m init
    Check 'новый репозиторий — empty' ((Get-PbDataLayout) -eq 'empty') (Get-PbDataLayout)
    $plan = Get-PbLayoutPlan -Fresh
    Install-PbDataLayout $plan
    $files = @((Invoke-PbGit ls-files).Out)
    Check 'разметка: все файлы одним коммитом' ((Get-PbDataLayout) -eq 'ok' -and $files -contains 'tabula-rasa.json' -and $files -contains 'catalog/apps.psd1' -and $files -contains 'saves/.gitkeep' -and $files -contains '.gitignore' -and @((Invoke-PbGit log --oneline).Out).Count -eq 2) $files
    Check 'README заменён' ((Get-Content (Join-Path $script:PB.DataRoot 'README.md') -Raw -Encoding UTF8) -match 'Мои данные Tabula Rasa')
    Check 'пустой каталог читается' ((Read-PbUserCatalog @()).Errors.Count -eq 0)
    Check 'после разметки план пуст' (@(Get-PbLayoutPlan).Count -eq 0) (Get-PbLayoutPlan)

    $script:PB.DataRoot = New-TestRepo 'foreign'
    $r = $script:PB.DataRoot
    New-Item -ItemType Directory (Join-Path $r 'docs') | Out-Null
    [IO.File]::WriteAllText((Join-Path $r 'README.md'), "# Свои данные`n`nМой журнал и планы.`nЕщё строка.`n")
    [IO.File]::WriteAllText((Join-Path (Join-Path $r 'docs') 'plan.md'), "план`n")
    [IO.File]::WriteAllText((Join-Path $r '.gitignore'), "*.log`nsecrets/`n")
    New-Item -ItemType Directory (Join-Path $r 'saves') | Out-Null
    [IO.File]::WriteAllText((Join-Path (Join-Path $r 'saves') 'a.json'), '{}')
    & git -C $r add -A; & git -C $r commit -q -m init
    Check 'чужой репозиторий — foreign' ((Get-PbDataLayout) -eq 'foreign') (Get-PbDataLayout)
    $plan = Get-PbLayoutPlan
    $rels = @($plan | ForEach-Object { $_.Rel })
    Check 'foreign: README и saves не трогаются' ($rels -notcontains 'README.md' -and $rels -notcontains 'saves/.gitkeep' -and $rels -contains 'configs/.gitkeep' -and $rels -contains 'catalog/apps.psd1') $rels
    Check 'foreign: .gitignore дополняется, *.log не повторяется' (($plan | Where-Object { $_.Rel -eq '.gitignore' }).Append -notcontains '*.log') $plan
    $before = (Get-Content (Join-Path $r 'README.md') -Raw -Encoding UTF8)
    Install-PbDataLayout $plan
    $gi = Get-Content (Join-Path $r '.gitignore') -Encoding UTF8
    Check 'foreign: ничего не удалено и не перезаписано' ((Get-Content (Join-Path $r 'README.md') -Raw -Encoding UTF8) -eq $before -and (Test-Path (Join-Path (Join-Path $r 'docs') 'plan.md')) -and $gi[0] -eq '*.log' -and $gi -contains '*.kdbx' -and (Get-PbDataLayout) -eq 'ok') $gi

    [IO.File]::WriteAllText((Join-Path $r 'tabula-rasa.json'), '{ "format": 99 }')
    Check 'манифест новее — только чтение' ((Get-PbDataLayout) -eq 'new' -and (Test-PbDataReadOnly))
    $blocked = $false
    try { Save-PbSave 'x' @{ Apps = @(); Tweaks = @(); Configs = @(); Files = @() } | Out-Null } catch { $blocked = $_.Exception.Message -match 'Обновите программу' }
    Check 'только чтение: сохранение не записывается' ($blocked -and -not (Test-Path (Join-Path (Join-Path $r 'saves') 'x.json')))
    $blocked = $false
    try { Add-PbUserApp @{ Id = 'my.x'; Name = 'X'; WingetId = 'X.X' } @() } catch { $blocked = $true }
    Check 'только чтение: каталог не меняется' $blocked

    # ---------- надёжность прогона: таймаут winget, коды, журнал изменений, кеш model.cs ----------
    Write-Host 'надёжность прогона'
    $script:PB.LogDir = Join-Path $tmp 'logs'
    $ps = (Get-Process -Id $PID).Path   # тот же PowerShell вместо winget: спит дольше лимита
    $r = Invoke-PbWingetTimed @('-NoProfile', '-Command', '[Console]::OutputEncoding = [Text.Encoding]::UTF8; Write-Output начало; Start-Sleep 60') 0.05 'test.slow' $ps
    Check 'таймаут: процесс снят через ~3 с, кода нет' ($r.TimedOut -and $null -eq $r.Code -and $r.Seconds -lt 15) $r
    Check 'таймаут: вывод в отдельном журнале' ((Get-Content $r.Log -Raw -Encoding UTF8) -match 'начало') (Get-Content $r.Log -Raw -Encoding UTF8)
    $r = Invoke-PbWingetTimed @('-NoProfile', '-Command', '[Console]::OutputEncoding = [Text.Encoding]::UTF8; Write-Output "с пробелом"; exit 7') 1 'test.code' $ps
    Check 'код выхода и аргумент с пробелами' (-not $r.TimedOut -and $r.Code -eq 7 -and (Get-Content $r.Log -Raw -Encoding UTF8) -match 'с пробелом') $r
    Check 'вывод возвращается строками (для поиска)' (@($r.Out) -contains 'с пробелом') $r.Out
    Check 'коды winget: уже установлено, нет пакета, система не поддерживает' ((Get-PbWingetCodeInfo -1978335135).Ok -and -not (Get-PbWingetCodeInfo -1978335212).Ok -and
        (Get-PbWingetCodeInfo -1978334957).Text -match 'не поддерживает' -and (Get-PbWingetCodeInfo 5).Text -match '0x00000005')
    $script:PB.Changes.Clear()
    Add-PbChange ([ordered]@{ Kind = 'Reg'; Path = 'HKCU:\Software\X'; Name = 'A' })
    $j = Join-Path $script:PB.LogDir "changes_$($script:PB.Stamp).json"
    Check 'журнал изменений пишется сразу, без конца прогона' ((Test-Path $j) -and (@(Get-Content $j -Raw -Encoding UTF8 | ConvertFrom-Json)).Count -eq 1)
    $mc = Join-Path $tmp 'modelcache'
    $probe = "`$ErrorActionPreference = 'Stop'; . '$((Join-Path (Join-Path $root 'lib') 'common.ps1'))'; `$script:PbUiDir = '$((Join-Path (Join-Path $root 'lib') 'ui'))'; " +
        "`$a = [Management.Automation.Language.Parser]::ParseFile('$((Join-Path (Join-Path $root 'lib') 'gui.ps1'))', [ref]`$null, [ref]`$null); " +
        "`$f = `$a.FindAll({ `$args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and `$args[0].Name -eq 'Import-PbModel' }, `$true)[0]; " +
        ". ([scriptblock]::Create(`$f.Extent.Text)); Import-PbModel '$mc'; ([type]'PcBase.Item').Assembly.Location"
    $first = & $ps -NoProfile -Command $probe
    $second = & $ps -NoProfile -Command $probe
    Check 'model.cs: собран в кеш один раз и загружается из него' ($first -like "$mc*" -and $second -eq $first -and @(Get-ChildItem $mc -Filter *.dll).Count -eq 1) @($first, $second)

    # ---------- статус твиков (CheckOnly): чтение подменено, в тестах ничего не меняется ----------
    Write-Host 'статус твиков'
    . (Join-Path (Join-Path $root 'lib') 'common.ps1')   # настоящий Set-Reg: секция про реестр выше подменяла его
    $script:PB.Root = $root; $script:PB.LogDir = Join-Path $tmp 'logs'
    $script:FakeReg = @{ 'HKCU:\X|A' = 1; 'HKCU:\X|B' = 0; 'HKCU:\X|S' = 'abc'; 'HKCU:\X|M' = @('a', 'b'); 'HKCU:\X|N' = -1 }
    function Get-PbRegValue ([string]$Path, [string]$Name) { $k = "$Path|$Name"; if ($script:FakeReg.ContainsKey($k)) { @{ Exists = $true; Value = $script:FakeReg[$k] } } else { @{ Exists = $false } } }
    function Get-PbSvcMode ([string]$Name) { @{ DiagTrack = 'Disabled'; Other = 'Auto' }[$Name] }
    function Get-PbTaskState ([string]$P, [string]$N) { @{ T1 = 'Disabled'; T2 = 'Ready' }[$N] }
    function Test-PbAppxPresent ([string]$Name) { $Name -eq 'Still.There' }
    $before = $script:PB.Changes.Count
    $tw = @(
        @{ Id = 't.all'; Apply = { Set-Reg 'HKCU:\X' 'A' 1; Set-Reg 'HKCU:\X' 'S' 'abc' -Type String; Set-Reg 'HKCU:\X' 'M' @('a', 'b') -Type MultiString; Set-Reg 'HKCU:\X' 'N' 0xFFFFFFFF; Set-SvcStart 'DiagTrack' 'Disabled'; Disable-Task '\' 'T1' } }
        @{ Id = 't.part'; Apply = { Set-Reg 'HKCU:\X' 'A' 1; Set-Reg 'HKCU:\X' 'B' 1; Disable-Task '\' 'T2' } }
        @{ Id = 't.no'; Apply = { Set-Reg 'HKCU:\X' 'Missing' 1; Set-SvcStart 'Other' 'Disabled' } }
        @{ Id = 't.appx'; Apply = { Remove-Appx @('Gone.App', 'Still.There') } }
        @{ Id = 't.unsafe'; Apply = { Set-Reg 'HKCU:\X' 'A' 1; & powercfg.exe /hibernate off } }
        @{ Id = 't.nothing'; Apply = { Set-SvcStart 'NoSuchService' 'Disabled' } }
        @{ Id = 't.check'; Check = { $true }; Apply = { Stop-Process -Name explorer } }
    )
    $st = @($tw | ForEach-Object { "$($_.Id)=$(Get-PbTweakStatus $_)" }) -join ' '
    Check 'твики: применено / частично / нет / Appx / небезопасный / нечего проверять / свой Check' ($st -eq 't.all=applied t.part=partial t.no=no t.appx=partial t.unsafe=unknown t.nothing=unknown t.check=applied') $st
    Check 'проверка ничего не пишет в журнал изменений' ($script:PB.Changes.Count -eq $before -and -not $script:PB.CheckOnly)
    . (Join-Path (Join-Path $root 'catalog') 'tweaks.ps1')
    $unk = @($Tweaks | Where-Object { -not $_.Check -and -not (Test-PbTweakCheckable $_) } | ForEach-Object { $_.Id }) -join ','
    Check 'каталог: без проверки только env.terminal, env.pwshprofile, env.upgrade' ($unk -eq 'env.terminal,env.pwshprofile,env.upgrade') $unk
    foreach ($f in 'Get-PbRegValue', 'Get-PbSvcMode', 'Get-PbTaskState', 'Test-PbAppxPresent') { Remove-Item "function:$f" }
    . (Join-Path (Join-Path $root 'lib') 'common.ps1')   # вернуть настоящие функции чтения
    $script:PB.Root = $root

    # ---------- статус программ ----------
    Write-Host 'статус программ'
    $en = @("`r  - `r",
        'Name               Id                    Version      Available    Source',
        '---------------------------------------------------------------------------',
        'Git                Git.Git               2.46.0       2.47.1       winget',
        'Notepad++ (64-bit) Notepad++.Notepad++   8.7.1                     winget',
        'Windows Terminal   Microsoft.WindowsTer… 1.21                      winget')
    $w = ConvertFrom-PbWingetList $en
    Check 'winget list en: обновление, без обновления, усечённый id отброшен' ($w['git.git'].Available -eq '2.47.1' -and $w['notepad++.notepad++'].Version -eq '8.7.1' -and -not $w['notepad++.notepad++'].Available -and $w.Count -eq 2) ($w | ConvertTo-Json)
    $ru = @('Имя            ИД                    Версия   Доступно',
        '--------------------------------------------------------',
        '7-Zip 24.08    7zip.7zip             24.08',
        'Vivaldi        Vivaldi.Vivaldi       6.9.1    7.0.3215')
    $w2 = ConvertFrom-PbWingetList $ru
    Check 'winget list ru: 4 колонки, «Доступно» четвёртая' ($w2['vivaldi.vivaldi'].Available -eq '7.0.3215' -and $w2['7zip.7zip'].Version -eq '24.08' -and -not $w2['7zip.7zip'].Available) ($w2 | ConvertTo-Json)
    $w3 = ConvertFrom-PbWingetList @('Name  Id       Version Source', '------------------------------', 'Ditto Ditto.Ditto 3.24 winget')
    Check 'winget list: 4 колонки с «Источником» — не обновление' (-not $w3['ditto.ditto'].Available) ($w3 | ConvertTo-Json)
    $entries = @(@{ Name = 'Git version 2.46.0'; Version = '2.46.0' }, @{ Name = 'GitHub CLI'; Version = '2.60' }, @{ Name = 'Npcap 1.80'; Version = '1.80' })
    Check 'реестр: «Git» не путается с «GitHub CLI», Detect для сайта' ((Find-PbUninstallEntry @{ Name = 'Git' } $entries).Version -eq '2.46.0' -and (Find-PbUninstallEntry @{ Name = 'GitHub CLI' } $entries).Version -eq '2.60' -and
        (Find-PbUninstallEntry @{ Name = 'Npcap'; Detect = 'Npcap*' } $entries) -and -not (Find-PbUninstallEntry @{ Name = 'Gi' } $entries))
    $git = @{ Id = 'git'; Name = 'Git'; WingetId = 'Git.Git' }; $vs = @{ Id = 'vscode'; Name = 'VS Code'; WingetId = 'Microsoft.VisualStudioCode' }
    $np = @{ Id = 'npcap'; Name = 'Npcap'; Source = 'web'; Detect = 'Nothing*' }
    $s1 = @((Get-PbAppStatus $git $entries $null).Kind, (Get-PbAppStatus $vs $entries $null).Kind, (Get-PbAppStatus $np $entries $null).Kind) -join ','
    Check 'шаг 1 (реестр): установлено / неизвестно до winget / сайт — не установлено' ($s1 -eq 'installed,unknown,missing') $s1
    $s2 = Get-PbAppStatus $git $entries $w; $s3 = Get-PbAppStatus $vs $entries $w
    Check 'шаг 2 (winget): обновление с версиями, нет в winget и реестре — не установлено' ($s2.Kind -eq 'update' -and $s2.Text -eq 'обновление: 2.46.0 → 2.47.1' -and $s3.Kind -eq 'missing') @($s2, $s3)

    # ---------- «уже было» и «изменено»: запись только при отличии (чтение и запись подменены) ----------
    Write-Host 'уже было и изменено'
    $script:PB.Changes.Clear(); $script:PB.Actions.Clear(); $script:PB.Results.Clear(); $script:PB.LogDir = Join-Path $tmp 'logs0'
    & {
        $script:Reg = @{ 'HKCU:\T|A' = @{ Exists = $true; Value = 1; Kind = 'DWord' }; 'HKCU:\T|B' = @{ Exists = $true; Value = '1'; Kind = 'String' } }
        $script:Writes = New-Object System.Collections.ArrayList
        function Get-PbRegValue ($Path, $Name) { $v = $script:Reg["$Path|$Name"]; if ($v) { $v } else { @{ Exists = $false; Value = $null } } }
        function Test-Path { $true }
        function New-Item { }
        function New-ItemProperty ($Path, $Name, $Value, $PropertyType) { [void]$script:Writes.Add("$Name=$Value"); $script:Reg["$Path|$Name"] = @{ Exists = $true; Value = $Value; Kind = $PropertyType } }
        Set-Reg 'HKCU:\T' 'A' 1
        Check 'Set-Reg: то же значение — не пишется, в журнал не попадает' ($script:Writes.Count -eq 0 -and $script:PB.Changes.Count -eq 0 -and $script:PB.Actions.Count -eq 1 -and -not $script:PB.Actions[0].Changed) $script:PB.Actions
        Set-Reg 'HKCU:\T' 'A' 0
        Check 'Set-Reg: другое значение — пишется, в журнале «было 1»' ($script:Writes -contains 'A=0' -and $script:PB.Changes.Count -eq 1 -and $script:PB.Changes[0].Old -eq 1 -and
            $script:PB.Actions[1].Changed -and $script:PB.Actions[1].Old -eq '1' -and $script:PB.Actions[1].New -eq '0') $script:PB.Actions[1]
        Set-Reg 'HKCU:\T' 'B' 1
        Check 'Set-Reg: то же число, но строкой — переписывается в DWord' ($script:Writes -contains 'B=1' -and $script:PB.Changes.Count -eq 2)
        Set-Reg 'HKCU:\T' 'C' 'x' 'String'
        Check 'Set-Reg: значения не было — «нет → x»' ($script:PB.Actions[3].Old -eq 'нет' -and $script:PB.Actions[3].New -eq 'x' -and -not $script:PB.Changes[2].OldExists)

        $script:Svc = 'Disabled'; $script:SvcSet = $null
        function Get-PbSvcMode ($Name) { $script:Svc }
        function Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        function Set-Service ($Name, $StartupType) { $script:SvcSet = $StartupType }
        $n = $script:PB.Changes.Count
        Set-SvcStart 'DiagTrack' 'Disabled'
        Check 'Set-SvcStart: уже отключена — не трогается' ($null -eq $script:SvcSet -and $script:PB.Changes.Count -eq $n -and $script:PB.Actions[-1].New -eq 'отключена' -and -not $script:PB.Actions[-1].Changed)
        $script:Svc = 'Auto'
        Set-SvcStart 'DiagTrack' 'Disabled'
        Check 'Set-SvcStart: была «автоматически» — отключена, в журнале' ($script:SvcSet -eq 'Disabled' -and $script:PB.Changes[-1].Old -eq 'Auto' -and $script:PB.Actions[-1].Old -eq 'автоматически')

        $script:Task = 'Disabled'; $script:TaskOff = 0
        function Get-PbTaskState ($TaskPath, $TaskName) { $script:Task }
        function Disable-ScheduledTask { $script:TaskOff++ }
        $n = $script:PB.Changes.Count
        Disable-Task '\X\' 'T1'
        Check 'Disable-Task: уже отключена — не трогается, в журнал не попадает' ($script:TaskOff -eq 0 -and $script:PB.Changes.Count -eq $n)
        $script:Task = 'Ready'
        Disable-Task '\X\' 'T1'
        Check 'Disable-Task: включённая — отключена, в журнале' ($script:TaskOff -eq 1 -and $script:PB.Changes[-1].WasEnabled)

        # итог твика
        $script:Reg = @{ 'HKCU:\T|A' = @{ Exists = $true; Value = 1; Kind = 'DWord' }; 'HKCU:\T|B' = @{ Exists = $true; Value = 1; Kind = 'DWord' } }
        $script:PB.Results.Clear()
        Invoke-Tweak @{ Name = 'Т1'; Apply = { Set-Reg 'HKCU:\T' 'A' 1; Set-Reg 'HKCU:\T' 'B' 1 }; Manual = 'не нужно' } 6>$null
        Invoke-Tweak @{ Name = 'Т2'; Apply = { Set-Reg 'HKCU:\T' 'A' 1; Set-Reg 'HKCU:\T' 'B' 0 } } 6>$null
        Invoke-Tweak @{ Name = 'Т3'; Apply = { Set-Reg 'HKCU:\T' 'C' 1 } } 6>$null
        $script:ApplyRan = $false
        Invoke-Tweak @{ Name = 'Т4'; Check = { $true }; Apply = { $script:ApplyRan = $true } } 6>$null
        $r = @($script:PB.Results | ForEach-Object { "$($_.'Что')=$($_.'Статус')/$($_.'Детали')" }) -join ' | '
        Check 'твик: «уже было», «изменено 1 из 2», «применено», Check выполнен — Apply не запускается' (
            $r -eq 'Т1=уже было/ | Т2=применено/изменено 1 из 2, остальное уже было | Т3=применено/ | Т4=уже было/' -and -not $script:ApplyRan -and -not $script:PB.Manual.Contains('Т1: не нужно')) $r
        $st = Get-PbStepState @($script:PB.Results[0])
        $st2 = Get-PbStepState @($script:PB.Results[1])
        Check 'шаг: «уже было» — состояние same, частично — done с подробностью' ($st.State -eq 'same' -and $st2.State -eq 'done' -and $st2.Detail -match 'изменено 1 из 2') @($st, $st2)

        # программы: версии из winget list до и после, коды «уже установлено» и «новее нет»
        $script:Ver = @{}; $script:Code = 0
        function Invoke-PbWingetTimed ($WingetArgs) {
            if ($WingetArgs[0] -eq 'list') {
                $v = $script:Ver[$WingetArgs[2]]
                if (-not $v) { return @{ Code = -1978335212; Out = @() } }
                return @{ Code = 0; Out = @('Name    Id       Version  Available Source', '-----------------------------------------', ('Prog    {0,-8} {1,-8} {2,-9} winget' -f $WingetArgs[2], $v[0], $v[1])) }
            }
            $id = $WingetArgs[2]
            if ($script:Code -eq 0) { $script:Ver[$id] = @($script:NewVer, '') }
            return @{ Code = $script:Code; Log = 'x.log' }
        }
        $script:PB.Results.Clear(); $script:PB.Upgrades = @('u2', 'u3')
        $script:Ver['A.One'] = @('1.2', ''); $script:Ver['A.Two'] = @('1.0', '1.1'); $script:Ver['A.Thr'] = @('3.0', '')
        Install-WingetApp @{ Id = 'u1'; Name = 'П1'; WingetId = 'A.One' } 6>$null
        $script:NewVer = '1.1'; Install-WingetApp @{ Id = 'u2'; Name = 'П2'; WingetId = 'A.Two' } 6>$null
        $script:Code = -1978335189; Install-WingetApp @{ Id = 'u3'; Name = 'П3'; WingetId = 'A.Thr' } 6>$null
        $script:Code = 0; $script:NewVer = '2.0'; Install-WingetApp @{ Id = 'u4'; Name = 'П4'; WingetId = 'A.New' } 6>$null
        $r = @($script:PB.Results | ForEach-Object { "$($_.'Что')=$($_.'Статус')/$($_.'Детали')" }) -join ' | '
        Check 'программы: уже установлено (версия), обновлено (было → стало), новее нет, установлено (версия)' (
            $r -eq 'П1=уже установлено/версия 1.2 | П2=обновлено/1.0 → 1.1 | П3=уже установлено/версия 3.0, новее нет | П4=установлено/версия 2.0') $r
        # Э7: переустановка (--force) и удаление
        $script:WgCalls = New-Object System.Collections.ArrayList
        function Invoke-PbWingetTimed ($WingetArgs) {
            [void]$script:WgCalls.Add(($WingetArgs -join ' '))
            if ($WingetArgs[0] -eq 'list') {
                $v = $script:Ver[$WingetArgs[2]]
                if (-not $v) { return @{ Code = -1978335212; Out = @() } }
                return @{ Code = 0; Out = @('Name    Id       Version  Available Source', '-----------------------------------------', ('Prog    {0,-8} {1,-8} {2,-9} winget' -f $WingetArgs[2], $v[0], $v[1])) }
            }
            if ($WingetArgs[0] -eq 'uninstall') { if ($script:Code -eq 0) { $script:Ver.Remove($WingetArgs[2]) }; return @{ Code = $script:Code; Log = 'x.log' } }
            if ($script:Code -eq 0) { $script:Ver[$WingetArgs[2]] = @($script:NewVer, '') }
            return @{ Code = $script:Code; Log = 'x.log' }
        }
        $script:PB.Results.Clear(); $script:PB.Reinstall = @('r1'); $script:Code = 0; $script:NewVer = '5.0'
        $script:Ver['A.Re'] = @('5.0', ''); $script:Ver['A.Rm'] = @('2.1', '')
        Install-WingetApp @{ Id = 'r1'; Name = 'П5'; WingetId = 'A.Re' } 6>$null
        Uninstall-WingetApp @{ Id = 'd1'; Name = 'П6'; Source = 'winget'; WingetId = 'A.Rm' } 6>$null
        Uninstall-WingetApp @{ Id = 'd2'; Name = 'П7'; Source = 'winget'; WingetId = 'A.None' } 6>$null
        Uninstall-WingetApp @{ Id = 'd3'; Name = 'П8'; Source = 'web' } 6>$null
        $r = @($script:PB.Results | ForEach-Object { "$($_.'Что')=$($_.'Статус')/$($_.'Детали')" }) -join ' | '
        Check 'Э7: переустановка с --force, удаление, «не установлена», удаление не из winget — ошибка' (
            $r -eq 'П5=переустановлено/версия 5.0 | Удалить: П6=удалено/версия 2.1 | Удалить: П7=уже было/не установлена | Удалить: П8=ОШИБКА/удаление доступно только для программ из winget' -and
            @($script:WgCalls | Where-Object { $_ -match '^install --id A.Re .*--force' }).Count -eq 1 -and @($script:WgCalls | Where-Object { $_ -match '^uninstall --id A.Rm' }).Count -eq 1) $r
        $script:PB.Reinstall = @()
    }
    $script:PB.Upgrades = @(); $script:PB.Actions.Clear(); $script:PB.Manual.Clear()

    # ---------- план и прогон (установка, твики и вопрос подменены) ----------
    Write-Host 'план и прогон'
    $script:PB.Results.Clear(); $script:PB.Manual.Clear(); $script:PB.Changes.Clear(); $script:PB.DataRoot = Join-Path $tmp 'nodata'
    $tws = @(@{ Id = 'p.a'; Name = 'Твик А'; Phase = 'pre'; Apply = {} }, @{ Id = 'p.irr'; Name = 'Удалить X'; Phase = 'pre'; Irreversible = $true; Apply = {} },
             @{ Id = 'p.post'; Name = 'После'; Phase = 'post'; Apply = {} })
    $aps = @(@{ Id = 'a1'; Name = 'Прог 1'; Source = 'winget'; WingetId = 'A.One' }, @{ Id = 'a2'; Name = 'Прог 2'; Source = 'web'; Interactive = $true },
             @{ Id = 'a3'; Name = 'Прог 3'; Source = 'winget'; WingetId = 'A.Three'; Config = @{ File = 'nothing\x.json'; Import = 'Set-NoConfig' } })
    $sel = @{ Apps = @('a1', 'a2', 'a3'); Tweaks = @('p.a', 'p.irr', 'p.post'); Configs = @('a3'); Files = @('f.zip'); FileTitles = @('Файл.zip'); Name = 'PC-02'; Upgrades = @('a1') }
    $stat = @{ Apps = @{ a1 = @{ Kind = 'update'; Text = 'обновление: 1 → 2' }; a3 = @{ Kind = 'installed' } }; Tweaks = @{ 'p.a' = 'applied' } }
    $plan = Get-PbRunPlan $sel $aps $tws $stat
    $ph = ($plan | ForEach-Object { $_.Phase }) -join ''
    Check 'план: фазы по порядку' ($ph -eq '1223334567') $ph
    $pn = @($plan | ForEach-Object { $_.PhaseName } | Select-Object -Unique) -join '|'
    Check 'план: названия фаз совпадают с номерами' ($pn -eq 'Точка восстановления|Настройки Windows|Программы|Настройки программ|Файлы|Среда|Имя компьютера') $pn
    $notes = @{}; foreach ($x in $plan) { $notes[$x.Key] = $x.Note }
    Check 'план: пометки — обновление, уже установлено, сайт и мастер, нет настроек, необратимо, уже применено' ($notes['app:a1'] -eq 'обновление: 1 → 2' -and $notes['app:a3'] -match 'уже установлено' -and
        $notes['app:a2'] -match 'сайта' -and $notes['app:a2'] -match 'мастер' -and $notes['config:a3'] -match 'нет' -and $notes['tweak:p.irr'] -match 'необратимо' -and $notes['tweak:p.a'] -match 'уже применено') ($notes | ConvertTo-Json)
    Check 'план: пусто — пустой план' ((Get-PbRunPlan @{ Apps = @(); Tweaks = @(); Configs = @(); Files = @() } $aps $tws $null).Count -eq 0)

    function Invoke-Tweak ($T) { Add-Result $T.Name 'применено' }
    function Install-App ($A) { if ($A.Id -eq 'a2') { Add-Result $A.Name 'ОШИБКА' 'подпись не прошла' } else { Add-Result $A.Name 'установлено' } }
    function Initialize-Winget { $true }
    function Invoke-PbWingetTimed { @{ Code = 0 } }
    function Set-NoConfig { Add-Result 'Прог 3: мои настройки' 'пропущено' 'нет файла' }
    function Save-PbFiles ($Names) { Add-Result 'Файл' 'загружено' }
    function Rename-Computer { param($NewName, [switch]$Force) }
    function Request-PbAnswer ($Text, $Items) { $script:Asked = @($Items); $false }   # «не выполнять необратимое»
    # отчёт — во временную папку, не в «Документы» этого компьютера
    $script:PB.LogDir = Join-Path $tmp 'logs1'
    function Get-PbReportDir { Join-Path $tmp 'reports' }
    $sync = [hashtable]::Synchronized(@{})
    Invoke-PbRun $plan $sel $aps $tws $sync 6>$null | Out-Null
    $states = ($plan | ForEach-Object { "$($_.Key)=$($_.State)" }) -join ' '
    Check 'прогон: без точки восстановления необратимое снято, ошибка и пропуск видны' ($states -eq 'restore=skip tweak:p.a=done tweak:p.irr=skip app:a1=done app:a2=error app:a3=done config:a3=skip files=done tweak:p.post=done rename=done') $states
    Check 'прогон: спросили про необратимое, итог и флаги' (($script:Asked -join ',') -eq 'Удалить X' -and $sync.Done -and $sync.NeedReboot -and ($plan | Where-Object Key -eq 'app:a2').Detail -match 'подпись' -and $script:PB.Upgrades -contains 'a1') $sync
    $rep = [string]$sync.Report
    $html = if ($rep -and (Test-Path $rep)) { Get-Content $rep -Raw -Encoding UTF8 } else { '' }
    Check 'отчёт: в папке отчётов и копия в журналах' ($rep -like (Join-Path (Join-Path $tmp 'reports') 'report_*.html') -and
        (Test-Path (Join-Path $script:PB.LogDir (Split-Path $rep -Leaf)))) $rep
    $failBlock = if ($html -match '(?s)Что не получилось(.*?)</div>') { $Matches[1] } else { '' }
    Check 'отчёт: ошибка в «Что не получилось», шаги по фазам, перезагрузка' ($failBlock -match 'Прог 2' -and $failBlock -match 'подпись не прошла' -and $failBlock -notmatch 'Прог 1' -and
        $html -match 'Нужна перезагрузка' -and $html -match 'Настройки Windows' -and $html -match 'class="st error">ошибка' -and $html -match 'Выполнено: 6') ($html.Length)
    $saveEnv = @{ USERPROFILE = $env:USERPROFILE; USERNAME = $env:USERNAME; APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
    try {
        $prof = 'C:\' + 'Users\' + 'jdoe'
        $env:USERPROFILE = $prof; $env:USERNAME = 'jdoe'; $env:APPDATA = "$prof\AppData\Roaming"; $env:LOCALAPPDATA = "$prof\AppData\Local"
        $p1 = Protect-PbReportText "$prof\AppData\Local\X\a.log; $prof\Desktop; пользователь jdoe; jdoe2"
        Check 'отчёт: пути профиля — переменными, имя пользователя скрыто' ($p1 -eq '%LOCALAPPDATA%\X\a.log; %USERPROFILE%\Desktop; пользователь <пользователь>; jdoe2') $p1
        $st = New-PbStep 3 'app' 'app:x' '<script>alert(1)</script> & Co' 'x'; $st.State = 'error'; $st.Detail = "$prof\a.txt"
        $h2 = New-PbReportHtml @($st) @{ Computer = 'PC-01'; Windows = 'Windows 11'; Started = (Get-Date); Finished = (Get-Date); Engine = 'dev'; Manual = @('Войти <в> почту'); LogDir = 'C:\ProgramData\tabula-rasa\logs' }
        Check 'отчёт: HTML экранирован, личного нет' ($h2 -notmatch '<script>alert' -and $h2 -match '&lt;script&gt;' -and $h2 -match '&amp; Co' -and $h2 -match 'Войти &lt;в&gt; почту' -and
            $h2 -notmatch 'jdoe' -and $h2 -match '%USERPROFILE%\\a.txt' -and $h2 -match 'PC-01') ($h2.Length)
        $sa = New-PbStep 2 'tweak' 'tweak:s' 'Тёмная тема' 's'; $sa.State = 'same'; $sa.Detail = 'уже было'
        $sa.Actions = @([ordered]@{ Kind = 'Reg'; Target = 'HKCU:\X\A'; Old = '0'; New = '0'; Changed = $false })
        $sb2 = New-PbStep 2 'tweak' 'tweak:p' 'Телеметрия' 'p'; $sb2.State = 'done'; $sb2.Detail = 'применено, изменено 1 из 2'
        $sb2.Actions = @([ordered]@{ Kind = 'Reg'; Target = 'HKLM:\Y\B'; Old = 'нет'; New = '1'; Changed = $true }, [ordered]@{ Kind = 'Service'; Target = 'служба DiagTrack'; Old = 'отключена'; New = 'отключена'; Changed = $false })
        $h3 = New-PbReportHtml @($sa, $sb2) @{ Computer = 'PC-01'; Windows = 'Windows 11'; Started = (Get-Date); Finished = (Get-Date); Engine = 'dev'; LogDir = 'C:\logs' }
        $same = if ($h3 -match '(?s)Было настроено до прогона(.*?)</div>') { $Matches[1] } else { '' }
        Check 'отчёт: «Было настроено до прогона», «Уже было: 1», раскрывающиеся «было → стало»' ($same -match 'Тёмная тема' -and $same -notmatch 'Телеметрия' -and $h3 -match 'Уже было: 1' -and
            $h3 -match '<summary>изменено 1 из 2</summary>' -and $h3 -match 'нет → <b>1</b>' -and $h3 -match 'отключена <span class="muted">\(уже было\)' -and $h3 -match 'beforeprint') ($h3.Length)
    } finally { foreach ($k in $saveEnv.Keys) { Set-Item "env:$k" $saveEnv[$k] } }
    $pr = Get-PbRunPlan @{ Apps = @('a1'); Tweaks = @(); Configs = @('a3'); Files = @(); Reinstall = @('a1'); Remove = @('a2') } $aps $tws $null
    $k = ($pr | ForEach-Object { "$($_.Kind):$($_.Name)" }) -join ' | '
    Check 'Э7: план — удаление первым в программах и необратимо, переустановка, настройки без установки' (
        $k -eq 'restore:Создать точку восстановления | remove:Удалить: Прог 2 | app:Переустановить: Прог 1 | config:Прог 3: с моими настройками' -and $pr[1].Irreversible -and $pr[1].Phase -eq 3) $k
    $dapps = @(@{ Id = 'ws'; Name = 'Wireshark'; Source = 'winget'; WingetId = 'W.S'; Requires = @('np') }, @{ Id = 'np'; Name = 'Npcap'; Source = 'web' },
               @{ Id = 'dk'; Name = 'Docker'; Source = 'winget'; WingetId = 'D.K'; Requires = @('t.wsl') })
    $dtw = @(@{ Id = 't.wsl'; Name = 'WSL2'; Phase = 'pre'; Apply = {} })
    $dp = Get-PbRunPlan @{ Apps = @('ws', 'dk'); Tweaks = @(); Configs = @(); Files = @() } $dapps $dtw @{ Apps = @{}; Tweaks = @{ 't.wsl' = 'applied' } }
    $dn = @{}; foreach ($x in $dp) { $dn[$x.Key] = $x.Note }
    $dp2 = Get-PbRunPlan @{ Apps = @('ws', 'np'); Tweaks = @(); Configs = @(); Files = @() } $dapps $dtw $null
    Check 'Э8: план — нужное не отмечено: пометка; уже применено или отмечено — без пометки' ($dn['app:ws'] -eq 'требует: Npcap (не отмечено)' -and -not $dn['app:dk'] -and
        -not (@($dp2 | Where-Object { $_.Note -match 'требует' }).Count)) ($dn | ConvertTo-Json)
    $plan2 = Get-PbRunPlan $sel $aps $tws $null
    $sync2 = [hashtable]::Synchronized(@{ StopAfter = $true })
    Invoke-PbRun $plan2 $sel $aps $tws $sync2 6>$null | Out-Null
    Check 'прогон: «остановить» — остальные шаги пропущены' (@($plan2 | Where-Object { $_.State -ne 'skip' }).Count -eq 0 -and ($plan2[1].Detail -eq 'прогон остановлен'))

    # ---------- Э9: продолжение после перезагрузки ----------
    Write-Host 'продолжение после перезагрузки'
    $script:PB.LogDir = Join-Path $tmp 'logs9'; $script:PB.Stamp = '2026-11-01_100000'
    $script:PB.Results.Clear(); $script:PB.Manual.Clear(); $script:PB.Changes.Clear(); $script:PB.NeedReboot = $false
    $rtw = @(@{ Id = 'g.wsl'; Name = 'WSL2'; Phase = 'pre'; RebootGate = $true; Apply = {} }, @{ Id = 'p.x'; Name = 'Твик X'; Phase = 'pre'; Apply = {} })
    $rap = @(@{ Id = 'dk'; Name = 'Docker'; Source = 'winget'; WingetId = 'D.K'; Requires = @('g.wsl') },
             @{ Id = 'n8'; Name = 'Прог N'; Source = 'winget'; WingetId = 'N.8'; Config = @{ File = 'n8\x.json'; Import = 'Set-N8Config' } },
             @{ Id = 'a1'; Name = 'Прог 1'; Source = 'winget'; WingetId = 'A.One' })
    $rsel = @{ Apps = @('dk', 'n8', 'a1'); Tweaks = @('g.wsl', 'p.x'); Configs = @('n8'); Files = @(); Name = $null }
    $rst = @{ Apps = @{}; Tweaks = @{ 'g.wsl' = 'no'; 'p.x' = 'no' } }
    $rp = Get-PbRunPlan $rsel $rap $rtw $rst
    $fc = @(Get-PbRebootForecast $rp $rap $rtw)
    $fc2 = @(Get-PbRebootForecast (Get-PbRunPlan $rsel $rap $rtw @{ Apps = @{}; Tweaks = @{ 'g.wsl' = 'applied'; 'p.x' = 'no' } }) $rap $rtw)
    Check 'Э9: прогноз — перезагрузка перед Docker; WSL уже применён — не ожидается' ($fc.Count -eq 1 -and $fc[0] -eq '«WSL2» перед «Docker»' -and -not $fc2.Count -and
        ($rp | Where-Object Key -eq 'app:dk').Note -match 'после перезагрузки') @($fc + $fc2)

    $script:Calls9 = New-Object System.Collections.ArrayList
    function Invoke-Tweak ($T) { [void]$script:Calls9.Add($T.Id); if ($T.Id -eq 'g.wsl') { $script:PB.NeedReboot = $true }; Add-Result $T.Name 'применено' }
    function Install-App ($A) {
        [void]$script:Calls9.Add($A.Id)
        if ($A.Id -eq 'n8' -and -not $script:N8Ok) { Add-Result $A.Name 'ждёт перезагрузки' 'перед установкой нужна перезагрузка'; $script:PB.RebootFirst = $true }
        else { Add-Result $A.Name 'установлено' }
    }
    function Set-N8Config { [void]$script:Calls9.Add('cfg'); Add-Result 'Прог N: мои настройки' 'применено' }
    function Get-PbBootTime { $script:Boot9 }
    $script:N8Ok = $false; $script:Boot9 = (Get-Date).AddHours(-1); $script:Task9 = $null
    $rp[0].State = 'skip'   # точка восстановления — не на этом компьютере
    $s1 = [hashtable]::Synchronized(@{})
    Invoke-PbRun $rp $rsel $rap $rtw $s1 6>$null | Out-Null
    $st1 = ($rp | ForEach-Object { "$($_.Key)=$($_.State)" }) -join ' '
    Check 'Э9: проход 1 — ждут Docker (после WSL), Прог N и его настройки, остальное выполнено' (
        $st1 -eq 'restore=skip tweak:g.wsl=done tweak:p.x=done app:dk=reboot app:n8=reboot app:a1=done config:n8=reboot' -and ($rp | Where-Object Key -eq 'app:dk').Detail -match 'WSL2') $st1
    $rs = Read-PbResume
    $h1 = if ($s1.Report -and (Test-Path $s1.Report)) { Get-Content $s1.Report -Raw -Encoding UTF8 } else { '' }
    Check 'Э9: пауза — состояние, задача на вход, промежуточный отчёт' ($s1.ResumePending -and $script:Task9 -eq 'on' -and $rs -and $rs.Stamp -eq '2026-11-01_100000' -and
        @($rs.Steps).Count -eq 7 -and (Test-PbResumeOwner $rs) -and $h1 -match 'Прогон продолжится после перезагрузки' -and $h1 -match 'После перезагрузки: 3') $rs

    $script:N8Ok = $true; $script:Boot9 = Get-Date
    $script:PB.Results.Clear(); $script:PB.Stamp = 'другой'; $script:Calls9.Clear()   # должны вернуться из состояния
    $rsel2 = Get-PbResumeSel $rs
    $rp2 = Get-PbRunPlan $rsel2 $rap $rtw $rst
    Restore-PbResumeSteps $rp2 $rs
    $s2 = [hashtable]::Synchronized(@{})
    Invoke-PbRun $rp2 $rsel2 $rap $rtw $s2 $rs 6>$null | Out-Null
    $st2 = ($rp2 | ForEach-Object { "$($_.Key)=$($_.State)" }) -join ' '
    Check 'Э9: продолжение — выполнены только ждавшие шаги, тот же прогон' ($st2 -eq 'restore=skip tweak:g.wsl=done tweak:p.x=done app:dk=done app:n8=done app:a1=done config:n8=done' -and
        ($script:Calls9 -join ',') -eq 'dk,n8,cfg' -and $script:PB.Stamp -eq '2026-11-01_100000') @($st2, ($script:Calls9 -join ','))
    $h2 = if ($s2.Report -and (Test-Path $s2.Report)) { Get-Content $s2.Report -Raw -Encoding UTF8 } else { '' }
    Check 'Э9: конец — состояние и задача убраны, один отчёт на прогон, итоги обоих проходов, перезагрузок 1' (-not $s2.ResumePending -and $script:Task9 -eq 'off' -and -not (Read-PbResume) -and
        ($s1.Report -eq $s2.Report -or -not (Test-Path $s1.Report)) -and $h2 -notmatch 'Прогон продолжится' -and $h2 -match 'Перезагрузок во время прогона</dt><dd>1' -and $s2.Boots -eq 1 -and
        @($script:PB.Results | Where-Object { $_.'Что' -eq 'Прог 1' }).Count -eq 1) @($s2.Boots, $script:Task9)

    # предохранитель: шаг снова просит перезагрузку — без неё снова ждёт, после настоящей перезагрузки — ошибка
    $script:PB.Stamp = '2026-11-01_110000'; $script:PB.Results.Clear(); $script:N8Ok = $false; $script:Boot9 = (Get-Date).AddHours(-1)
    $gsel = @{ Apps = @('n8'); Tweaks = @(); Configs = @(); Files = @() }
    $gp = Get-PbRunPlan $gsel $rap $rtw $null; $gp[0].State = 'skip'
    Invoke-PbRun $gp $gsel $rap $rtw ([hashtable]::Synchronized(@{})) 6>$null | Out-Null
    $g1 = Read-PbResume
    $gp2 = Get-PbRunPlan $gsel $rap $rtw $null; Restore-PbResumeSteps $gp2 $g1
    Invoke-PbRun $gp2 $gsel $rap $rtw ([hashtable]::Synchronized(@{})) $g1 6>$null | Out-Null
    $noBoot = "$($gp2[1].State)/$($gp2[1].Reboots)"
    $g2 = Read-PbResume; $script:Boot9 = Get-Date
    $gp3 = Get-PbRunPlan $gsel $rap $rtw $null; Restore-PbResumeSteps $gp3 $g2
    Invoke-PbRun $gp3 $gsel $rap $rtw ([hashtable]::Synchronized(@{})) $g2 6>$null | Out-Null
    Check 'Э9: предохранитель — без перезагрузки снова ждёт, после неё повторная просьба — ошибка, прогон закончен' ($noBoot -eq 'reboot/1' -and $gp3[1].State -eq 'error' -and
        $gp3[1].Detail -match 'снова' -and -not (Read-PbResume) -and $script:Task9 -eq 'off') @($noBoot, $gp3[1].State, $gp3[1].Detail)

    # имя компьютера сменилось после перезагрузки: шага переименования в новом плане нет — он возвращается из состояния
    $nsel = @{ Apps = @('a1'); Tweaks = @(); Configs = @(); Files = @(); Name = 'PC-09' }
    $np = Get-PbRunPlan $nsel $rap $rtw $null
    foreach ($x in $np) { $x.State = 'done' }
    $nst = New-PbResumeState $np $nsel (Get-Date) 0
    $nsel2 = @{ Apps = @('a1'); Tweaks = @(); Configs = @(); Files = @(); Name = $env:COMPUTERNAME }
    $np2 = Get-PbRunPlan $nsel2 $rap $rtw $null
    $before = $np2.Count
    Restore-PbResumeSteps $np2 ($nst | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    Check 'Э9: шаг, которого нет в новом плане, возвращается на своё место' ($before -eq 2 -and $np2.Count -eq 3 -and $np2[2].Key -eq 'rename' -and $np2[2].State -eq 'done' -and
        $np2[2].Phase -eq 7) (($np2 | ForEach-Object { $_.Key }) -join ',')

    # временный автоматический вход — на тестовом ключе вместо Winlogon
    $w = $script:PbResume.Winlogon
    try {
        New-Item -Path $w -Force | Out-Null
        New-ItemProperty -Path $w -Name 'AutoAdminLogon' -Value '0' -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $w -Name 'DefaultUserName' -Value 'old' -PropertyType String -Force | Out-Null
        $script:Secret9.Clear()
        $sec = ConvertTo-SecureString 'x' -AsPlainText -Force
        Enable-PbAutoLogon $sec
        $idle = Get-ItemProperty $w
        Set-PbAutoLogonArmed $true; $on = Get-ItemProperty $w
        Set-PbAutoLogonArmed $false; $off = Get-ItemProperty $w
        Stop-PbResume; $back = Get-ItemProperty $w
        Check 'Э9: автовход — пароль сохранён, вход только на одну загрузку, после входа выключен, в конце всё как было' ($idle.AutoAdminLogon -eq '0' -and
            $on.AutoAdminLogon -eq '1' -and $on.AutoLogonCount -eq 1 -and $on.DefaultUserName -eq $env:USERNAME -and $off.AutoAdminLogon -eq '0' -and $null -eq $off.AutoLogonCount -and
            $back.AutoAdminLogon -eq '0' -and $back.DefaultUserName -eq 'old' -and $null -eq $back.DefaultDomainName -and -not (Test-PbAutoLogonEnabled) -and
            ($script:Secret9 -join ',') -eq 'set,clear') @($on, $back)
        function Set-PbLogonSecret ($Password) { 5 }
        $err = $null; try { Enable-PbAutoLogon $sec } catch { $err = $_.Exception.Message }
        Check 'Э9: пароль не сохранён — ошибка, автовход не остаётся включённым' ($err -match 'код 5' -and -not (Test-PbAutoLogonEnabled)) $err
    } finally { Remove-Item -Path (Split-Path $w) -Recurse -Force -ErrorAction SilentlyContinue }
    # настоящие LSA и планировщик — только в CI (одноразовая машина с правами администратора), в отдельном процессе
    if ($env:GITHUB_ACTIONS) {
        $lib = Join-Path $root 'lib'
        $probe9 = "`$ErrorActionPreference = 'Stop'; . '$lib\common.ps1'; . '$lib\run.ps1'; `$script:PB.Root = '$root'; Add-Type -Path '$lib\ui\model.cs'; " +
            "`$s = ConvertTo-SecureString 'x' -AsPlainText -Force; `$a = [PcBase.AutoLogon]::StorePassword(`$s); `$b = [PcBase.AutoLogon]::ClearPassword(); `$c = [PcBase.AutoLogon]::ClearPassword(); " +
            "Register-PbResumeTask; `$t = Test-PbResumeTask; Unregister-PbResumeTask; `$u = Test-PbResumeTask; `"`$a,`$b,`$c,`$t,`$u`""
        $ci9 = & $ps -NoProfile -Command $probe9 2>&1
        Check 'Э9 (CI): секрет LSA пишется и удаляется, задача планировщика регистрируется и удаляется' ([string]$ci9 -eq '0,0,0,True,False') $ci9
    }

    foreach ($f in 'Invoke-Tweak', 'Install-App', 'Initialize-Winget', 'Invoke-PbWingetTimed', 'Set-NoConfig', 'Save-PbFiles', 'Rename-Computer', 'Request-PbAnswer', 'Set-N8Config', 'Get-PbBootTime') { Remove-Item "function:$f" -ErrorAction SilentlyContinue }
    . (Join-Path (Join-Path $root 'lib') 'common.ps1'); . (Join-Path (Join-Path $root 'lib') 'files.ps1'); . (Join-Path (Join-Path $root 'lib') 'run.ps1')
    Set-PbResumeSandbox
    $script:PB.Root = $root; $script:PB.LogDir = Join-Path $tmp 'logs2'; $script:PB.DataRoot = Join-Path $tmp 'nodata'
    New-Item -ItemType Directory $script:PB.LogDir -Force | Out-Null
    '[{"Kind":"Reg"},{"Kind":"Reg"}]' | Set-Content (Join-Path $script:PB.LogDir 'changes_2026-10-01_101500.json')
    '[{"Kind":"Reg"}]' | Set-Content (Join-Path $script:PB.LogDir 'changes_2026-10-30_090000.json')
    $logs = @(Get-PbChangeLogs)
    Check 'журналы для отката: новые первыми, дата из имени, число записей' ($logs.Count -eq 2 -and $logs[0].Count -eq 1 -and $logs[1].Date -eq [datetime]'2026-10-01 10:15:00' -and $logs[1].Count -eq 2) ($logs | ConvertTo-Json)

    # ---------- Э7: другая сборка — тоже установлена ----------
    Write-Host 'другая сборка'
    $ent = @(@{ Name = 'Notepad++ (64-bit x64)'; Version = '8.6' })
    $s1 = Get-PbAppStatusCore @{ Name = 'Notepad++'; Source = 'winget'; WingetId = 'Notepad++.Notepad++' } $ent @{}
    $s2 = Get-PbAppStatusCore @{ Name = 'Windows Terminal'; Source = 'winget'; WingetId = 'Microsoft.WindowsTerminal'; Appx = 'Microsoft.WindowsTerminal' } @() @{} @{ 'Microsoft.WindowsTerminal' = '1.21.2911.0' }
    $s3 = Get-PbAppStatusCore @{ Name = 'Notepad++'; Source = 'winget'; WingetId = 'Notepad++.Notepad++' } $ent $null
    Check 'статус: MSI не через winget, из Microsoft Store, до ответа winget — просто установлено' ($s1.Kind -eq 'installed' -and $s1.Text -eq 'установлено не через winget · 8.6' -and
        $s2.Kind -eq 'installed' -and $s2.Text -eq 'установлено из Microsoft Store · 1.21.2911.0' -and $s3.Text -eq 'установлено · 8.6') @($s1.Text, $s2.Text, $s3.Text)

    # ---------- удаление с компьютера (lib\selfremove.ps1): только свои папки ----------
    Write-Host 'удаление с компьютера'
    . (Join-Path (Join-Path $root 'lib') 'selfremove.ps1')
    $own = Join-Path $tmp 'tabula-rasa-private'; New-Item -ItemType Directory $own -Force | Out-Null
    & git -C $own init -q 2>$null; & git -C $own remote add origin 'https://github.com/someone/tabula-rasa-private.git' 2>$null
    $alien = Join-Path $tmp 'alien'; New-Item -ItemType Directory (Join-Path $alien 'tabula-rasa-private') -Force | Out-Null
    $alienRepo = Join-Path $alien 'tabula-rasa-private'
    & git -C $alienRepo init -q 2>$null; & git -C $alienRepo remote add origin 'https://github.com/someone/other-repo.git' 2>$null
    Check 'удаление: только свои папки — не корень, не профиль, не пустой путь' (
        -not (Test-PbSafeRemovePath '') -and -not (Test-PbSafeRemovePath ([IO.Path]::GetPathRoot($tmp))) -and -not (Test-PbSafeRemovePath $tmp) -and
        -not (Test-PbSafeRemovePath 'tabula-rasa') -and (Test-PbSafeRemovePath (Join-Path $tmp 'tabula-rasa')) -and (Test-PbSafeRemovePath (Join-Path $tmp 'Tabula Rasa')) -and
        (Test-PbSafeRemovePath (Join-Path $tmp 'tabula-rasa-files')) -and -not (Test-PbSafeRemovePath (Join-Path $tmp 'tabula-rasa-backup')))
    Check 'удаление: «Мои данные» — только клон своего tabula-rasa-private' ((Test-PbOwnDataRoot $own) -and -not (Test-PbOwnDataRoot $alienRepo) -and -not (Test-PbOwnDataRoot (Join-Path $tmp 'nope')))
    $saveRoot = $script:PB.Root; $saveData = $script:PB.DataRoot
    $script:PB.Root = Join-Path $tmp 'tabula-rasa'; $script:PB.DataRoot = $own
    $t1 = New-PbSelfRemoveScript @('data', 'git', 'logs', 'files') 4321
    $t2 = New-PbSelfRemoveScript @() 4321
    $script:PB.DataRoot = $alienRepo
    $t3 = New-PbSelfRemoveScript @('data') 4321
    $script:PB.Root = $saveRoot; $script:PB.DataRoot = $saveData
    $pe = $null; [void][Management.Automation.Language.Parser]::ParseInput($t1, [ref]$null, [ref]$pe)
    Check 'удаление: скрипт разбирается; всё выбранное — в нём; ждёт процесс' (-not $pe.Count -and $t1.Contains($own) -and $t1.Contains('Get-Process -Id 4321') -and $t1.Contains('Git.Git')) $pe
    Check 'удаление: без отметок — только программа, без выхода из GitHub и удаления Git' ($t2 -match 'if \(\$False\) \{\s+if \(Get-Command gh' -and -not $t2.Contains($own) -and $t2.Contains('Get-Process -Id 4321'))
    Check 'удаление: чужой репозиторий в -DataRoot не удаляется' (-not $t3.Contains($alienRepo))

    # ---------- заставка ----------
    Write-Host 'заставка'
    . (Join-Path (Join-Path $root 'lib') 'splash.ps1')
    $sx = Get-PbSplashXaml
    $okXml = $true; try { [void][xml]$sx } catch { $okXml = $false }
    Check 'заставка: разметка — корректный XML, все цвета подставлены' ($okXml -and $sx -notmatch '"@\w+"' -and $sx -match 'x:Name="Step"' -and $sx -match 'PART_Indicator') $sx.Length
    Set-PbSplash 'шаг' 0.5 6>$null
    Close-PbSplash
    Check 'заставка: без запуска — вызовы ничего не делают' ($null -eq $script:PbSplash)

    # ---------- имена ассетов ----------
    Write-Host 'имена ассетов'
    Check 'транслит' ((ConvertTo-PbAssetName 'Отчёт 2024 (итог).pdf') -eq 'Otchet_2024_itog.pdf')
    Check 'заглавные слова' ((ConvertTo-PbAssetName 'ЩУКА.exe') -eq 'SHCHUKA.exe')
    Check 'пустое имя' ((ConvertTo-PbAssetName '日本語.txt') -eq 'file.txt')
} catch {
    if ($env:GITHUB_ACTIONS) { Write-Host "::error title=tests/run.ps1::$($_.Exception.Message) @ $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" }
    throw
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Fails) { Write-Host "Ошибок: $($script:Fails) из $($script:Count)" -ForegroundColor Red; exit 1 }
Write-Host "Все проверки пройдены: $($script:Count)" -ForegroundColor Green
exit 0   # иначе остаётся $LASTEXITCODE последней внешней команды из проверок
