# Tabula Rasa: развёртывание и обслуживание компьютеров. Профилей нет — одно окно со всем каталогом.
#
# Запуск (права администратора запрашиваются автоматически):
#   powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\setup.ps1
# Обычно запускается из bootstrap.ps1; вручную — для повторного прогона.
#
# Две папки: движок — здесь (C:\tabula-rasa, клон публичного репозитория), Мои данные — C:\tabula-rasa-private
# (клон своего приватного репозитория: сохранения, настройки программ). Подключаются из окна; без них работает всё,
# кроме «с моими настройками», а сохранения пишутся локально.
#
# Ключи:
#   -Selection <имя|путь>   открыть окно с сохранением: путь к .json, имя из Моих данных или локальных сохранений
#   -NoPull                 не подтягивать свежую версию из git
#   -DryRun                 с -Console: только показать план, не спрашивая о применении
#   -DataRoot <папка>       где лежат свои данные, если не в C:\tabula-rasa-private
#   -Console                план и прогон — в консоли, как раньше (для отладки); по умолчанию — в окне
#   -Spawned                служебный: так setup.ps1 запускает сам себя скрытым процессом
#   -Resume                 служебный: продолжить прогон после перезагрузки (так запускает задача планировщика, lib\resume.ps1)
#
# Обычный запуск (без -Console) — программа без консоли: setup.ps1 запускает себя заново скрытым процессом
# (с правами администратора, в STA) и отпускает окно, из которого его запустили, оставив в нём одну строку.
# Шаги старта видны на заставке (lib\splash.ps1), вопросы и ошибки — в окнах, отчёт о прогоне — lib\report.ps1.

[CmdletBinding()]
param(
    [string]$Selection,
    [switch]$NoPull,
    [switch]$DryRun,
    [string]$DataRoot,
    [switch]$Console,
    [switch]$Spawned,
    [switch]$Resume
)

$ErrorActionPreference = 'Continue'   # Stop ломает нативные команды в PS 5.1; где надо — -ErrorAction Stop явно
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- права админа и STA (окно на WPF работает только в STA-потоке) ----------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = [Threading.Thread]::CurrentThread.ApartmentState -eq 'STA'
$script:PbSpawned = [bool]$Spawned -and -not $Console
$PbPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ключи для повторного запуска (в кавычках: Start-Process склеивает аргументы в одну строку)
function Get-PbSetupArgs ([switch]$WithPull) {
    $a = @()
    if ($Selection) { $a += @('-Selection', "`"$Selection`"") }
    if ($NoPull -and -not $WithPull) { $a += '-NoPull' }
    if ($DryRun) { $a += '-DryRun' }
    if ($DataRoot) { $a += @('-DataRoot', "`"$DataRoot`"") }
    if ($Resume) { $a += '-Resume' }
    return $a
}

# setup.ps1 скрытым процессом: без окна консоли, с правами администратора (-Elevate — через запрос UAC)
function Start-PbSetupHidden ([string]$File, [string[]]$Rest, [switch]$Elevate) {
    $p = @{ FilePath = $PbPowerShell; WindowStyle = 'Hidden'; PassThru = $true; ErrorAction = 'Stop'
            ArgumentList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$File`"") + @($Rest) + '-Spawned' }
    if ($Elevate) { $p.Verb = 'RunAs' } else { $p.WorkingDirectory = $env:SystemRoot }
    return (Start-Process @p)
}

# обычный запуск: окно, из которого запустили (команда irm | iex, ярлык, setup.ps1), принадлежит пользователю —
# его не закрываем и не прячем, только оставляем в нём одну строку
if (-not $Console -and -not $Spawned) {
    try {
        [void](Start-PbSetupHidden $PSCommandPath (Get-PbSetupArgs) -Elevate:(-not $isAdmin))
        Write-Host '  Tabula Rasa запущена, это окно можно закрыть.' -ForegroundColor Green
    } catch {
        Write-Host '  Tabula Rasa не запущена: для работы нужны права администратора. Запустите её снова и подтвердите запрос.' -ForegroundColor Yellow
    }
    return
}
if (-not $isAdmin -or -not $isSta) {
    $argList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Selection) { $argList += @('-Selection', "`"$Selection`"") }
    if ($NoPull) { $argList += '-NoPull' }
    if ($DryRun) { $argList += '-DryRun' }
    if ($Console) { $argList += '-Console' }
    if ($DataRoot) { $argList += @('-DataRoot', "`"$DataRoot`"") }
    if ($Resume) { $argList += '-Resume' }
    if ($isAdmin) { Start-Process powershell.exe -ArgumentList $argList }
    else { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList }
    return
}

$Host.UI.RawUI.WindowTitle = 'Tabula Rasa'
. (Join-Path $PSScriptRoot 'lib\splash.ps1')
if ($script:PbSpawned) { Start-PbSplash }

# ---------- самая свежая версия: до загрузки lib\*.ps1 ----------
# Клон движка всегда приводится к origin/master — другая ветка, отставание или локальные правки не повод запускать
# старую версию. Ничего не теряется: правки уходят в git stash, свои коммиты master — в ветку backup/master-<дата>.
# Если версия изменилась, этот же setup.ps1 перезапускается, чтобы окно работало уже на новом коде.
# Повторный запуск помечается переменной TR_ENGINE_SYNCED, чтобы не проверять второй раз.
$preNotices = @()
if ($env:TR_ENGINE_NOTICE) { $preNotices += @($env:TR_ENGINE_NOTICE -split "`n" | Where-Object { $_ }) }
$env:TR_ENGINE_NOTICE = $null
$engineSynced = $env:TR_ENGINE_SYNCED -eq '1'
$env:TR_ENGINE_SYNCED = $null
if (-not $NoPull -and -not $engineSynced -and (Get-Command git -ErrorAction SilentlyContinue) -and
    (Test-Path (Join-Path $PSScriptRoot '.git'))) {
    function Invoke-EngineGit { & git -C $PSScriptRoot @args 2>$null }
    $engineOrigin = Invoke-EngineGit remote get-url origin
    # только свой клон (в том числе старый адрес до переименования); чужой разбирает блок «старый клон» ниже
    if ($engineOrigin -match 'github\.com[/:]iheeae/(tabula-rasa|pc-base)(\.git)?/?$') {
        Set-PbSplash 'Проверка обновлений…' 0.1
        $before = Invoke-EngineGit rev-parse HEAD
        Invoke-EngineGit fetch --quiet origin master | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $preNotices += 'Нет связи с GitHub: обновления не проверены, запущена текущая версия Tabula Rasa.'
        } else {
            $target = Invoke-EngineGit rev-parse origin/master
            $branch = Invoke-EngineGit symbolic-ref --short -q HEAD
            if ($before -ne $target -or $branch -ne 'master') {
                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                if (Invoke-EngineGit status --porcelain) {
                    Invoke-EngineGit stash push --include-untracked -m "tabula-rasa: локальные изменения перед обновлением $stamp" | Out-Null
                    $preNotices += "Локальные изменения в $PSScriptRoot перед обновлением сохранены в git stash ($stamp)."
                }
                Invoke-EngineGit merge-base --is-ancestor master origin/master
                if ($LASTEXITCODE -eq 1) {   # у локальной master есть коммиты, которых нет на GitHub
                    Invoke-EngineGit branch -f "backup/master-$stamp" master | Out-Null
                    $preNotices += "Локальные коммиты ветки master сохранены в ветке backup/master-$stamp."
                }
                Invoke-EngineGit checkout -q -B master origin/master | Out-Null
                Invoke-EngineGit branch -q --set-upstream-to=origin/master master | Out-Null
                $after = Invoke-EngineGit rev-parse HEAD
                if ($after -ne $target) {
                    $preNotices += "Не удалось обновить Tabula Rasa в $($PSScriptRoot): запущена текущая версия."
                } elseif ($after -ne $before) {
                    Set-PbSplash "Tabula Rasa обновлена ($($before.Substring(0, 7)) → $($after.Substring(0, 7))), запуск новой версии…" 0.2
                    $env:TR_ENGINE_SYNCED = '1'
                    $env:TR_ENGINE_NOTICE = ($preNotices -join "`n")
                    if ($script:PbSpawned) {
                        # новая версия — тоже скрытым процессом; своя заставка закрывается, когда появилось окно новой
                        $child = Start-PbSetupHidden $PSCommandPath (Get-PbSetupArgs -WithPull)
                        $until = (Get-Date).AddSeconds(30)
                        while (-not $child.HasExited -and (Get-Date) -lt $until) {
                            $child.Refresh()
                            if ($child.MainWindowHandle -ne [IntPtr]::Zero) { break }
                            Start-Sleep -Milliseconds 200
                        }
                        Close-PbSplash
                        exit 0
                    }
                    $relaunch = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
                    if ($Selection) { $relaunch += @('-Selection', $Selection) }
                    if ($DryRun) { $relaunch += '-DryRun' }
                    if ($Console) { $relaunch += '-Console' }
                    if ($DataRoot) { $relaunch += @('-DataRoot', $DataRoot) }
                    & powershell.exe @relaunch
                    exit $LASTEXITCODE
                }
            }
        }
    }
}

try {
    . (Join-Path $PSScriptRoot 'lib\common.ps1')
    . (Join-Path $PSScriptRoot 'lib\gui.ps1')
    . (Join-Path $PSScriptRoot 'lib\configs.ps1')
} catch { Show-PbFatal $_ $null; exit 1 }
$script:PB.Root = $PSScriptRoot
if ($DataRoot) { $script:PB.DataRoot = $DataRoot }
$EngineRepo = 'iheeae/tabula-rasa'
$startNotices = @($preNotices)
$windowMode = $false

# загрузчик в отдельном окне: переносит или заново клонирует папку движка. Сами выходим сразу, чтобы не держать её.
# Это переустановка, а не обычный запуск: ход загрузчика виден в его окне, затем окно программы открывается как обычно
function Start-PbBootstrap {
    Close-PbSplash
    $boot = "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://raw.githubusercontent.com/$EngineRepo/master/bootstrap.ps1 | iex"
    Start-Process powershell.exe -WorkingDirectory $env:SystemRoot -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $boot)
    Set-Location $env:SystemRoot
}

# ---------- переезд pc-base → Tabula Rasa ----------
# Запуск из старой C:\pc-base: свою папку не переместить, поэтому переносит загрузчик. Новая уже есть — запускается она.
# С -NoPull (так запускает загрузчик) не переезжаем: загрузчик уже пробовал, папка занята — работаем из старой.
$newRoot = 'C:\tabula-rasa'
if ($PSScriptRoot -eq $script:PbLegacy.Root -and -not $NoPull) {
    if (Test-Path (Join-Path $newRoot 'setup.ps1')) {
        Write-Host "  Tabula Rasa установлен в $newRoot, запуск оттуда." -ForegroundColor Yellow
        $fwd = @()
        if ($Selection) { $fwd += @('-Selection', "`"$Selection`"") }
        if ($DataRoot) { $fwd += @('-DataRoot', "`"$DataRoot`"") }
        if ($script:PbSpawned) { Close-PbSplash; [void](Start-PbSetupHidden "$newRoot\setup.ps1" $fwd) }
        else { Start-Process powershell.exe -WorkingDirectory $env:SystemRoot -ArgumentList (@('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$newRoot\setup.ps1`"", '-Console') + $fwd) }
    } else {
        Write-Host "  pc-base теперь называется Tabula Rasa. Загрузчик перенесёт $PSScriptRoot в $newRoot." -ForegroundColor Yellow
        Start-PbBootstrap
    }
    return
}
if ($PSScriptRoot -eq $script:PbLegacy.Root) {
    $startNotices += "Tabula Rasa запущен из старой папки $($PSScriptRoot): её не удалось переименовать. Закройте окна, которые её используют, и запустите Tabula Rasa снова."
}
Set-PbSplash 'Перенос старых папок…' 0.3
if (Get-Command git -ErrorAction SilentlyContinue) { Update-PbOrigin $PSScriptRoot }
if ($PSScriptRoot -ne $script:PbLegacy.Root -and (Test-Path $script:PbLegacy.Root)) {
    $startNotices += "Найдена старая папка $($script:PbLegacy.Root). Если всё работает, её можно удалить."
}
# Мои данные, локальные сохранения, журналы и логи
if (-not $DataRoot) {
    switch (Move-PbLegacyDir $script:PbLegacy.DataRoot $script:PB.DataRoot) {
        'both' { $startNotices += "Найдена старая папка $($script:PbLegacy.DataRoot). Мои данные уже в $($script:PB.DataRoot), старую папку можно удалить." }
        'busy' { $script:PB.DataRoot = $script:PbLegacy.DataRoot
                 $startNotices += "Папку $($script:PbLegacy.DataRoot) не удалось переименовать: она используется. Мои данные открыты из неё; перезапустите Tabula Rasa, когда папка освободится." }
    }
}
if (Get-Command git -ErrorAction SilentlyContinue) { Update-PbOrigin $script:PB.DataRoot }
[void](Move-PbLegacyDir $script:PbLegacy.Local (Join-Path $env:LOCALAPPDATA 'tabula-rasa') 10)
switch (Move-PbLegacyDir $script:PbLegacy.Program (Join-Path $env:ProgramData 'tabula-rasa') 10) {
    'busy' { $script:PB.LogDir = Join-Path $script:PbLegacy.Program 'logs' }
}

# ---------- старый клон ----------
# Публичный репозиторий начат с чистой истории. Если эта папка — клон чего-то другого (не тот origin или нет общего
# предка с origin/master), git pull не поможет: загрузчик отодвинет папку в .old_<дата> (ничего не удаляя)
# и склонирует движок заново.
if (-not $NoPull -and (Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $PSScriptRoot '.git'))) {
    $origin = & git -C $PSScriptRoot remote get-url origin 2>$null
    $sameOrigin = $origin -match ('github\.com[/:]' + [regex]::Escape($EngineRepo) + '(\.git)?/?$')
    $related = $false
    if ($sameOrigin) {
        & git -C $PSScriptRoot fetch --quiet origin 2>$null
        if ($LASTEXITCODE -eq 0) {
            & git -C $PSScriptRoot merge-base HEAD origin/master 2>$null | Out-Null
            $related = $LASTEXITCODE -eq 0
        } else { $related = $true }   # нет сети — судить не по чему, работаем с тем, что есть
    }
    if (-not $sameOrigin -or -not $related) {
        Write-Host ''
        Write-Host "  $PSScriptRoot содержит устаревшую копию ($origin)." -ForegroundColor Yellow
        Write-Host '  Загрузчик переместит её в .old_<дата> и установит Tabula Rasa заново.' -ForegroundColor Yellow
        Start-PbBootstrap
        return
    }
}

New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null
$transcript = Join-Path $script:PB.LogDir "setup_$($script:PB.Stamp).log"
Start-Transcript -Path $transcript -Force | Out-Null

try {
    # ---------- незавершённый прогон (Э9, lib\resume.ps1) ----------
    # -Resume (задача планировщика после входа): вход уже выполнен — автоматический вход больше не нужен до следующей
    # перезагрузки прогона. Обычный запуск при незавершённом прогоне — спросить: продолжить сейчас или отказаться.
    # Ни прогона, ни задачи нет, а пароль автоматического входа остался (прогон прервался) — убрать его.
    $resumeState = Read-PbResume
    if ($resumeState -and -not (Test-PbResumeOwner $resumeState)) { $resumeState = $null }
    if ($Resume) {
        Set-PbAutoLogonArmed $false
        if (-not $resumeState) {
            Write-Warn2 'Продолжать нечего: состояние прогона не найдено.'
            if (-not (Read-PbResume)) { Stop-PbResume }
            $windowMode = $true
            return
        }
    } elseif ($resumeState) {
        $left = @($resumeState.Steps | Where-Object { $_.State -in 'reboot', 'wait' }).Count
        $when = (ConvertTo-PbDate $resumeState.Started).ToString('dd.MM.yyyy HH:mm')
        $text = "Прогон от $when не завершён: он ждёт перезагрузки, шагов осталось: $left."
        $go = $false
        if ($Console) {
            Write-Warn2 $text
            $go = (Read-Host '    Продолжить его сейчас? Иначе он будет отменён [Y/n]') -notmatch '^[nNтТ]'
        } else {
            Set-PbSplashVisible $false
            $go = Show-UiMessage -Title 'Незавершённый прогон' -Primary 'Продолжить' -Secondary 'Отменить прогон' -Lines @($text,
                @{ Text = 'Продолжить можно и без перезагрузки: шаги, которым она нужна, снова попросят её. При отмене оставшиеся шаги не выполняются, а пароль автоматического входа, если он был сохранён, удаляется.'; Tone = 'muted' })
            Set-PbSplashVisible $true
        }
        if ($go) { $Resume = $true } else { Stop-PbResume; $resumeState = $null }
    } elseif (-not (Test-Path -LiteralPath (Get-PbResumePath))) {   # незавершённый прогон другого пользователя не трогаем
        Clear-PbAutoLogon
        if (Test-PbResumeTask) { Unregister-PbResumeTask }
    }

    # свежая версия движка подтягивается в самом начале, до загрузки lib\*.ps1 (см. «самая свежая версия»)
    # Мои данные: подтянуть с GitHub и отправить то, что не ушло в прошлый раз
    if (-not $NoPull -and (Test-PbDataConnected)) {
        Set-PbSplash 'Синхронизация Моих данных…' 0.45
        Write-Step "Мои данные ($($script:PB.DataRoot)): синхронизация с GitHub"
        switch (Push-PbData) {
            'offline' { Write-Warn2 "нет связи с GitHub; неотправленные изменения ($((Get-PbDataState).Pending)) будут отправлены при следующем запуске" }
            'public'  { $w = Get-PbPublicWarning (Get-PbDataRepo); Write-Warn2 $w; $startNotices += $w }
        }
    }

    # ---------- каталог ----------
    Set-PbSplash 'Загрузка каталога…' 0.65
    $Apps = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'catalog\apps.psd1')).Apps
    # собственный каталог из «Моих данных»: только winget, ошибочные записи пропускаются
    $uc = Read-PbUserCatalog @($Apps | ForEach-Object { $_.Id })
    $Apps = @($Apps) + @($uc.Apps)
    if ($uc.Errors.Count) { $startNotices += "Собственный каталог: пропущено записей с ошибками: $($uc.Errors.Count) ($($uc.Errors -join '; '))." }
    . (Join-Path $PSScriptRoot 'catalog\tweaks.ps1')
    Get-EnvInfo
    # всё, что не подходит к этой версии Windows, отсекается сразу — в меню и окне его не видно
    $Tweaks = @($Tweaks | Where-Object { $_.Os -contains $script:PB.Os })
    $Apps = @($Apps | Where-Object { -not $_.Os -or $_.Os -contains $script:PB.Os })
    $osTag = "Windows $($script:PB.Os)"

    Clear-Host
    Write-Host ''
    Write-Host '  Tabula Rasa' -ForegroundColor Cyan
    Write-Host ("  {0} | Windows {1} (сборка {2}) | {3}{4}" -f $env:COMPUTERNAME, $script:PB.Os, [Environment]::OSVersion.Version.Build,
        $(if ($script:PB.IsDomain) { 'в домене' } else { 'не в домене' }), $(if ($script:PB.IsLaptop) { ' | ноутбук' } else { '' })) -ForegroundColor Gray
    $ds = Get-PbDataState
    if ($ds.Connected) { Write-Host "  Мои данные: $($script:PB.DataRoot)$(if ($ds.User) { " ($($ds.User))" })$(if ($ds.Pending) { ", не отправлено: $($ds.Pending)" })" -ForegroundColor Gray }
    else { Write-Host '  Мои данные не подключены (подключение — в окне, слева внизу)' -ForegroundColor Gray }
    if ($DryRun) { Write-Host '  РЕЖИМ ПРОВЕРКИ: ничего не меняется' -ForegroundColor Yellow }
    if (-not $resumeState -and -not (Test-SameUserAsDesktop)) {
        $who = "Tabula Rasa запущена от имени $env:USERNAME, а рабочий стол принадлежит другому пользователю."
        $what = 'Настройки текущего пользователя (Проводник, панель задач, Terminal) будут применены к профилю администратора, а не к профилю того, кто работает за компьютером.'
        Write-Warn2 $who; Write-Warn2 $what
        if ($Console) {
            if ((Read-Host '    Продолжить? [y/N]') -notmatch '^[yYнН]') { return }
        } else {
            Set-PbSplashVisible $false
            if (-not (Show-UiMessage -Title 'Другой пользователь' -Lines @($who, @{ Text = $what; Tone = 'muted' }) -Primary 'Продолжить' -Secondary 'Выйти' -SafeDefault)) { return }
            Set-PbSplashVisible $true
        }
    }

    # ---------- окно выбора ----------
    $initial = $null
    if ($Selection) {
        $p = Find-PbSave $Selection
        if ($p) { $initial = Read-SaveFile $p } else { Write-Warn2 "Сохранение не найдено: $Selection" }
    }
    # список файлов окно получает само, в фоне: из релиза files «Моих данных». Заставка закрывается, когда окно показано
    Set-PbSplash 'Подготовка окна…' 0.85
    if ($resumeState -and $Console) {
        # -Console: продолжение — сразу прогон в консоли, без окна
        $sel = Get-PbResumeSel $resumeState
        $plan = Get-PbRunPlan $sel $Apps $Tweaks $null
        Restore-PbResumeSteps $plan $resumeState
        Write-PbPlan $plan
        Invoke-PbRun $plan $sel $Apps $Tweaks $null $resumeState
        return
    }
    $sel = Show-SelectionDialog -Apps $Apps -Tweaks $Tweaks -Initial $initial -Notices $startNotices -IsDomain $script:PB.IsDomain -RunInWindow (-not $Console) -Resume $resumeState
    if ($script:PB.WindowShownSec) { Write-Host "  Окно открылось через $($script:PB.WindowShownSec) с после запуска." -ForegroundColor DarkGray }
    # план, прогон и итог прошли в окне (lib\gui.ps1 + lib\run.ps1): журнал прогона — logs\run_<дата>.log
    if ($sel -and $sel.RanInWindow) { $windowMode = $true; return }
    if (-not $sel) { Write-Host '  Отменено.'; return }

    # -Console: тот же план и прогон (lib\run.ps1), вывод — в консоль; применение — после подтверждения
    $plan = Get-PbRunPlan $sel $Apps $Tweaks $null
    Write-PbPlan $plan
    Write-Host ''
    if ($DryRun) { Write-Host '  Показан только план (-DryRun), изменения не вносились.' -ForegroundColor Yellow; return }
    if ((Read-Host '  Применить план? [y/N]') -notmatch '^[yYнН]') { Write-Host '  Изменения не вносились.' -ForegroundColor Yellow; return }
    Invoke-PbRun $plan $sel $Apps $Tweaks $null
}
catch {
    # падение целиком: в окне — «Что-то пошло не так» с путём к журналу; в консоли — текст ошибки, как раньше
    if ($Console) { throw }
    $windowMode = $true
    try { Stop-Transcript | Out-Null } catch { }
    Show-PbFatal $_ $transcript
    exit 1
}
finally {
  Close-PbSplash
  if ($windowMode) { try { Stop-Transcript | Out-Null } catch { } }
  else {
    $changesFile = $null
    if ($script:PB.Changes.Count) { $changesFile = Save-Changes }

    if ($script:PB.Results.Count) {
        Write-Step 'Итог'
        $script:PB.Results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
        $fails = @($script:PB.Results | Where-Object { $_.'Статус' -in 'ОШИБКА', 'ТАЙМАУТ' })
        if ($fails.Count) { Write-Host "  Ошибок: $($fails.Count). Подробности — в журнале выполнения" -ForegroundColor Red }
        else { Write-Host '  Ошибок нет' -ForegroundColor Green }
    }
    if ($script:PB.Manual.Count) {
        Write-Step 'Выполнить вручную'
        $i = 1; foreach ($m in $script:PB.Manual) { Write-Host ("  {0,2}. {1}" -f $i, $m); $i++ }
        $script:PB.Manual | Set-Content -Path (Join-Path $script:PB.LogDir "manual_$($script:PB.Stamp).txt") -Encoding UTF8
    }
    if ($changesFile) { Write-Host ''; Write-Host "  Журнал изменений: $changesFile  (откат: undo.ps1)" -ForegroundColor Gray }
    if ($script:PB.Report) { Write-Host "  Отчёт: $($script:PB.Report)" -ForegroundColor Gray }
    Write-Host "  Журнал выполнения: $transcript" -ForegroundColor Gray
    Stop-Transcript | Out-Null

    if ($script:PB.ResumePending) {
        # Э9: часть шагов ждёт перезагрузки; после входа прогон продолжится сам (задача планировщика)
        Write-Host '  Часть шагов выполнится после перезагрузки: после входа в Windows прогон продолжится автоматически.' -ForegroundColor Yellow
        if ((Read-Host '  Перезагрузить сейчас? [Y/n]') -notmatch '^[nNтТ]') { Restart-PbForResume }
    } elseif ($script:PB.NeedReboot) {
        if ((Read-Host '  Нужна перезагрузка. Перезагрузить сейчас? [Y/n]') -notmatch '^[nNтТ]') { Restart-Computer -Force }
    } else {
        Read-Host '  Готово. Enter — закрыть' | Out-Null
    }
  }
}
