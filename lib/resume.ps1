# Tabula Rasa: продолжение прогона после перезагрузки (Э9).
#
# Шаг, которому нужна перезагрузка (winget 0x8A15010A; пункт, зависящий от RebootGate-пункта, потребовавшего
# перезагрузку), получает состояние «reboot» и ждёт. В конце прохода, если такие есть, Invoke-PbRun сохраняет
# состояние прогона (resume.json) и регистрирует задачу планировщика на вход этого же пользователя. После входа
# setup.ps1 -Resume открывает окно сразу на экране прогона и продолжает с ожидающих шагов; журнал изменений и отчёт
# остаются общими на весь прогон (тот же Stamp).
#
# Временный автоматический вход — по выбору пользователя: пароль проверяется (LogonUser) и хранится в LSA
# (секрет DefaultPassword, как у Autologon от Sysinternals), в реестр открытым текстом не пишется. AutoAdminLogon
# включается только перед перезагрузкой прогона и выключается сразу после входа. Параметры Winlogon — временное
# состояние, а не настройка: они не идут через Set-Reg и журнал изменений, прежние значения хранятся в autologon.json
# и возвращаются Clear-PbAutoLogon (конец прогона, отмена, любой запуск без незавершённого прогона).

$script:PbResume = @{
    Dir      = Join-Path $env:ProgramData 'tabula-rasa'
    Task     = 'Tabula Rasa — продолжение прогона'
    Winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Names    = @('AutoAdminLogon', 'DefaultUserName', 'DefaultDomainName', 'AutoLogonCount')
}
function Get-PbResumePath { Join-Path $script:PbResume.Dir 'resume.json' }
function Get-PbAutoLogonPath { Join-Path $script:PbResume.Dir 'autologon.json' }

# файл только для администраторов, SYSTEM и того, чей это прогон: в нём выбор и ход прогона (не секреты, но и не для всех)
function Protect-PbResumeFile ([string]$Path) {
    try {
        $acl = New-Object Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sid in 'S-1-5-32-544', 'S-1-5-18', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
            $id = (New-Object Security.Principal.SecurityIdentifier $sid)
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule $id, 'FullControl', 'Allow'))
        }
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    } catch { }
}

function Write-PbJsonFile ([string]$Path, $Object) {
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Object -Depth 8), (New-Object Text.UTF8Encoding $false))
    Protect-PbResumeFile $Path
}

# дата из resume.json: в 5.1 ConvertFrom-Json оставляет строку, в 7 — уже DateTime
function ConvertTo-PbDate ($Value) {
    if ($Value -is [datetime]) { return $Value }
    try { return [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch { return [datetime]::MinValue }
}

# время последней загрузки Windows: была ли перезагрузка с момента паузы
function Get-PbBootTime {
    try { return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime } catch { return [datetime]::MinValue }
}

# ---------- состояние прогона ----------

# выбор окна → JSON и обратно: только простые поля (массивы строк, имя)
function ConvertTo-PbSelHash ($Sel) {
    $h = @{}
    foreach ($k in 'Apps', 'Tweaks', 'Configs', 'Files', 'FileTitles', 'Upgrades', 'Reinstall', 'Remove') { $h[$k] = @(@($Sel.$k) | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
    $h.Name = if ($Sel.Name) { [string]$Sel.Name } else { $null }
    return $h
}

# @{ ...; Steps; Results; Manual } — всё, что нужно, чтобы продолжить с того же места
function New-PbResumeState ($Plan, $Sel, [datetime]$Started, [int]$Boots) {
    return [ordered]@{
        Version  = 1
        Stamp    = $script:PB.Stamp
        Started  = $Started.ToString('o')
        Paused   = (Get-Date).ToString('o')
        Boots    = $Boots
        User     = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Root     = $script:PB.Root
        DataRoot = $script:PB.DataRoot
        LogDir   = $script:PB.LogDir
        Sel      = (ConvertTo-PbSelHash $Sel)
        NeedReboot = [bool]$script:PB.NeedReboot
        Steps    = @($Plan | ForEach-Object { [ordered]@{ Key = $_.Key; Phase = $_.Phase; Kind = $_.Kind; Name = $_.Name; Ref = [string]$_.Ref; Note = $_.Note
            Irreversible = [bool]$_.Irreversible; State = $_.State; Detail = $_.Detail; Reboots = [int]$_.Reboots; Actions = @($_.Actions) } })
        Results  = @($script:PB.Results | ForEach-Object { [ordered]@{ What = $_.'Что'; Status = $_.'Статус'; Details = $_.'Детали' } })
        Manual   = @($script:PB.Manual)
        Report   = $script:PB.Report
    }
}

function Save-PbResume ($State) { Write-PbJsonFile (Get-PbResumePath) $State }

# состояние или $null (нет файла, повреждён, другая версия, другой пользователь)
function Read-PbResume {
    $p = Get-PbResumePath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { $s = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    if (-not $s -or $s.Version -ne 1 -or -not $s.Stamp) { return $null }
    return $s
}

function Test-PbResumeOwner ($State) { [string]$State.User -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }

function Remove-PbResume { Remove-Item -LiteralPath (Get-PbResumePath) -Force -ErrorAction SilentlyContinue }

# выбор из resume.json → такой же хеш, как из окна
function Get-PbResumeSel ($State) { ConvertTo-PbSelHash $State.Sel }

# сохранённый ход → в свежий план (те же Key): готовое остаётся готовым, ожидающее перезагрузки — снова «ожидает».
# Шага уже нет в новом плане (имя компьютера сменилось после перезагрузки) — он возвращается из сохранённого как был.
# $Plan — ArrayList из Get-PbRunPlan
function Restore-PbResumeSteps ($Plan, $State) {
    $have = @{}; foreach ($p in $Plan) { $have[$p.Key] = $p }
    $pos = 0
    foreach ($s in @($State.Steps | Where-Object { $_ })) {
        $p = $have[[string]$s.Key]
        if (-not $p) {
            $p = New-PbStep ([int]$s.Phase) ([string]$s.Kind) ([string]$s.Key) ([string]$s.Name) ([string]$s.Ref)
            $p.Note = [string]$s.Note; $p.Irreversible = [bool]$s.Irreversible
            $Plan.Insert([Math]::Min($pos, $Plan.Count), $p)
        }
        $pos = $Plan.IndexOf($p) + 1
        $p.State = if ($s.State -in 'reboot', 'run') { 'wait' } else { [string]$s.State }
        $p.Detail = if ($s.State -eq 'reboot') { '' } else { [string]$s.Detail }
        $p.Reboots = [int]$s.Reboots
        $p.Actions = @($s.Actions | Where-Object { $_ } | ForEach-Object { [ordered]@{ Kind = $_.Kind; Target = $_.Target; Old = $_.Old; New = $_.New; Changed = [bool]$_.Changed } })
    }
}

# итоги, «выполнить вручную» и журнал изменений прошлых проходов → в $script:PB, чтобы файлы прогона дописывались целиком
function Restore-PbResumeRun ($State) {
    $script:PB.Stamp = [string]$State.Stamp
    $script:PB.NeedReboot = [bool]$State.NeedReboot
    $script:PB.Results.Clear(); foreach ($r in @($State.Results | Where-Object { $_ })) { Add-Result $r.What $r.Status $r.Details }
    $script:PB.Manual.Clear(); foreach ($m in @($State.Manual | Where-Object { $_ })) { Add-Manual $m }
    $script:PB.Changes.Clear()
    $f = Join-Path $script:PB.LogDir "changes_$($script:PB.Stamp).json"
    if (Test-Path -LiteralPath $f) {
        try { foreach ($c in @(Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })) { [void]$script:PB.Changes.Add($c) } } catch { }
    }
}

# ---------- задача планировщика: при входе этого пользователя ----------

function Register-PbResumeTask {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $setup = Join-Path $script:PB.Root 'setup.ps1'
    $arg = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$setup`" -Resume -NoPull -Spawned"
    if ($script:PB.DataRoot) { $arg += " -DataRoot `"$($script:PB.DataRoot)`"" }
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $ps -Argument $arg -WorkingDirectory $env:SystemRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
    Register-ScheduledTask -TaskName $script:PbResume.Task -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal -Settings $set `
        -Description 'Продолжает прогон Tabula Rasa после перезагрузки. Удаляется по окончании прогона.' -Force -ErrorAction Stop | Out-Null
}

function Unregister-PbResumeTask {
    if (Get-ScheduledTask -TaskName $script:PbResume.Task -TaskPath '\' -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $script:PbResume.Task -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Test-PbResumeTask { [bool](Get-ScheduledTask -TaskName $script:PbResume.Task -TaskPath '\' -ErrorAction SilentlyContinue) }

# всё про незавершённый прогон: задача, состояние, автоматический вход
function Stop-PbResume {
    Unregister-PbResumeTask
    Remove-PbResume
    Clear-PbAutoLogon
}

# ---------- временный автоматический вход ----------

# LSA и LogonUser — в model.cs (PcBase.AutoLogon); в окне сборка уже загружена, в -Console — компилируется здесь
function Import-PbLogonType {
    if ('PcBase.AutoLogon' -as [type]) { return }
    if (Get-Command Import-PbModel -ErrorAction SilentlyContinue) { Import-PbModel } else { Add-Type -Path (Join-Path $script:PB.Root 'lib\ui\model.cs') }
}

# @{ Ok; Reason }: можно ли предложить автоматический вход этому пользователю
function Get-PbAutoLogonSupport {
    $pl = $null
    try { $pl = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -ErrorAction Stop).DevicePasswordLessBuildVersion } catch { }
    if ($pl -eq 2) { return @{ Ok = $false; Reason = 'На компьютере включён вход только через Windows Hello, без пароля.' } }
    # автоматический вход уже настроен владельцем компьютера: спрашивать нечего, и чужие параметры не трогаем
    try { if ((Get-ItemProperty $script:PbResume.Winlogon -ErrorAction Stop).AutoAdminLogon -eq '1') { return @{ Ok = $false; Already = $true; Reason = '' } } } catch { }
    if ((Get-Command Test-SameUserAsDesktop -ErrorAction SilentlyContinue) -and -not (Test-SameUserAsDesktop)) {
        return @{ Ok = $false; Reason = 'Tabula Rasa запущена от имени другого пользователя, чем тот, кто работает за компьютером.' }
    }
    return @{ Ok = $true; Reason = '' }
}

# пароль текущего пользователя: 0 — верный, иначе код ошибки Windows
function Test-PbLogonPassword ([Security.SecureString]$Password) {
    Import-PbLogonType
    return [PcBase.AutoLogon]::Validate($env:USERNAME, $env:USERDOMAIN, $Password)
}

# секрет LSA DefaultPassword: записать / удалить. 0 — успех, иначе код ошибки Windows (tests\run.ps1 их подменяет)
function Set-PbLogonSecret ([Security.SecureString]$Password) { Import-PbLogonType; return [PcBase.AutoLogon]::StorePassword($Password) }
function Clear-PbLogonSecret { Import-PbLogonType; return [PcBase.AutoLogon]::ClearPassword() }

# сохранить пароль (LSA) и прежние параметры Winlogon; сам вход включает Set-PbAutoLogonArmed перед перезагрузкой
function Enable-PbAutoLogon ([Security.SecureString]$Password) {
    $f = Get-PbAutoLogonPath
    $fresh = -not (Test-Path -LiteralPath $f)
    if ($fresh) {
        $prev = @{}
        $k = Get-Item -LiteralPath $script:PbResume.Winlogon
        foreach ($n in $script:PbResume.Names) {
            $prev[$n] = if ($k.GetValueNames() -contains $n) { @{ Value = $k.GetValue($n); Kind = $k.GetValueKind($n).ToString() } } else { $null }
        }
        Write-PbJsonFile $f @{ Prev = $prev; User = $env:USERNAME; Domain = $env:USERDOMAIN }
    }
    $rc = Set-PbLogonSecret $Password
    if ($rc -ne 0) {
        # без пароля включённый автовход остановился бы на ошибке входа: такой прогон продолжается после ручного входа
        if ($fresh) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        throw "пароль не сохранён (код $rc)"
    }
}

function Test-PbAutoLogonEnabled { Test-Path -LiteralPath (Get-PbAutoLogonPath) }

# включить вход на одну следующую загрузку (AutoLogonCount = 1: Windows сама выключит его после входа) или выключить
function Set-PbAutoLogonArmed ([bool]$On) {
    $f = Get-PbAutoLogonPath
    if (-not (Test-Path -LiteralPath $f)) { return }
    $cfg = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
    $w = $script:PbResume.Winlogon
    if ($On) {
        New-ItemProperty -Path $w -Name 'DefaultUserName' -Value ([string]$cfg.User) -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $w -Name 'DefaultDomainName' -Value ([string]$cfg.Domain) -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $w -Name 'AutoLogonCount' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $w -Name 'AutoAdminLogon' -Value '1' -PropertyType String -Force | Out-Null
    } else {
        New-ItemProperty -Path $w -Name 'AutoAdminLogon' -Value '0' -PropertyType String -Force | Out-Null
        Remove-ItemProperty -Path $w -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
    }
}

# удалить пароль из LSA и вернуть Winlogon как было до прогона. Без autologon.json ничего не делает
function Clear-PbAutoLogon {
    $f = Get-PbAutoLogonPath
    if (-not (Test-Path -LiteralPath $f)) { return }
    try { $rc = Clear-PbLogonSecret; if ($rc -ne 0) { Write-Warn2 "пароль автоматического входа не удалён (код $rc)" } }
    catch { Write-Warn2 "пароль автоматического входа не удалён: $($_.Exception.Message)" }
    try {
        $cfg = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $w = $script:PbResume.Winlogon
        foreach ($n in $script:PbResume.Names) {
            $p = $cfg.Prev.$n
            if ($p) { New-ItemProperty -Path $w -Name $n -Value $p.Value -PropertyType $p.Kind -Force | Out-Null }
            else { Remove-ItemProperty -Path $w -Name $n -ErrorAction SilentlyContinue }
        }
        # пароль открытым текстом мог остаться от чужой настройки автовхода: его не трогаем, свой в реестр не писали
    } catch { Write-Warn2 "параметры входа не восстановлены: $($_.Exception.Message)" }
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
}

# перезагрузка для продолжения: включить автоматический вход (если выбран) и перезагрузить
function Restart-PbForResume {
    Set-PbAutoLogonArmed $true
    Restart-Computer -Force
}
