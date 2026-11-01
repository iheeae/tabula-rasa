# Tabula Rasa: отчёт о прогоне — один HTML-файл без внешних ссылок (открывается в браузере, в PDF — печатью из браузера).
#
# Пишется в конце каждого прогона (Invoke-PbRun, lib\run.ps1) — и из окна, и из -Console: «Документы\Tabula Rasa\Отчёты»
# и копия в папке журналов. Содержимое: компьютер, Windows, дата, шаги по фазам с результатом, что не получилось,
# что было настроено до прогона, что выполнить вручную, журнал изменений для отката. У шагов — раскрывающийся список
# действий «было → стало» (Actions шага); при печати раскрывается весь. Личного нет: пути профиля заменяются переменными
# (%USERPROFILE% и т. п.), имя пользователя и репозиторий данных в отчёт не попадают — кроме имени компьютера.

$script:PbStepStateText = @{ done = 'выполнено'; same = 'уже было'; skip = 'пропущено'; error = 'ошибка'; wait = 'не выполнялось'; run = 'прервано'; reboot = 'после перезагрузки' }

# действия шага: сводка («изменено 3 из 5») и список «было → стало» под ней
function ConvertTo-PbActionsHtml ($Actions) {
    $a = @($Actions | Where-Object { $_ })
    if (-not $a.Count) { return '' }
    $ch = @($a | Where-Object { $_.Changed }).Count
    $sum = if (-not $ch) { "без изменений: $($a.Count)" } elseif ($ch -eq $a.Count) { "изменено: $ch" } else { "изменено $ch из $($a.Count)" }
    $li = foreach ($x in $a) {
        $v = if ($x.Changed) { "$(ConvertTo-PbHtml $x.Old) → <b>$(ConvertTo-PbHtml $x.New)</b>" } else { "$(ConvertTo-PbHtml $x.New) <span class=`"muted`">(уже было)</span>" }
        "<li><code>$(ConvertTo-PbHtml $x.Target)</code>: $v</li>"
    }
    return "<details><summary>$sum</summary><ul>$($li -join '')</ul></details>"
}

function Get-PbReportDir { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Tabula Rasa\Отчёты' }

# пути профиля → переменные, чтобы в отчёте не было имени пользователя
function Protect-PbReportText ([string]$Text) {
    if (-not $Text) { return '' }
    # длинные первыми: %LOCALAPPDATA% раньше %USERPROFILE%
    $vars = @(@{ N = 'LOCALAPPDATA'; V = $env:LOCALAPPDATA }, @{ N = 'APPDATA'; V = $env:APPDATA }, @{ N = 'USERPROFILE'; V = $env:USERPROFILE }) |
        Where-Object { $_.V } | Sort-Object { $_.V.Length } -Descending
    foreach ($v in @($vars)) { $Text = $Text -replace [regex]::Escape($v.V), "%$($v.N)%" }
    if ($env:USERNAME) { $Text = $Text -replace ('(?<![\p{L}\d])' + [regex]::Escape($env:USERNAME) + '(?![\p{L}\d])'), '<пользователь>' }
    return $Text
}

function ConvertTo-PbHtml ([string]$Text) { [Net.WebUtility]::HtmlEncode((Protect-PbReportText $Text)) }

# HTML отчёта. $Info: @{ Computer; Windows; Started; Finished; Engine; NeedReboot; Manual; ChangesFile; ChangesCount; LogDir; Error;
#   Boots (перезагрузок во время прогона); Pending (прогон продолжится после перезагрузки — отчёт промежуточный) }
function New-PbReportHtml ($Plan, $Info) {
    $steps = @($Plan)
    $cnt = @{}; foreach ($k in $script:PbStepStateText.Keys) { $cnt[$k] = @($steps | Where-Object { $_.State -eq $k }).Count }
    $bad = @($steps | Where-Object { $_.State -eq 'error' })
    $sb = New-Object Text.StringBuilder
    $title = "Отчёт Tabula Rasa: $($Info.Computer), $($Info.Finished.ToString('dd.MM.yyyy HH:mm'))"
    [void]$sb.Append(@"
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>$([Net.WebUtility]::HtmlEncode($title))</title>
<style>
:root { --bg:#f3f3f3; --card:#fff; --text:#1b1b1b; --muted:#5f5f5f; --line:#e5e5e5; --ok:#0f7b0f; --warn:#9d5d00; --bad:#c42b1c; --accent:#0067c0; }
@media (prefers-color-scheme: dark) { :root { --bg:#202020; --card:#2b2b2b; --text:#fff; --muted:#ababab; --line:#383838; --ok:#6ccb5f; --warn:#fce100; --bad:#ff99a4; --accent:#60cdff; } }
* { box-sizing:border-box }
body { margin:0; padding:32px 16px; background:var(--bg); color:var(--text); font:14px/1.5 "Segoe UI Variable Text","Segoe UI",sans-serif }
main { max-width:960px; margin:0 auto }
h1 { font-size:28px; font-weight:600; margin:0 0 4px } h2 { font-size:20px; font-weight:600; margin:28px 0 8px }
.muted { color:var(--muted) } .card { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:16px 20px; margin-top:12px }
dl { display:grid; grid-template-columns:max-content 1fr; gap:4px 24px; margin:0 } dt { color:var(--muted) } dd { margin:0; overflow-wrap:anywhere }
.sum { display:flex; flex-wrap:wrap; gap:8px; margin-top:16px } .pill { padding:4px 12px; border-radius:999px; border:1px solid var(--line); background:var(--card) }
table { width:100%; border-collapse:collapse } th, td { text-align:left; vertical-align:top; padding:8px 8px; border-bottom:1px solid var(--line) }
th { color:var(--muted); font-weight:600 } td.st { white-space:nowrap } td.d { overflow-wrap:anywhere; color:var(--muted) }
tr.ph td { font-weight:600; padding-top:16px; border-bottom:none }
details { margin-top:4px } summary { cursor:pointer; color:var(--accent) } details ul { margin:4px 0 0; padding-left:18px } details li { margin:2px 0 }
.same { color:var(--muted) } .done { color:var(--ok) } .skip { color:var(--warn) } .error, .run { color:var(--bad) } .wait { color:var(--muted) } .reboot { color:var(--accent) }
.alert { border-left:4px solid var(--bad) } .note { border-left:4px solid var(--accent) }
ol { margin:0; padding-left:20px } code { font-family:Consolas,monospace; font-size:13px; overflow-wrap:anywhere }
@media print { body { background:#fff; color:#000; padding:0 } .card { border-color:#ccc } :root { --muted:#444; --line:#ccc } }
</style></head><body><main>
<h1>Отчёт Tabula Rasa</h1>
<div class="muted">$([Net.WebUtility]::HtmlEncode("Компьютер $($Info.Computer) · $($Info.Finished.ToString('dd.MM.yyyy HH:mm'))"))</div>
<div class="card"><dl>
<dt>Компьютер</dt><dd>$([Net.WebUtility]::HtmlEncode($Info.Computer))</dd>
<dt>Windows</dt><dd>$(ConvertTo-PbHtml $Info.Windows)</dd>
<dt>Начало</dt><dd>$($Info.Started.ToString('dd.MM.yyyy HH:mm:ss'))</dd>
<dt>Окончание</dt><dd>$($Info.Finished.ToString('dd.MM.yyyy HH:mm:ss'))</dd>
<dt>Версия Tabula Rasa</dt><dd>$(ConvertTo-PbHtml $Info.Engine)</dd>
$(if ($Info.Boots) { "<dt>Перезагрузок во время прогона</dt><dd>$([int]$Info.Boots)</dd>" })
</dl></div>
<div class="sum">
<span class="pill">Шагов: $($steps.Count)</span><span class="pill done">Выполнено: $($cnt.done)</span>
$(if ($cnt.same) { "<span class=`"pill same`">Уже было: $($cnt.same)</span>" })
$(if ($cnt.skip) { "<span class=`"pill skip`">Пропущено: $($cnt.skip)</span>" })
$(if ($cnt.error) { "<span class=`"pill error`">С ошибкой: $($cnt.error)</span>" })
$(if ($cnt.wait + $cnt.run) { "<span class=`"pill wait`">Не выполнено: $($cnt.wait + $cnt.run)</span>" })
$(if ($cnt.reboot) { "<span class=`"pill reboot`">После перезагрузки: $($cnt.reboot)</span>" })
</div>
"@)
    if ($Info.Error) { [void]$sb.Append("<div class=`"card alert`"><b>Прогон прерван.</b> $(ConvertTo-PbHtml $Info.Error)</div>`n") }
    if ($Info.Pending) { [void]$sb.Append("<div class=`"card note`"><b>Прогон продолжится после перезагрузки.</b> Это промежуточный отчёт: после перезагрузки и входа в Windows оставшиеся шаги выполнятся, и отчёт будет заменён итоговым.</div>`n") }
    elseif ($Info.NeedReboot) { [void]$sb.Append("<div class=`"card note`"><b>Нужна перезагрузка.</b> Часть изменений вступит в силу после перезагрузки компьютера.</div>`n") }
    if ($bad.Count) {
        [void]$sb.Append("<h2>Что не получилось</h2><div class=`"card alert`"><table>`n")
        foreach ($s in $bad) { [void]$sb.Append("<tr><td>$(ConvertTo-PbHtml $s.Name)</td><td class=`"d`">$(ConvertTo-PbHtml $s.Detail)</td></tr>`n") }
        [void]$sb.Append("</table></div>`n")
    }
    $manual = @($Info.Manual | Where-Object { $_ })
    if ($manual.Count) {
        [void]$sb.Append("<h2>Выполнить вручную</h2><div class=`"card`"><ol>`n")
        foreach ($m in $manual) { [void]$sb.Append("<li>$(ConvertTo-PbHtml $m)</li>`n") }
        [void]$sb.Append("</ol></div>`n")
    }
    $same = @($steps | Where-Object { $_.State -eq 'same' })
    if ($same.Count) {
        [void]$sb.Append("<h2>Было настроено до прогона</h2><div class=`"card`"><p class=`"muted`">Эти пункты были отмечены, но менять их не пришлось: всё нужное уже стояло.</p><table>`n")
        foreach ($s in $same) { [void]$sb.Append("<tr><td>$(ConvertTo-PbHtml $s.Name)</td><td class=`"d`">$(ConvertTo-PbHtml $s.Detail)$(ConvertTo-PbActionsHtml $s.Actions)</td></tr>`n") }
        [void]$sb.Append("</table></div>`n")
    }
    [void]$sb.Append("<h2>Шаги</h2><div class=`"card`"><table><tr><th>Шаг</th><th>Результат</th><th>Подробности</th></tr>`n")
    $ph = $null
    foreach ($s in $steps) {
        if ($s.PhaseName -ne $ph) { $ph = $s.PhaseName; [void]$sb.Append("<tr class=`"ph`"><td colspan=`"3`">$(ConvertTo-PbHtml $ph)</td></tr>`n") }
        $st = [string]$s.State
        # пометки плана — прогноз («уже применено: будет пропущено», «обновление: …»); после прогона их заменяет результат.
        # Остаются только те, что важны и потом: необратимость и перезагрузка
        $note = if ($s.State -in 'wait', 'skip' -or [string]$s.Note -match 'необратимо|перезагруз') { $s.Note } else { '' }
        $d = @($s.Detail, $note | Where-Object { $_ }) -join ' · '
        [void]$sb.Append("<tr><td>$(ConvertTo-PbHtml $s.Name)</td><td class=`"st $st`">$($script:PbStepStateText[$st])</td><td class=`"d`">$(ConvertTo-PbHtml $d)$(ConvertTo-PbActionsHtml $s.Actions)</td></tr>`n")
    }
    [void]$sb.Append("</table></div>`n<h2>Откат и журналы</h2><div class=`"card`"><dl>`n")
    if ($Info.ChangesFile) {
        [void]$sb.Append("<dt>Журнал изменений</dt><dd><code>$(ConvertTo-PbHtml $Info.ChangesFile)</code> (изменений: $($Info.ChangesCount))</dd>`n")
        [void]$sb.Append("<dt>Откат</dt><dd>В окне Tabula Rasa: «⋯ → Откат изменений», или <code>undo.ps1</code>. Удалённые встроенные приложения и установленные программы так не возвращаются: для них используется точка восстановления «tabula-rasa &lt;дата&gt;».</dd>`n")
    } else { [void]$sb.Append("<dt>Журнал изменений</dt><dd>Изменений реестра, служб и задач не было.</dd>`n") }
    [void]$sb.Append("<dt>Журналы выполнения</dt><dd><code>$(ConvertTo-PbHtml $Info.LogDir)</code></dd>`n</dl></div>`n")
    [void]$sb.Append("<p class=`"muted`">Отчёт создан Tabula Rasa. Чтобы сохранить его в PDF, используйте печать в браузере (Ctrl+P → «Сохранить как PDF»).</p>`n</main>`n<script>addEventListener('beforeprint', function () { document.querySelectorAll('details').forEach(function (d) { d.open = true }) })</script>`n</body></html>`n")
    return $sb.ToString()
}

# записать отчёт: «Документы\Tabula Rasa\Отчёты» и копия в журналах. Возвращает путь к основному файлу
# (не вышло записать в «Документы» — путь к копии в журналах; не вышло нигде — $null)
function Write-PbReport ($Plan, $Info) {
    $html = New-PbReportHtml $Plan $Info
    $name = "report_$($Info.Computer)_$($Info.Finished.ToString('yyyy-MM-dd_HHmmss')).html"
    $enc = New-Object Text.UTF8Encoding $false
    $main = $null
    foreach ($dir in @((Get-PbReportDir), $Info.LogDir)) {
        if (-not $dir) { continue }
        try {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
            $f = Join-Path $dir $name
            [IO.File]::WriteAllText($f, $html, $enc)
            if (-not $main) { $main = $f }
        } catch { Write-Warn2 "отчёт не записан в $($dir): $($_.Exception.Message)" }
    }
    return $main
}
