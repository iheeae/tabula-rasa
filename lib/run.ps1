# Tabula Rasa: план и прогон. Один список шагов (Get-PbRunPlan) — и экран плана, и экран прогона в окне,
# и вывод в консоль (setup.ps1 -Console).
#
# Шаг: @{ Key; Phase (1–7); PhaseName; Kind; Name; Ref; State = wait|run|done|same|skip|error|reboot; Detail; Note; Irreversible;
#        Already (статус твика до прогона: applied|partial|no|unknown); Actions (действия «было → стало», Add-PbAction);
#        Reboots (сколько раз шаг сам просил перезагрузку перед собой) }.
# same — «уже было»: всё нужное уже стояло, ничего не менялось. reboot — ждёт перезагрузки (Э9, lib\resume.ps1):
# конец прохода с такими шагами — пауза, состояние в resume.json, продолжение после входа (setup.ps1 -Resume).
# Invoke-PbRun выполняет шаги по порядку. Из окна — в фоновом runspace с общим $Sync: State/Detail шагов,
# $Sync.SkipCurrent (снять текущий), $Sync.StopAfter (остановить после текущего), вопросы — $Sync.Ask / $Sync.Answer
# вместо Read-Host. Без $Sync — как раньше, в консоли. В конце — отчёт (lib\report.ps1), путь — $Sync.Report / $script:PB.Report.

. (Join-Path $PSScriptRoot 'report.ps1')
. (Join-Path $PSScriptRoot 'resume.ps1')

# обычный хеш, не [ordered]: у [ordered] целое в [] — номер по порядку, а не ключ ($PbPhases[1] давал вторую фазу)
$script:PbPhases = @{
    1 = 'Точка восстановления'; 2 = 'Настройки Windows'; 3 = 'Программы'; 4 = 'Настройки программ'
    5 = 'Файлы'; 6 = 'Среда'; 7 = 'Имя компьютера'
}

function New-PbStep ([int]$Phase, [string]$Kind, [string]$Key, [string]$Name, $Ref) {
    return [hashtable]::Synchronized(@{ Key = $Key; Phase = $Phase; PhaseName = $script:PbPhases[$Phase]; Kind = $Kind; Name = $Name; Ref = $Ref
        State = 'wait'; Detail = ''; Note = ''; Irreversible = $false; Already = $null; Actions = @(); Reboots = 0 })
}

# $Sel — выбор окна (Apps, Configs, Tweaks, Files, FileTitles, Name, Upgrades, Reinstall, Remove); $Status — статусы окна (необязательно):
# @{ Apps = @{ id = @{ Kind } }; Tweaks = @{ id = 'applied' } } — для пометок «будет пропущено». Твики, статуса которых
# нет (окно ещё не проверило, -Console), проверяются здесь же (Get-PbTweakStatus — только чтение)
function Get-PbRunPlan ($Sel, $Apps, $Tweaks, $Status) {
    $plan = New-Object System.Collections.ArrayList
    $pre = @($Tweaks | Where-Object { $_.Phase -ne 'post' -and $Sel.Tweaks -contains $_.Id })
    $post = @($Tweaks | Where-Object { $_.Phase -eq 'post' -and $Sel.Tweaks -contains $_.Id })
    # не $apps: имена переменных без учёта регистра — затёрло бы параметр $Apps (удаление и «с моими» без установки пропадали)
    $inst = @($Apps | Where-Object { $Sel.Apps -contains $_.Id })
    $remove = @($Apps | Where-Object { @($Sel.Remove) -contains $_.Id })
    $cfg = @($Apps | Where-Object { $_.Config -and $_.Config.Import -and $Sel.Configs -contains $_.Id })
    $any = $pre.Count + $post.Count + $inst.Count + $remove.Count + $cfg.Count + @($Sel.Files).Count + [int][bool]$Sel.Name
    if (-not $any) { return , $plan }

    [void]$plan.Add((New-PbStep 1 'restore' 'restore' 'Создать точку восстановления' $null))
    foreach ($t in $pre) { [void]$plan.Add((New-PbTweakStep 2 $t $Status)) }
    # удаление — первым в фазе программ: необратимо (вернуть — только установкой заново)
    foreach ($a in $remove) {
        $s = New-PbStep 3 'remove' "remove:$($a.Id)" "Удалить: $($a.Name)" $a.Id
        $s.Irreversible = $true; $s.Note = 'необратимо: вернуть можно только установкой заново'
        [void]$plan.Add($s)
    }
    foreach ($a in $inst) {
        $s = New-PbStep 3 'app' "app:$($a.Id)" $a.Name $a.Id
        $st = if ($Status -and $Status.Apps) { $Status.Apps[$a.Id] } else { $null }
        if (@($Sel.Reinstall) -contains $a.Id) { $s.Note = 'переустановка'; $s.Name = "Переустановить: $($a.Name)" }
        elseif ($st -and $st.Kind -eq 'update' -and @($Sel.Upgrades) -contains $a.Id) { $s.Note = "обновление: $($st.Text -replace '^обновление: ', '')" }
        elseif ($st -and $st.Kind -in 'installed', 'update') { $s.Note = 'уже установлено: будет пропущено' }
        elseif ($a.Source -eq 'web') { $s.Note = 'с официального сайта, с проверкой подписи' }
        if ($a.Interactive) { $s.Note = (@($s.Note, 'откроется мастер установки') | Where-Object { $_ }) -join '; ' }
        [void]$plan.Add($s)
    }
    foreach ($a in $cfg) {
        $s = New-PbStep 4 'config' "config:$($a.Id)" "$($a.Name): с моими настройками" $a.Id
        if (-not (Find-PbConfig $a.Config.File)) { $s.Note = 'сохранённых настроек нет: будет пропущено' }
        [void]$plan.Add($s)
    }
    if (@($Sel.Files).Count) {
        $titles = if ($Sel.FileTitles) { @($Sel.FileTitles) } else { @($Sel.Files) }
        $s = New-PbStep 5 'files' 'files' "Загрузить файлы: $($titles.Count)" $null
        $s.Note = ($titles -join ', ')
        [void]$plan.Add($s)
    }
    foreach ($t in $post) { [void]$plan.Add((New-PbTweakStep 6 $t $Status)) }
    # зависимости (Э8): нужное не отмечено и не установлено — пометка у шага (снять его в окне можно, с предупреждением)
    $all = @{}; foreach ($x in @(@($Apps) + @($Tweaks))) { if ($x.Id) { $all[$x.Id] = $x } }
    $chosen = @{}; foreach ($id in @(@($Sel.Apps) + @($Sel.Tweaks))) { if ($id) { $chosen[$id] = $true } }
    foreach ($s in @($plan | Where-Object { $_.Kind -in 'app', 'tweak' })) {
        $miss = @(@($all[$s.Ref].Requires) | Where-Object { $_ -and -not $chosen[$_] } | Where-Object {
            $r = $_
            -not ($Status -and (($Status.Apps -and $Status.Apps[$r] -and $Status.Apps[$r].Kind -in 'installed', 'update') -or ($Status.Tweaks -and $Status.Tweaks[$r] -eq 'applied')))
        } | ForEach-Object { if ($all[$_]) { $all[$_].Name } else { $_ } })
        if ($miss.Count) { $s.Note = (@($s.Note, "требует: $($miss -join ', ') (не отмечено)") | Where-Object { $_ }) -join '; ' }
        # Э9: нужное — пункт, после которого может понадобиться перезагрузка (RebootGate), и он в этом же плане
        $gate = @(Get-PbRebootGates $s $all $plan)
        if ($gate.Count) { $s.Note = (@($s.Note, "после перезагрузки, если её потребует «$($gate -join '», «')»") | Where-Object { $_ }) -join '; ' }
    }
    if ($Sel.Name -and $Sel.Name -ne $env:COMPUTERNAME) {
        $s = New-PbStep 7 'rename' 'rename' "Имя компьютера: $env:COMPUTERNAME → $($Sel.Name)" $Sel.Name
        $s.Note = 'вступит в силу после перезагрузки'
        [void]$plan.Add($s)
    }
    return , $plan
}

# RebootGate-пункты из Requires шага, которые в плане и ещё не применены / не установлены: имена
function Get-PbRebootGates ($Step, $All, $Plan) {
    @(@($All[$Step.Ref].Requires) | Where-Object { $_ -and $All[$_] -and $All[$_].RebootGate } | Where-Object {
        $r = $_; @($Plan | Where-Object { $_.Ref -eq $r -and $_.Kind -in 'app', 'tweak' -and $_.Note -notmatch 'будет пропущено' }).Count
    } | ForEach-Object { $All[$_].Name })
}

# Э9: ожидаемые перезагрузки посреди прогона — для предупреждения перед ним. Пусто — предупреждать не о чем
function Get-PbRebootForecast ($Plan, $Apps, $Tweaks) {
    $all = @{}; foreach ($x in @(@($Apps) + @($Tweaks))) { if ($x.Id) { $all[$x.Id] = $x } }
    @($Plan | Where-Object { $_.Kind -in 'app', 'tweak' } | ForEach-Object {
        $s = $_; Get-PbRebootGates $s $all $Plan | ForEach-Object { "«$_» перед «$($all[$s.Ref].Name)»" }
    } | Select-Object -Unique)
}

# шаг твика с проверкой до прогона: уже применено — будет пропущено, частично — изменится только отличающееся
function New-PbTweakStep ([int]$Phase, $T, $Status) {
    $s = New-PbStep $Phase 'tweak' "tweak:$($T.Id)" $T.Name $T.Id
    $st = $null
    if ($Status -and $Status.Tweaks) { $st = $Status.Tweaks[$T.Id] }
    if (-not $st -and (Get-Command Get-PbTweakStatus -ErrorAction SilentlyContinue)) { try { $st = Get-PbTweakStatus $T } catch { $st = 'unknown' } }
    $s.Already = $st
    # уже применённое необратимое пропускается и ничего не удаляет — не помечать красным и не считать необратимым
    $s.Irreversible = [bool]$T.Irreversible -and $st -ne 'applied'
    if ($st -eq 'applied') { $s.Note = 'уже применено: будет пропущено' }
    elseif ($st -eq 'partial') { $s.Note = 'применено частично: изменятся только отличающиеся значения' }
    if ($s.Irreversible -and $st -ne 'applied') { $s.Note = (@($s.Note, 'необратимо: отменяется только точкой восстановления') | Where-Object { $_ }) -join '; ' }
    return $s
}

# сводка плана для подсказки и консоли: «настройки Windows уже применены: 3 из 7»
function Get-PbPlanSummary ($Plan) {
    $tw = @($Plan | Where-Object { $_.Kind -eq 'tweak' })
    if (-not $tw.Count) { return '' }
    $done = @($tw | Where-Object { $_.Already -eq 'applied' }).Count
    $part = @($tw | Where-Object { $_.Already -eq 'partial' }).Count
    $t = "настройки Windows уже применены: $done из $($tw.Count)"
    if ($part) { $t += ", частично: $part" }
    return $t
}

# план текстом (setup.ps1 -Console и журнал)
function Write-PbPlan ($Plan) {
    $sum = Get-PbPlanSummary $Plan
    if ($sum) { Write-Host "  План: $sum" -ForegroundColor Gray }
    $ph = 0
    foreach ($s in $Plan) {
        if ($s.Phase -ne $ph) { $ph = $s.Phase; Write-Step $s.PhaseName }
        Write-Host "    $($s.Name)$(if ($s.Note) { "   [$($s.Note)]" })" -ForegroundColor $(if ($s.Irreversible) { 'Yellow' } else { 'Gray' })
    }
}

# вопрос «да/нет»: в окне — через $Sync (окно показывает диалог), в консоли — Read-Host
function Request-PbAnswer ([string]$Text, [string[]]$Items) {
    $sync = $script:PB.RunSync
    if (-not $sync) {
        Write-Host "    $Text" -ForegroundColor Yellow
        $Items | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
        return ((Read-Host '    [y/N]') -match '^[yYнН]')
    }
    $sync.Answer = $null
    $sync.Ask = @{ Text = $Text; Items = @($Items) }
    while ($null -eq $sync.Answer) { Start-Sleep -Milliseconds 200 }
    $sync.Ask = $null
    return [bool]$sync.Answer
}

# состояние шага по строкам итога, добавленным за время шага
function Get-PbStepState ($Results) {
    $r = @($Results)
    $bad = @($r | Where-Object { $_.'Статус' -in 'ОШИБКА', 'ТАЙМАУТ' })
    if ($bad.Count) { return @{ State = 'error'; Detail = (@($bad | ForEach-Object { "$($_.'Статус'): $($_.'Детали')" }) -join '; ') } }
    $skip = @($r | Where-Object { $_.'Статус' -eq 'пропущено' })
    if ($skip.Count -and $skip.Count -eq $r.Count) { return @{ State = 'skip'; Detail = (@($skip | ForEach-Object { $_.'Детали' }) -join '; ') } }
    $text = (@($r | ForEach-Object { @($_.'Статус', $_.'Детали' | Where-Object { $_ }) -join ', ' } | Select-Object -Unique) -join '; ')
    # всё нужное уже было: ничего не менялось
    if (-not @($r | Where-Object { $_.'Статус' -notin 'уже было', 'уже установлено' }).Count) { return @{ State = 'same'; Detail = $text } }
    return @{ State = 'done'; Detail = $text }
}

# выполнить план. $Apps / $Tweaks — загруженные в этом же runspace (скриптблоки твиков привязаны к своему runspace).
# $Resume — состояние прошлого прохода (Read-PbResume): шаги уже перенесены в $Plan (Restore-PbResumeSteps),
# здесь восстанавливаются итоги, журнал изменений и время начала — отчёт и журнал изменений общие на весь прогон
function Invoke-PbRun ($Plan, $Sel, $Apps, $Tweaks, $Sync, $Resume) {
    $script:PB.RunSync = $Sync
    $script:PB.Upgrades = @($Sel.Upgrades)
    $script:PB.Reinstall = @($Sel.Reinstall)
    $byId = @{}; foreach ($a in $Apps) { $byId[$a.Id] = $a }
    $tw = @{}; foreach ($t in $Tweaks) { $tw[$t.Id] = $t }
    $wingetReady = $null
    $phase = 0
    $started = Get-Date
    $runErr = $null
    $boots = 0; $rebooted = $false
    if ($Resume) {
        Restore-PbResumeRun $Resume
        $started = ConvertTo-PbDate $Resume.Started
        $boots = [int]$Resume.Boots
        # перезагрузка была, если Windows загрузилась после паузы. Продолжили без неё — повторная просьба шага не ошибка
        $rebooted = (Get-PbBootTime) -gt (ConvertTo-PbDate $Resume.Paused)
        if ($rebooted) { $boots++ }
        Write-Step "Продолжение прогона$(if ($rebooted) { " после перезагрузки ($boots)" })"
    }
    $script:PB.ResumePending = $false
    # Э9: что нужно шагу (Requires; для «с моими настройками» — сама программа) и RebootGate-пункты, потребовавшие
    # перезагрузку в этом проходе: шаг, которому нужно ждущее перезагрузки, тоже ждёт
    $all = @{}; foreach ($x in @(@($Apps) + @($Tweaks))) { if ($x.Id) { $all[$x.Id] = $x } }
    $stepOf = @{}; foreach ($x in $Plan) { if ($x.Kind -in 'app', 'tweak') { $stepOf[$x.Ref] = $x } }
    $gates = @{}
    try {
        foreach ($s in $Plan) {
            if ($s.State -ne 'wait') { continue }   # уже снят (нет точки восстановления, остановка) или выполнен до перезагрузки
            if ($Sync -and $Sync.StopAfter) { $s.State = 'skip'; $s.Detail = 'прогон остановлен'; continue }
            $need = if ($s.Kind -eq 'config') { @($s.Ref) } elseif ($s.Kind -in 'app', 'tweak' -and $all[$s.Ref]) { @($all[$s.Ref].Requires | Where-Object { $_ }) } else { @() }
            $wait = @($need | Where-Object { $gates[$_] -or ($stepOf[$_] -and $stepOf[$_].State -eq 'reboot') })
            if ($wait.Count) {
                $names = @($wait | ForEach-Object { if ($all[$_]) { $all[$_].Name } else { $_ } })
                $s.State = 'reboot'; $s.Detail = "выполнится после перезагрузки: нужна для «$($names -join '», «')»"
                continue
            }
            if ($s.Phase -ne $phase) { $phase = $s.Phase; Write-Step $s.PhaseName }
            if ($Sync) { $Sync.Current = $s.Key; $Sync.SkipCurrent = $false }
            $s.State = 'run'
            $mark = $script:PB.Results.Count
            $actMark = $script:PB.Actions.Count
            # перезагрузка, которую потребовал именно этот шаг
            $rebootBefore = $script:PB.NeedReboot; $script:PB.NeedReboot = $false; $script:PB.RebootFirst = $false
            try {
                switch ($s.Kind) {
                    'restore' {
                        try {
                            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
                            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
                            Checkpoint-Computer -Description "tabula-rasa $($script:PB.Stamp)" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                            Write-Ok 'создана'; Add-Result 'Точка восстановления' 'создана'
                        } catch {
                            Write-Warn2 "не создана: $($_.Exception.Message)"
                            Add-Result 'Точка восстановления' 'пропущено' $_.Exception.Message
                            # без точки восстановления необратимое уже ничем не отменить — спросить, а не молча выполнить
                            $irr = @($Plan | Where-Object { $_.Irreversible -and $_.State -eq 'wait' })
                            if ($irr.Count -and -not (Request-PbAnswer 'Точка восстановления не создана. Без неё эти изменения отменить будет невозможно. Выполнить их?' @($irr | ForEach-Object { $_.Name }))) {
                                foreach ($x in $irr) { $x.State = 'skip'; $x.Detail = 'нет точки восстановления'; Add-Result $x.Name 'пропущено' 'нет точки восстановления' }
                            }
                        }
                    }
                    'tweak' { Invoke-Tweak $tw[$s.Ref] }
                    'app' {
                        $a = $byId[$s.Ref]
                        if ($a.Source -eq 'winget') {
                            if ($null -eq $wingetReady) {
                                $wingetReady = Initialize-Winget
                                if ($wingetReady) { [void](Invoke-PbWingetTimed @('source', 'update', '--name', 'winget') 5 'source_update') }
                            }
                            if (-not $wingetReady) { Add-Result $a.Name 'ОШИБКА' 'нет winget'; break }
                        }
                        Install-App $a
                        Update-SessionPath
                    }
                    'remove' {
                        if ($null -eq $wingetReady) { $wingetReady = Initialize-Winget }
                        if (-not $wingetReady) { Add-Result $s.Name 'ОШИБКА' 'нет winget'; break }
                        Uninstall-WingetApp $byId[$s.Ref]
                    }
                    'config' {
                        $a = $byId[$s.Ref]
                        Write-Host "  - $($a.Name): с моими настройками" -ForegroundColor White
                        & $a.Config.Import
                    }
                    'files' { Save-PbFiles -Names $Sel.Files }
                    'rename' {
                        Rename-Computer -NewName $s.Ref -Force -ErrorAction Stop
                        $script:PB.NeedReboot = $true; Add-Result $s.Name 'применено'
                    }
                }
            } catch { Write-Fail $_.Exception.Message; Add-Result $s.Name 'ОШИБКА' $_.Exception.Message }
            $stepReboot = [bool]$script:PB.NeedReboot
            $script:PB.NeedReboot = $rebootBefore -or $stepReboot
            $new = @($script:PB.Results | Select-Object -Skip $mark)
            $s.Actions = @($script:PB.Actions | Select-Object -Skip $actMark)
            if ($Sync -and $Sync.SkipCurrent) { $s.State = 'skip'; $s.Detail = 'пропущено вручную' }
            elseif ($script:PB.RebootFirst) {
                # шаг сам просит перезагрузку перед собой. Второй раз после настоящей перезагрузки — ошибка, а не новая перезагрузка
                if ($s.Reboots -and $rebooted) {
                    $s.State = 'error'; $s.Detail = 'после перезагрузки снова требуется перезагрузка'
                    Add-Result $s.Name 'ОШИБКА' $s.Detail
                } else { $s.Reboots = 1; $s.State = 'reboot'; $s.Detail = 'выполнится после перезагрузки: перед установкой нужна перезагрузка' }
            }
            elseif ($new.Count) { $st = Get-PbStepState $new; $s.State = $st.State; $s.Detail = $st.Detail }
            else { $s.State = 'done' }
            if ($stepReboot -and $s.State -eq 'done' -and $s.Kind -in 'app', 'tweak' -and $all[$s.Ref] -and $all[$s.Ref].RebootGate) { $gates[$s.Ref] = $true }
        }
        $pending = @($Plan | Where-Object { $_.State -eq 'reboot' })
        if ($pending.Count -and $Sync -and $Sync.StopAfter) { foreach ($x in $pending) { $x.State = 'skip'; $x.Detail = 'прогон остановлен' }; $pending = @() }
        $script:PB.ResumePending = $pending.Count -gt 0
        if ($script:PB.NeedExplorerRestart) { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }
    } catch { $runErr = $_.Exception.Message; throw
    } finally {
        $changesFile = $null
        if ($script:PB.Changes.Count) { $changesFile = Save-Changes }
        if ($script:PB.Manual.Count) { $script:PB.Manual | Set-Content -Path (Join-Path $script:PB.LogDir "manual_$($script:PB.Stamp).txt") -Encoding UTF8 }
        # Э9: есть ждущие перезагрузки — задача планировщика на вход и состояние; иначе всё про продолжение убирается
        if ($script:PB.ResumePending) {
            try { Register-PbResumeTask }
            catch {
                $why = "продолжение после перезагрузки не подготовлено: $($_.Exception.Message)"
                Write-Fail $why
                foreach ($x in @($Plan | Where-Object { $_.State -eq 'reboot' })) { $x.State = 'error'; $x.Detail = $why; Add-Result $x.Name 'ОШИБКА' $why }
                $script:PB.ResumePending = $false
            }
        }
        if (-not $script:PB.ResumePending) { try { Stop-PbResume } catch { Write-Warn2 "состояние продолжения не очищено: $($_.Exception.Message)" } }
        # отчёт один на прогон: промежуточный (до перезагрузки) заменяется
        if ($Resume -and $Resume.Report) {
            foreach ($f in @([string]$Resume.Report, (Join-Path $script:PB.LogDir (Split-Path ([string]$Resume.Report) -Leaf)))) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        }
        $script:PB.Report = $null
        $info = Get-PbReportInfo $started $changesFile $runErr
        $info.Boots = $boots; $info.Pending = [bool]$script:PB.ResumePending
        try { $script:PB.Report = Write-PbReport $Plan $info }
        catch { Write-Warn2 "отчёт не создан: $($_.Exception.Message)" }
        if ($script:PB.ResumePending) {
            try { Save-PbResume (New-PbResumeState $Plan $Sel $started $boots) }
            catch { Write-Fail "состояние прогона не сохранено: $($_.Exception.Message)"; Unregister-PbResumeTask; $script:PB.ResumePending = $false }
        }
        if ($Sync) {
            $Sync.NeedReboot = $script:PB.NeedReboot; $Sync.Manual = @($script:PB.Manual); $Sync.Report = $script:PB.Report
            $Sync.ResumePending = [bool]$script:PB.ResumePending; $Sync.Boots = $boots; $Sync.Done = $true
        }
        $script:PB.RunSync = $null
    }
}

# сведения для отчёта о прогоне (lib\report.ps1)
function Get-PbReportInfo ([datetime]$Started, [string]$ChangesFile, [string]$Err) {
    $win = "Windows $($script:PB.Os)"
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        if ($cv.DisplayVersion) { $win += " $($cv.DisplayVersion)" }
        $win += " (сборка $($cv.CurrentBuild)$(if ($null -ne $cv.UBR) { ".$($cv.UBR)" }))"
    } catch { $win += " (сборка $([Environment]::OSVersion.Version.Build))" }
    $engine = 'dev'
    if (Get-Command Get-PbEngineVersion -ErrorAction SilentlyContinue) { $engine = Get-PbEngineVersion }
    return @{ Computer = $env:COMPUTERNAME; Windows = $win; Started = $Started; Finished = (Get-Date); Engine = $engine
        NeedReboot = [bool]$script:PB.NeedReboot; Manual = @($script:PB.Manual); ChangesFile = $ChangesFile
        ChangesCount = @($script:PB.Changes).Count; LogDir = $script:PB.LogDir; Error = $Err; Boots = 0; Pending = $false }
}

# ---------- откат (undo.ps1 и окно «Откат изменений») ----------

# журналы изменений: новые первыми, и в старой папке логов (pc-base). @{ Path; Date; Count }
function Get-PbChangeLogs {
    @(@($script:PB.LogDir, (Join-Path $script:PbLegacy.Program 'logs')) | Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -Filter 'changes_*.json' -ErrorAction SilentlyContinue } |
        Sort-Object Name -Descending | ForEach-Object {
            $n = 0; try { $n = @(Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }).Count } catch { }
            $d = $_.LastWriteTime
            if ($_.BaseName -match '(\d{4}-\d\d-\d\d)_(\d\d)(\d\d)(\d\d)$') { try { $d = [datetime]::ParseExact("$($Matches[1]) $($Matches[2]):$($Matches[3]):$($Matches[4])", 'yyyy-MM-dd HH:mm:ss', $null) } catch { } }
            @{ Path = $_.FullName; Date = $d; Count = $n }
        })
}

# откат одного журнала в обратном порядке; строки результата — @{ Ok; Text }
function Invoke-PbUndo ([string]$File) {
    # | ForEach-Object: в 5.1 ConvertFrom-Json отдаёт JSON-массив одним объектом, @() дал бы массив из одного массива
    $changes = @(Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
    [array]::Reverse($changes)
    foreach ($c in $changes) {
        try {
            $text = switch ($c.Kind) {
                'Reg' {
                    if ($c.OldExists) {
                        $kind = if ($c.OldKind) { $c.OldKind } else { $c.Type }
                        $val = $c.Old
                        if ($kind -eq 'MultiString') { $val = [string[]]@($val) }
                        if ($kind -eq 'Binary') { $val = [byte[]]@($val) }
                        New-ItemProperty -Path $c.Path -Name $c.Name -Value $val -PropertyType $kind -Force -ErrorAction Stop | Out-Null
                    } elseif (Test-Path $c.Path) {
                        Remove-ItemProperty -Path $c.Path -Name $c.Name -ErrorAction SilentlyContinue
                    }
                    if ($c.KeyCreated -and (Test-Path $c.Path)) {
                        $k = Get-Item $c.Path
                        if ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item $c.Path -Force }
                    }
                    "$($c.Path)\$($c.Name)"
                }
                'RegKey' { if ($c.KeyCreated -and (Test-Path $c.Path)) { Remove-Item $c.Path -Recurse -Force; "ключ $($c.Path) удалён" } }
                'Service' {
                    $st = @{ 'Auto' = 'Automatic'; 'Manual' = 'Manual'; 'Disabled' = 'Disabled' }[[string]$c.Old]
                    if ($st) { Set-Service -Name $c.Name -StartupType $st -ErrorAction Stop; "служба $($c.Name) → $st" }
                }
                'Task' { if ($c.WasEnabled) { Enable-ScheduledTask -TaskPath $c.TaskPath -TaskName $c.TaskName -ErrorAction Stop | Out-Null; "задача $($c.TaskName) включена" } }
                'Hibernate' { if ($c.WasEnabled) { & powercfg.exe /hibernate on; 'гибернация и быстрый запуск снова включены' } }
                'PowerScheme' { if ($c.Old) { & powercfg.exe /setactive $c.Old; "схема питания $($c.Old) снова активна" } }
                'MachinePath' {
                    $cur = [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_ -and $_ -ne $c.Dir }
                    [Environment]::SetEnvironmentVariable('Path', ($cur -join ';'), 'Machine')
                    "PATH: удалён $($c.Dir)"
                }
            }
            if ($text) { @{ Ok = $true; Text = $text } }
        } catch { @{ Ok = $false; Text = "$($c.Kind) $($c.Path)$($c.Name): $($_.Exception.Message)" } }
    }
}

$script:PbUndoLimits = 'Не отменяются через undo.ps1: удалённые встроенные приложения и OneDrive, установленные программы, обновления winget upgrade --all, применённые настройки программ в файлах. Для них используется точка восстановления «tabula-rasa <дата>» (Панель управления → Восстановление) или удаление программ вручную.'
