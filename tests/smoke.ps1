# Tabula Rasa: «дымовая» проверка окна на настоящей Windows (CI): окно открывается с полным каталогом, ждёт фоновую
# проверку статусов (реестр, winget), проходит по разделам, показывает план и закрывается само.
#   powershell -ExecutionPolicy Bypass -STA -File tests\smoke.ps1
# Ошибки окна (lib\gui.ps1, Write-PbUiError) пишутся в logs\ui-error_*.txt — их наличие и есть провал проверки.
# Мои данные не подключаются: DataRoot — пустая временная папка.

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot
$env:TR_SMOKE = '1'
if (-not $env:TR_SMOKE_SHOTS) { $env:TR_SMOKE_SHOTS = Join-Path ([IO.Path]::GetTempPath()) 'tabula-rasa-shots' }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tabula-rasa-smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
. (Join-Path $root 'lib\splash.ps1'); . (Join-Path $root 'lib\common.ps1'); . (Join-Path $root 'lib\gui.ps1'); . (Join-Path $root 'lib\configs.ps1')
$script:PB.Root = $root; $script:PB.DataRoot = Join-Path $tmp 'data'; $script:PB.LogDir = Join-Path $tmp 'logs'
New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null
$Apps = (Import-PowerShellDataFile (Join-Path $root 'catalog\apps.psd1')).Apps
. (Join-Path $root 'catalog\tweaks.ps1')
Get-EnvInfo
$Tweaks = @($Tweaks | Where-Object { $_.Os -contains $script:PB.Os })
$Apps = @($Apps | Where-Object { -not $_.Os -or $_.Os -contains $script:PB.Os })

$fail = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
# сторож: раз в 5 с — что на экране; через 300 с закрыть все окна (модальные тоже), чтобы проверка не висела
Add-Type -AssemblyName PresentationFramework, WindowsBase
$script:WatchLog = New-Object System.Collections.ArrayList
$watch = New-Object Windows.Threading.DispatcherTimer
$watch.Interval = [TimeSpan]::FromSeconds(5)
$watch.add_Tick({
    $wins = @(); try { $wins = @([Windows.Application]::Current.Windows | ForEach-Object { "$($_.GetType().Name) «$($_.Title)» visible=$($_.IsVisible)" }) } catch { }
    $line = ("[{0,3} с] окон: {1}: {2}; статусы: {3}; smoke: {4}" -f [int]$sw.Elapsed.TotalSeconds, $wins.Count, ($wins -join '; '), $script:SmokeState, $env:TR_SMOKE_STEP)
    Write-Host "  $line"
    [void]$script:WatchLog.Add($line)
    if ($sw.Elapsed.TotalSeconds -gt 300) {
        $script:SmokeTimeout = $true
        $watch.Stop()
        foreach ($w in @([Windows.Application]::Current.Windows)) { try { $w.Close() } catch { } }
    }
})
$watch.Start()
# второй сторож — в своём потоке: если завис сам поток окна (первый сторож тогда молчит), через 360 с — провал
# с последним шагом проверки вместо немого тайм-аута шага CI
$hang = [PowerShell]::Create()
[void]$hang.AddScript({
    param($Sec)
    Start-Sleep -Seconds $Sec
    $m = "окно не отвечает $Sec с (завис поток окна), последний шаг проверки: «$([Environment]::GetEnvironmentVariable('TR_SMOKE_STEP'))»"
    [Console]::Out.WriteLine("FAIL $m")
    if ([Environment]::GetEnvironmentVariable('GITHUB_ACTIONS')) { [Console]::Out.WriteLine("::error title=tests/smoke.ps1::$m") }
    [Console]::Out.Flush(); [Environment]::Exit(1)
}).AddArgument(360)
[void]$hang.BeginInvoke()
try {
    $r = Show-SelectionDialog -Apps $Apps -Tweaks $Tweaks -Notices @('Проверка окна') -IsDomain $false -RunInWindow $true
    Write-Host "Окно закрылось через $([int]$sw.Elapsed.TotalSeconds) с"
} catch {
    $fail += "окно упало: $($_.Exception.Message) $($_.ScriptStackTrace)"
}
$watch.Stop()
if ($script:SmokeTimeout) { $fail += "окно не закрылось само за 300 с. Сторож:`n" + (($script:WatchLog | Select-Object -Last 25) -join "`n") }
# контраст: каждый видимый текст на каждом снятом экране в обеих темах (lib\gui.ps1, Find-UiContrastIssues)
$cf = Join-Path $env:TR_SMOKE_SHOTS 'contrast.txt'
if (Test-Path $cf) {
    $cl = @(Get-Content $cf -Encoding UTF8 | Where-Object { $_ })
    if ($cl.Count) { $fail += "контраст текста ниже нормы WCAG ($($cl.Count)):`n" + (($cl | Select-Object -First 30) -join "`n") }
    else { Write-Host 'Контраст текста: всё в норме' -ForegroundColor Green }
}
if ($env:TR_SMOKE_STEP -like 'ошибка*') { $fail += $env:TR_SMOKE_STEP }
elseif ($env:TR_SMOKE_STEP -ne 'закрытие') { $fail += "проверка окна остановилась на шаге «$env:TR_SMOKE_STEP»" }
foreach ($f in @(Get-ChildItem $script:PB.LogDir -Filter 'ui-error_*.txt' -ErrorAction SilentlyContinue)) {
    $fail += "ошибка в окне: " + (Get-Content $f.FullName -Raw -Encoding UTF8)
}
$own = @($Error | Where-Object { $_.InvocationInfo -and $_.InvocationInfo.ScriptName -match '[\\/](lib|catalog)[\\/]' } |
    ForEach-Object { "$($_.Exception.Message) @ $(Split-Path $_.InvocationInfo.ScriptName -Leaf):$($_.InvocationInfo.ScriptLineNumber)" } | Select-Object -Unique)
if ($own.Count) { Write-Host "Ошибки в журнале PowerShell ($($own.Count)):"; $own | ForEach-Object { Write-Host "  $_" } }
if ($fail.Count -and $own.Count) { $fail += "ошибки PowerShell из lib:`n" + (($own | Select-Object -First 10) -join "`n") }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($fail.Count) {
    $fail | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red; if ($env:GITHUB_ACTIONS) { Write-Host ("::error title=tests/smoke.ps1::" + ($_ -replace '%', '%25' -replace '\r?\n', '%0A')) } }
    [Environment]::Exit(1)   # фоновые задачи окна (runspace) не должны держать процесс
}
if ($own.Count -and $env:GITHUB_ACTIONS) { Write-Host ("::warning title=tests/smoke.ps1::" + (($own | Select-Object -First 10) -join '%0A')) }
Write-Host 'Окно открылось, отработало и закрылось без ошибок' -ForegroundColor Green
[Environment]::Exit(0)
