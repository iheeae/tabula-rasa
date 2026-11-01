# Tabula Rasa: каталог настроек Windows.
#
# Профилей и обязательных пунктов нет: каждая настройка — галочка в окне, телеметрия тоже.
# Os           — '10', '11' или оба: где твик вообще имеет смысл (на другой версии он не виден).
# Phase        — 'pre' (до установки программ) или 'post' (после: конфиги Terminal, pwsh).
# Irreversible — $true, если undo.ps1 это не вернёт (удаление UWP и т. п.); в окне помечается.
# Requires   — id программ и настроек, без которых настройка не работает (как в catalog\apps.psd1)
# Apply        — сам твик. Реестр, службы и задачи менять только через Set-Reg / Set-SvcStart /
#                Disable-Task, тогда изменения попадут в журнал и откатятся через undo.ps1.
# Manual       — что сделать вручную, попадёт в итоговый список.
# Desc         — что именно меняется; показывается в окне.
# Check        — только если Apply делает что-то кроме Set-Reg / Set-SvcStart / Disable-Task / Remove-Appx: проверка
#                «уже применено» без изменений, возвращает $true/$false. Остальные твики проверяются сами (CheckOnly);
#                без Check и с другими командами в Apply — статус «не проверяется»

$Adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

$Tweaks = @(

    # ============================== Приватность и телеметрия ==============================

    @{ Id = 'priv.telemetry'; Name = 'Телеметрия: минимальный уровень, служба DiagTrack отключена'; Desc = 'Политика телеметрии устанавливается на минимум; отключаются службы DiagTrack и WAP Push, задачи оценки совместимости, CEIP и сбора отзывов.'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           $dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
           Set-Reg $dc 'AllowTelemetry' 0
           Set-Reg $dc 'DoNotShowFeedbackNotifications' 1
           Set-Reg $dc 'AllowDeviceNameInTelemetry' 0
           Set-Reg $dc 'LimitDiagnosticLogCollection' 1
           Set-Reg $dc 'DisableOneSettingsDownloads' 1
           Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
           Set-SvcStart 'DiagTrack' 'Disabled'
           Set-SvcStart 'dmwappushservice' 'Disabled'
           Disable-Task '\Microsoft\Windows\Application Experience\' 'Microsoft Compatibility Appraiser'
           Disable-Task '\Microsoft\Windows\Application Experience\' 'ProgramDataUpdater'
           Disable-Task '\Microsoft\Windows\Customer Experience Improvement Program\' 'Consolidator'
           Disable-Task '\Microsoft\Windows\Customer Experience Improvement Program\' 'UsbCeip'
           Disable-Task '\Microsoft\Windows\Feedback\Siuf\' 'DmClient'
           Disable-Task '\Microsoft\Windows\Feedback\Siuf\' 'DmClientOnScenarioDownload'
           Disable-Task '\Microsoft\Windows\DiskDiagnostic\' 'Microsoft-Windows-DiskDiagnosticDataCollector'
       } }

    @{ Id = 'priv.ads'; Name = 'Реклама, рекомендации и автоматическая установка предлагаемых приложений'; Desc = 'Отключаются рекламный идентификатор, персонализированные предложения, советы в меню «Пуск», автоматическая установка рекламируемых приложений и экран завершения настройки Windows.'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
           Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
           $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
           foreach ($v in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
                          'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'OemPreInstalledAppsEnabled',
                          'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                          'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                          'SubscribedContent-353698Enabled') { Set-Reg $cdm $v 0 }
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
           $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
           Set-Reg $cc 'DisableWindowsConsumerFeatures' 1
           Set-Reg $cc 'DisableSoftLanding' 1
           Set-Reg $cc 'DisableCloudOptimizedContent' 1
           Set-Reg $Adv 'Start_IrisRecommendations' 0
           Set-Reg $Adv 'ShowSyncProviderNotifications' 0
       } }

    @{ Id = 'priv.activity'; Name = 'Журнал действий, сбор вводимого текста, онлайн-распознавание речи'; Desc = 'Отключаются журнал действий (Timeline), сбор набранного и рукописного текста и онлайн-распознавание речи.'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
           Set-Reg $sys 'PublishUserActivities' 0
           Set-Reg $sys 'UploadUserActivities' 0
           Set-Reg $sys 'EnableActivityFeed' 0
           Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
           Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
           Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
           Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
           Set-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
       } }

    @{ Id = 'priv.search'; Name = 'Поиск без Bing и интернета'; Desc = 'Поиск в меню «Пуск» выполняется только по компьютеру: без Bing, веб-подсказок и рекомендуемого содержимого.'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
       } }

    @{ Id = 'priv.ai'; Name = 'Отключить Copilot и Recall политиками'; Desc = 'Групповые политики отключают Copilot и запрещают Recall (снимки экрана для ИИ).'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
           Set-Reg $Adv 'ShowCopilotButton' 0
       } }

    # ============================== Проводник ==============================

    @{ Id = 'exp.ext'; Name = 'Показывать расширения файлов'; Desc = 'Проводник показывает расширения (.exe, .pdf и т. д.). Это затрудняет маскировку файлов вида «фото.jpg.exe».'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'HideFileExt' 0; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'exp.hidden'; Name = 'Показывать скрытые файлы'; Desc = 'Отображаются скрытые файлы и папки, например AppData. Защищённые системные файлы остаются скрытыми.'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'Hidden' 1; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'exp.thispc'; Name = 'Проводник открывается на «Этот компьютер»'; Desc = 'По Win+E Проводник открывает «Этот компьютер» с дисками вместо «Главной».'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'LaunchTo' 1 } }

    @{ Id = 'exp.norecent'; Name = 'Не показывать недавние файлы и частые папки'; Desc = 'Панель быстрого доступа не показывает недавние файлы и часто используемые папки, история не накапливается.'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
           Set-Reg $Adv 'Start_TrackDocs' 0
       } }

    @{ Id = 'exp.classicmenu'; Name = 'Классическое контекстное меню'; Desc = 'Правый клик сразу открывает полное контекстное меню, как в Windows 10, без пункта «Показать дополнительные параметры».'; Group = 'Проводник'; Os = @('11'); Phase = 'pre'
       Apply = { Set-RegDefault 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' ''; $script:PB.NeedExplorerRestart = $true } }

    # ============================== Панель задач ==============================

    @{ Id = 'tb.search'; Name = 'Убрать поиск с панели задач'; Desc = 'Скрывает поле или значок поиска на панели задач. Поиск по клавише Win сохраняется.'; Group = 'Панель задач'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'tb.taskview'; Name = 'Убрать кнопку «Представление задач»'; Desc = 'Скрывает кнопку виртуальных рабочих столов. Рабочие столы доступны по Win+Tab.'; Group = 'Панель задач'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'ShowTaskViewButton' 0; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'tb.widgets'; Irreversible = $true; Name = 'Удалить виджеты / отключить «Новости и интересы»'; Desc = 'Windows 11: удаляется пакет «Мини-приложения» (виджеты, включая карточки на экране блокировки). Windows 10: отключаются «Новости и интересы».'; Group = 'Панель задач'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           if ($script:PB.Os -eq '11') {
               Remove-Appx @('MicrosoftWindows.Client.WebExperience')
           } else {
               try { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' 'ShellFeedsTaskbarViewMode' 2 } catch { Write-Warn2 'раздел Feeds защищён ACL, пропущено' }
               Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
           }
           $script:PB.NeedExplorerRestart = $true
       } }

    @{ Id = 'tb.chat'; Name = 'Убрать значок «Чат» (Teams)'; Desc = 'Скрывает на панели задач значок «Чат» (Teams для дома).'; Group = 'Панель задач'; Os = @('11'); Phase = 'pre'
       Apply = { try { Set-Reg $Adv 'TaskbarMn' 0 } catch { Write-Warn2 'параметр TaskbarMn защищён ACL в этой сборке, пропущено' } } }

    @{ Id = 'tb.win10junk'; Name = 'Windows 10: убрать Кортану, «Люди» и «Провести собрание» с панели задач'; Desc = 'Скрывает на панели задач Windows 10 кнопки Кортаны, «Люди» и «Провести собрание».'; Group = 'Панель задач'; Os = @('10'); Phase = 'pre'
       Apply = {
           Set-Reg $Adv 'ShowCortanaButton' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People' 'PeopleBand' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1
           $script:PB.NeedExplorerRestart = $true
       } }

    @{ Id = 'tb.win10ink'; Name = 'Windows 10: убрать Windows Ink и сенсорную клавиатуру с панели задач'; Desc = 'Скрывает на панели задач Windows 10 кнопки Windows Ink и сенсорной клавиатуры.'; Group = 'Панель задач'; Os = @('10'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace' 'PenWorkspaceButtonDesiredVisibility' 0
           Set-Reg 'HKCU:\Software\Microsoft\TabletTip\1.7' 'TipbandDesiredVisibility' 0
       } }

    @{ Id = 'start.morepins'; Name = 'Windows 11: больше закреплённых приложений в меню «Пуск»'; Desc = 'Макет меню «Пуск» «Больше закреплённых»: меньше места под рекомендации.'; Group = 'Панель задач'; Os = @('11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'Start_Layout' 1 } }

    @{ Id = 'tb.left';Name = 'Кнопка «Пуск» слева'; Desc = 'Кнопка «Пуск» и значки панели задач выравниваются по левому краю, как в Windows 10.'; Group = 'Панель задач'; Os = @('11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'TaskbarAl' 0; $script:PB.NeedExplorerRestart = $true } }

    # ============================== Мусор ==============================

    @{ Id = 'bloat.uwp'; Irreversible = $true; Name = 'Удалить предустановленные приложения (новости, погода, советы, Clipchamp, Solitaire…)'; Desc = 'Удаляются предустановленные приложения: новости, погода, советы, Solitaire, Clipchamp, To Do, Skype, «Почта и календарь», «Кино и ТВ» и другие. Вернуть их можно только из Microsoft Store.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Remove-Appx @(
               'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
               'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.People', 'Microsoft.WindowsMaps',
               'Microsoft.WindowsFeedbackHub', 'Microsoft.549981C3F5F10', 'Clipchamp.Clipchamp', 'Microsoft.Todos',
               'Microsoft.PowerAutomateDesktop', 'Microsoft.SkypeApp', 'MicrosoftTeams', 'Microsoft.MixedReality.Portal',
               'Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.MSPaint', 'Microsoft.Wallet',
               'Microsoft.Messaging', 'Microsoft.OneConnect', 'microsoft.windowscommunicationsapps', 'Microsoft.Windows.DevHome',
               'Microsoft.ZuneVideo', 'Microsoft.WindowsSoundRecorder', 'Microsoft.MicrosoftJournal'
           )
       } }

    @{ Id = 'bloat.copilot'; Irreversible = $true; Name = 'Удалить приложение Copilot'; Desc = 'Удаляет приложение Copilot.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Remove-Appx @('Microsoft.Copilot') } }

    @{ Id = 'bloat.phonelink'; Irreversible = $true; Name = 'Удалить «Связь с телефоном» и Cross Device'; Desc = 'Удаляются «Связь с телефоном» и Cross Device; политика запрещает связывать компьютер с телефоном.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Remove-Appx @('Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice')
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableMmx' 0
       } }

    @{ Id = 'bloat.xbox'; Irreversible = $true; Name = 'Удалить компоненты Xbox'; Desc = 'Удаляются приложения Xbox и Game Bar, отключается запись игр. Не рекомендуется для игровых компьютеров с Game Pass.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Remove-Appx @('Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay',
                         'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider')
           Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
       } }

    @{ Id = 'bloat.onedrive'; Irreversible = $true; Name = 'Удалить OneDrive'; Desc = 'Удаляет OneDrive и скрывает его в Проводнике. Пропускается, если Рабочий стол или Документы перенесены в OneDrive.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Check = { -not (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe')) -and -not (Test-Path (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')) }
       Apply = {
           $usf = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
           if (@($usf.Desktop, $usf.Personal, $usf.'My Pictures') -match 'OneDrive') {
               throw 'Рабочий стол, Документы или Изображения перенесены в OneDrive. Удаление пропущено: сначала верните папки на компьютер.'
           }
           Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
           $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
           if ($setup) { Start-Process $setup -ArgumentList '/uninstall' -Wait }
           if (Get-Command winget -ErrorAction SilentlyContinue) { & winget uninstall --id Microsoft.OneDrive -e --silent --disable-interactivity 2>$null | Out-Null }
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
           Set-Reg 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
           $script:PB.NeedExplorerRestart = $true
       } }

    # ============================== Система ==============================

    @{ Id = 'sys.wsl'; Name = 'WSL2 и платформа виртуальных машин (для Docker)'; Desc = 'Включает WSL и платформу виртуальных машин, устанавливает ядро WSL2 (требуется для Docker). Потребуется перезагрузка.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'; RebootGate = $true
       Check = { @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform' | ForEach-Object { (Get-WindowsOptionalFeature -Online -FeatureName $_ -ErrorAction Stop).State } | Where-Object { $_ -ne 'Enabled' }).Count -eq 0 }
       Apply = {
           foreach ($f in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') {
               $st = (Get-WindowsOptionalFeature -Online -FeatureName $f).State
               if ($st -ne 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null; $script:PB.NeedReboot = $true }
           }
           & wsl.exe --install --no-distribution 2>$null | Out-Null
           & wsl.exe --set-default-version 2 2>$null | Out-Null
       }
       Manual = 'WSL: после перезагрузки при необходимости установить дистрибутив (wsl --install -d <имя>)' }

    @{ Id = 'sys.stickykeys'; Name = 'Отключить залипание клавиш по 5×Shift'; Desc = 'Пятикратное нажатие Shift больше не открывает окно залипания клавиш (полезно в играх).'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' -Type String } }

    @{ Id = 'sys.mouseaccel'; Name = 'Отключить ускорение мыши'; Desc = 'Отключается «Повышенная точность установки указателя»: курсор движется строго пропорционально мыши.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' -Type String
           Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' -Type String
           Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' -Type String
       } }

    @{ Id = 'sys.dark'; Name = 'Тёмная тема'; Desc = 'Тёмная тема для системы и приложений.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 0
       } }

    @{ Id = 'sys.highperf'; Name = 'Схема электропитания «Высокая производительность» (кроме ноутбуков)'; Desc = 'Включает схему электропитания «Высокая производительность». На ноутбуках пропускается.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Check = { [string](& powercfg.exe /getactivescheme) -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }   # SCHEME_MIN
       Apply = {
           if ($script:PB.IsLaptop) { Write-Warn2 'ноутбук, пропущено'; return }
           $old = $null
           if ((& powercfg.exe /getactivescheme) -match '([0-9a-fA-F-]{36})') { $old = $Matches[1] }
           & powercfg.exe /setactive SCHEME_MIN
           Add-PbChange ([ordered]@{ Kind = 'PowerScheme'; Old = $old })
       } }

    @{ Id = 'sys.nohiber'; Name = 'Отключить гибернацию и быстрый запуск'; Desc = 'Отключает гибернацию (файл hiberfil.sys занимает несколько гигабайт) и быстрый запуск. Спящий режим сохраняется.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Check = { (Get-PbRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled').Value -eq 0 }
       Apply = {
           $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
           & powercfg.exe /hibernate off
           Add-PbChange ([ordered]@{ Kind = 'Hibernate'; WasEnabled = ($v -ne 0) })
       } }

    # ============================== Среда (после установки программ) ==============================

    @{ Id = 'env.terminal'; Name = 'Windows Terminal: PowerShell 7 по умолчанию, Cascadia Code 11, выдвижная консоль Alt+`'; Desc = 'Профиль по умолчанию — PowerShell 7, шрифт Cascadia Code 11, выдвижная консоль по Alt+` (Alt+Ё), запуск при входе в систему со сворачиванием в область уведомлений.'; Group = 'Среда'; Os = @('10', '11'); Phase = 'post'
       Apply = { Set-TerminalConfig } }

    @{ Id = 'env.defaultterm'; Name = 'Windows Terminal как терминал по умолчанию'; Desc = 'Консольные программы открываются в Windows Terminal вместо окна conhost.'; Group = 'Среда'; Os = @('11'); Phase = 'post'
       Apply = {
           Set-Reg 'HKCU:\Console\%%Startup' 'DelegationConsole' '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}' -Type String
           Set-Reg 'HKCU:\Console\%%Startup' 'DelegationTerminal' '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}' -Type String
       } }

    @{ Id = 'env.pwshprofile'; Name = 'Профиль PowerShell 7: подсказки из истории, приглашение с веткой git, псевдонимы'; Desc = 'Устанавливает профиль PowerShell 7 (из Моих данных или встроенный): подсказки из истории, меню по Tab, ветка git в приглашении, псевдонимы ll, which и touch.'; Group = 'Среда'; Os = @('10', '11'); Phase = 'post'
       Apply = { Set-PwshProfile } }

    @{ Id = 'env.upgrade'; Name = 'Обновить все установленные программы (winget upgrade --all)'; Desc = 'В конце прогона обновляет все программы, известные winget. На рабочем компьютере затрагивает и корпоративное ПО.'; Group = 'Среда'; Os = @('10', '11'); Phase = 'post'
       Apply = {
           $r = Invoke-PbWingetTimed @('upgrade', '--all', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') 60 'upgrade_all'
           if ($r.TimedOut) { throw "winget upgrade --all не завершился за 60 мин и прерван; журнал: $($r.Log)" }
       } }
)

# ---------- функции для твиков «Среда» ----------

function Set-TerminalConfig {
    $dir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir 'settings.json'
    $pwshGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

    $cfg = $null
    if (Test-Path $file) {
        Copy-Item $file "$file.tabula-rasa_$($script:PB.Stamp).bak" -Force
        try { $cfg = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Write-Warn2 'settings.json не удалось разобрать, файл записан заново (копия сохранена рядом, .bak)' }
    }
    if (-not $cfg) { $cfg = [pscustomobject]@{ '$schema' = 'https://aka.ms/terminal-profiles-schema' } }

    function Set-Prop ($Obj, [string]$Name, $Value) { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

    # PowerShell 7 по умолчанию — только если он установлен (на старых сборках Windows 10 пакет может не встать)
    if (Test-Path (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')) { Set-Prop $cfg 'defaultProfile' $pwshGuid }
    else { Write-Warn2 'PowerShell 7 не установлен: профиль Terminal по умолчанию не изменён'; Add-Manual 'Windows Terminal: выбрать PowerShell 7 профилем по умолчанию после его установки' }
    Set-Prop $cfg 'startOnUserLogin' $true
    Set-Prop $cfg 'minimizeToNotificationArea' $true
    Set-Prop $cfg 'disabledProfileSources' @('Windows.Terminal.Azure')

    if (-not $cfg.profiles) { Set-Prop $cfg 'profiles' ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = @() }) }
    if ($cfg.profiles -is [array]) { Set-Prop $cfg 'profiles' ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = $cfg.profiles }) }
    if (-not $cfg.profiles.defaults) { Set-Prop $cfg.profiles 'defaults' ([pscustomobject]@{}) }
    Set-Prop $cfg.profiles.defaults 'font' ([pscustomobject]@{ face = 'Cascadia Code'; size = 11 })

    # квейк: старый формат (keys внутри actions) WT сам мигрирует в новый
    $actions = @()
    if ($cfg.actions) { $actions = @($cfg.actions | Where-Object { $_.keys -ne 'alt+sc(41)' -and $_.command -ne 'quakeMode' -and $_.command.action -ne 'quakeMode' }) }
    $actions += [pscustomobject]@{ command = [pscustomobject]@{ action = 'quakeMode' }; keys = 'alt+sc(41)' }
    Set-Prop $cfg 'actions' $actions
    if ($cfg.keybindings) {
        Set-Prop $cfg 'keybindings' @($cfg.keybindings | Where-Object { $_.keys -ne 'alt+sc(41)' })
    }

    $json = $cfg | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding $false))
    Write-Ok "Terminal: $file"
}

function Set-PwshProfile {
    # профиль из Моих данных перекрывает встроенный
    $src = Find-PbConfig 'pwsh_profile.ps1'
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $dst = Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    Copy-PbConfigIn $src $dst   # с копией .bak; %USERPROFILE% и т. п. в своём профиле раскрываются (lib\configs.ps1)
    Write-Ok "профиль PowerShell: $dst"
}
