# Tabula Rasa — инструкции для Claude Code (движок)

Публичный движок развёртывания и обслуживания компьютеров с Windows: одно окно с каталогом программ, настроек
Windows и файлов. Название в интерфейсе и текстах — «Tabula Rasa», технически (репозитории, URL, папки, id) — `tabula-rasa`.
С владельцем общаемся по-русски, на «ты», без канцелярита; правило ниже про тон касается только самой программы.

**Это публичный репозиторий — ничего личного.** Личное (журнал, планы, issues, аудиты, свои настройки программ,
сохранения) живёт в приватном репозитории владельца и на компьютере лежит в `C:\tabula-rasa-private`
(`$script:PB.DataRoot`). Здесь — только код, каталог, встроенные настройки по умолчанию, README.

## Жёсткие ограничения
- **Windows PowerShell 5.1 + .NET Framework 4.8** — на чистой Windows больше ничего нет. Никакого PS7-синтаксиса
  (`??`, `?.`, тернарник, `ForEach-Object -Parallel`), никаких внешних модулей и DLL. GUI — WPF из коробки;
  `Add-Type` для своего `lib/ui/model.cs` (C# 5) — можно.
- **Кодировка:** `.ps1` / `.psd1` / `.xaml` / `.cs` — UTF-8 с BOM, иначе 5.1 ломает кириллицу. `bootstrap.ps1` — только ASCII
  (идёт через `irm | iex`). JSON — UTF-8 без BOM.
- **Реестр, службы, задачи** — только через `Set-Reg` / `Set-SvcStart` / `Disable-Task` из `lib/common.ps1`,
  иначе изменение не попадёт в журнал и `undo.ps1` его не откатит.
- **Каталог** (`catalog/apps.psd1`) — только бесплатное навсегда и без условий. Исключения: Npcap, Docker Desktop.
  Бесплатность в описаниях не пишется; открытый код — полем `OpenSource = $true` (проверять по факту, лицензия OSI),
  условия и закрытый код — полем `License`.
- **Секреты и личное не коммитить**: пароли, ключи, токены, конфиги VPN, учётки, имена компьютеров и людей, работодатели.
  Свои настройки программ — в «Моих данных», не в `configs/` движка (`.gitignore` это страхует).
- **Сначала план**: «Показать план» ничего не меняет; применение — только кнопкой «Применить…» на экране плана и после
  подтверждения (в `-Console` — вопрос в консоли). Не ломать.
- Всё, что читает свои настройки, ищет их через `Find-PbConfig` (сначала `DataRoot\configs`, потом `Root\configs`);
  нет нигде — вариант «с моими настройками» недоступен, прогон не падает.
- **Мои данные**: git в `DataRoot` — только через `lib/data.ps1`; сеть (push, вход) — только в фоне, окно не ждёт.
  «Отключить и удалить» не трогать без нужды и не тестировать на живом входе — в тестах глушить `gh`, `cmdkey`, глобальный git.
- **Файлы** — только релиз `files` в репозитории данных текущего пользователя (`Get-PbDataRepo`), никаких захардкоженных
  владельцев. Имя ассета — ASCII (`ConvertTo-PbAssetName`), исходное имя — в `label`; после загрузки — сверка SHA-256 с `digest`.
  Google Drive — только в `tools/upload-files.ps1 -FromDrive` (переезд, с Диска только чтение), в движке его нет.
- **Свои данные любого пользователя**: репозиторий данных — `<логин>/tabula-rasa-private`, разметка по манифесту
  `tabula-rasa.json` (`Get-PbDataLayout`, `Install-PbDataLayout`): чужое в репозитории не удалять и не перезаписывать;
  манифест новее движка — только чтение (`Assert-PbDataWritable`). Публичный репозиторий — push не выполняется
  (`Test-PbDataPrivate` в `Push-PbData`). Свой каталог (`lib/catalog.ps1`) — только декларативно, без кода.
- **Настройки программ** — поле `Config` в каталоге (`Export` / `Import` в `lib/configs.ps1`); всё снятое проходит фильтр
  секретов (`Remove-PbJsonSecrets` / `Remove-PbTextSecrets`) и показывается перед записью. Пути профиля — переменными
  (`ConvertTo-PbPortablePath` при снятии, `Expand-PbPortablePath` / `Copy-PbConfigIn` при применении). Реестр программ —
  `Export-PbRegKey` → JSON → `Import-PbRegJson` через `Set-Reg`, не `reg import`.
- **Твики и статус**: в `Apply` — только `Set-Reg` / `Set-SvcStart` / `Disable-Task` / `Remove-Appx`, тогда «уже применено»
  проверяется само (`CheckOnly`). Любая другая команда — нужен `Check = { … }` только на чтение, иначе «не проверяется».
- **Прогон** — `lib/run.ps1`, один код для окна и `-Console`; в фоне — `$Sync`, никаких `Read-Host` (`Request-PbAnswer`).
- **Без консоли**: обычный запуск — скрытый процесс (`setup.ps1 -Spawned`, `Start-PbSetupHidden`); шаги старта —
  `Set-PbSplash` (`lib/splash.ps1`, не зависит от остального lib), вопросы — `Show-UiMessage`, падение — `Show-PbFatal`.
  `Read-Host` и вывод для пользователя в консоль — только при `-Console`. Окно пользователя не закрывать и не прятать.
- **«Уже было» и «изменено»**: `Set-Reg` / `Set-RegDefault` / `Set-SvcStart` / `Disable-Task` / `Remove-Appx` сначала
  сравнивают; совпало — не трогать и не писать в журнал изменений. Каждое действие — `Add-PbAction` (было → стало);
  по ним `Invoke-Tweak` пишет «уже было» / «применено» / «изменено N из M», программы — по `Get-PbWingetEntry` до и после.
- **Зависимости** — поле `Requires` в каталоге (программы и твики), а не текст в описании: в окне отмечаются вместе
  (`AutoAdded`, в сохранение не пишутся), в плане — пометка, если не отмечены; `tests/ci.ps1` проверяет id и циклы.
- **Цвета** — только кисти палитры (`Set-UiPalette`: Text, TextMuted, Accent, Success, Warning, Danger…), никаких
  зашитых цветов и системного чёрного: у текста цвет задаётся явно или наследуется от окна/списка с `Foreground = Text`.
  Контраст текстов в обеих темах проверяет `tests/smoke.ps1` в CI, снимки — в ветке `ci-screenshots`.
- **Перезагрузки** (Э9) — `lib/resume.ps1`: шаг, которому нужна перезагрузка до него, — состояние `reboot`
  (`$script:PB.RebootFirst`; пункт `Requires` → `RebootGate`-пункт, потребовавший перезагрузку). Конец прохода с такими
  шагами — `resume.json`, задача планировщика на вход, отсчёт 60 с; продолжение — `setup.ps1 -Resume`, тот же `Stamp`,
  один журнал изменений и отчёт. Шаг сам просит перезагрузку второй раз после настоящей перезагрузки — ошибка, не цикл.
  Временный автоматический вход — только по выбору пользователя: пароль — секрет LSA (`PcBase.AutoLogon`), в файлы и реестр
  открытым текстом не пишется; `AutoAdminLogon` — только на одну загрузку. Параметры Winlogon — временное состояние вне
  журнала изменений (не `Set-Reg`): прежние значения — `autologon.json`, возврат — `Clear-PbAutoLogon` (конец, отмена,
  запуск без незавершённого прогона). В тестах LSA, планировщик и Winlogon подменяются, на живом входе не проверять.
- **Отчёт** — `lib/report.ps1`, один механизм для окна, `-Console` и будущего клиентского отчёта; без личного, кроме
  имени компьютера (`Protect-PbReportText`), всё экранируется.
- **Старые места** (`C:\pc-base`, `C:\pc-base-private`, `%LOCALAPPDATA%\pc-base`, `%ProgramData%\pc-base`) — в `$script:PbLegacy`.
  Переезд — `Move-PbLegacyDir` / `Update-PbOrigin` в `setup.ps1` и свой в `bootstrap.ps1`; ничего не удалять.

## Тексты программы
Всё, что видит пользователь (окна, диалоги, уведомления, подсказки, вывод `setup.ps1` / `undo.ps1` / `bootstrap.ps1`,
`Desc` / `Manual` / `Note` / `Config.Desc` / `Config.Skip` / `License` в каталоге и твиках, README) — профессиональным тоном, как в Windows:
- безлично или нейтрально; если без обращения нельзя — «вы» со строчной. Никаких «ты», «твой», «тебе»;
- без разговорных конструкций и тире вместо сказуемого, полными предложениями, одна мысль — одно предложение;
- термины: «компьютер» (в чипах и коротких подписях можно «ПК»), «репозиторий», «удалить», «установить».

## Проверки перед коммитом
```powershell
# синтаксис всех скриптов
Get-ChildItem -Recurse -Include *.ps1,*.psd1 | ForEach-Object {
  $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null
  if ($e) { "$($_.Name): $($e[0].Message) @ $($e[0].Extent.StartLineNumber)" } }
# проверки без окна и без сети: должно быть «Все проверки пройдены»
./tests/run.ps1
# каталог грузится, id уникальны
$a = (Import-PowerShellDataFile ./catalog/apps.psd1).Apps; . ./catalog/tweaks.ps1
@($a.Id) + @($Tweaks.Id) | Group-Object | Where-Object Count -gt 1   # должно быть пусто
# тон: должно быть пусто (границы слов — юникодные, grep -w для кириллицы не работает)
$bad = '(?<!\p{L})(ты|твой|твоя|твоё|твои|твоих|твоим|твоей|тебе|тебя|снести|снесёт|сносит|снос|репа|репы|репу|репе|бесплатно)(?!\p{L})'
Get-ChildItem -Recurse -Include *.ps1,*.psd1,*.xaml,*.cs | Select-String -Pattern $bad |
  Where-Object { $_.Line -notmatch 'бесплатн\w* (навсегда|до|для|без)' } | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
```
```bash
# BOM: должно быть ef bb bf у всего, кроме bootstrap.ps1
for f in $(git ls-files '*.ps1' '*.psd1' '*.xaml' '*.cs'); do printf '%s ' "$f"; head -c3 "$f" | od -An -tx1; done
# bootstrap.ps1 — только ASCII: должно быть пусто
LC_ALL=C grep -nP '[^\x00-\x7F]' bootstrap.ps1
# личное: должно быть пусто (кроме iheeae в URL)
grep -rniE 'IHEEAE|ilyai|ЛАНИТ|LANIT|ВИСМО|VISMO|Хваев|Khvaev|gmail|isidor|C:\\Users\\[a-z]' . --exclude-dir=.git
```
Имя владельца `iheeae` в URL репозитория и Pages — допустимо. В примерах — `PC-01`, `user`, `Мой набор`.
Окно на Linux не открывается: если живой Windows нет — так и пиши в PR и давай чек-лист ручной проверки.

## Карта
```
bootstrap.ps1        загрузчик: winget, git, переезд C:\pc-base, клон в C:\tabula-rasa (постороннюю копию отодвигает), setup.ps1
setup.ps1            точка входа: скрытый перезапуск с правами, заставка, переезд старых папок, обновление, синхронизация
                     «Моих данных», окно, прогон, итог; падение — «Что-то пошло не так»
undo.ps1             откат по журналу изменений (ищет и в старой папке логов)
lib/common.ps1       $script:PB (Root, DataRoot…), $script:PbLegacy, Find-PbConfig, реестр/службы/задачи с журналом, winget, установка с сайта
lib/data.ps1         сохранения (Read-/Write-SaveFile, Save-/Rename-/Remove-PbSave), Мои данные (Connect-/Disconnect-PbData, Push-PbData,
                     Get-PbDataRepo, Test-PbDataPrivate), разметка (Get-PbDataLayout, Install-PbDataLayout), Invoke-PbGh
lib/catalog.ps1      свой каталог (Read-/Write-PbUserCatalog, Add-/Remove-PbUserApp), поиск winget (Search-PbWinget, разбор по колонкам)
lib/status.ps1       статус: программы (реестр Uninstall → winget list, ConvertFrom-PbWingetList), твики (Get-PbTweakStatus в common.ps1)
lib/run.ps1          план и прогон: Get-PbRunPlan (шаги по фазам), Invoke-PbRun ($Sync из окна или консоль), Get-PbChangeLogs, Invoke-PbUndo
lib/resume.ps1       продолжение после перезагрузки (Э9): resume.json, задача «Tabula Rasa — продолжение прогона», Get-PbRebootForecast
                     (в run.ps1), временный автоматический вход (Enable-/Clear-PbAutoLogon, Set-PbAutoLogonArmed)
lib/report.ps1       отчёт о прогоне: HTML в «Документы\Tabula Rasa\Отчёты» и в logs (Write-PbReport, Protect-PbReportText)
lib/selfremove.ps1   удаление с компьютера: Get-PbSelfRemoveParts, скрипт очистки во временной папке (ждёт процесс, удаляет
                     только свои папки — Test-PbSafeRemovePath, «Мои данные» — Test-PbOwnDataRoot), два подтверждения в окне
lib/splash.ps1       заставка в своём STA-потоке (Start-/Set-/Close-PbSplash), Show-PbFatal; грузится до остального lib
lib/files.ps1        «Файлы»: релиз files репозитория данных (Get-PbFiles, Save-PbFiles — загрузка со сверкой SHA-256, ConvertTo-PbAssetName)
lib/gui.ps1          окно (Show-SelectionDialog: «Установка | Снятие настроек», план/прогон/итог — RunPane), «Добавить программу»,
                     «Откат изменений» (Show-UndoDialog), значок «TR», тема (фирменная палитра Set-UiPalette, кнопка в шапке,
                     высокая контрастность), ui.json; снимки и контраст текстов для CI (Save-UiShot, Find-UiContrastIssues);
                     фоновые задачи — runspace + DispatcherTimer; скриптблоки твиков в фоне — только свои (tweaks.ps1 заново)
lib/ui/              main/dialog/addapp.xaml, theme.xaml (стили), model.cs (модель для привязок)
lib/configs.ps1      настройки программ: Export-*/Set-* по полю Config, фильтр секретов, снятие через временную папку
catalog/apps.psd1    программы       catalog/tweaks.ps1  настройки Windows
configs/             встроенное по умолчанию (pwsh_profile.ps1) и README с форматом «Моих данных»
tools/               export-vivaldi.ps1 (обёртка Export-VivaldiConfig); upload-files.ps1 — файлы в релиз files, переезд с Google Drive
tests/run.ps1        проверки без окна и без сети (winget ru/en, свой каталог, секреты, пути профиля, снятие, реестр, разметка,
                     план и прогон, отчёт, заставка)
.github/workflows/   pages.yml — bootstrap.ps1 на GitHub Pages: irm iheeae.github.io/tabula-rasa | iex
```
