// Tabula Rasa: модель окна выбора для WPF-привязок. Подключается из lib\gui.ps1 через Add-Type.
// C# 5 (компилятор .NET Framework 4.8, что есть в Windows PowerShell 5.1): без =>, ?., $"" и т.п.
// Правила выбора живут здесь, в сеттерах, чтобы их не обходила ни одна кнопка окна:
//   снял программу — сбросился вариант «с моими настройками»; выбрал «с моими» — программа отметилась;
//   установленная программа (IsLocked) отмечена и не снимается: с ней выполняется только выбранное действие
//   (Action: обновить / переустановить / удалить) или «с моими настройками»; удаление и «с моими» несовместимы.

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace PcBase
{
    public class Bindable : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise(string name)
        {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }

    // строка блока «подробности» справа: подпись, значение, тон (''/accent/danger)
    public class Fact
    {
        public string Label { get; set; }
        public string Value { get; set; }
        public string Tone { get; set; }
    }

    // пункт каталога: программа (app), настройка (tweak), файл из релиза files «Моих данных» (file),
    // программа на вкладке «Снятие настроек» (capture), результат поиска winget в окне «Добавить программу» (found)
    public class Item : Bindable
    {
        public Item() { Facts = new List<Fact>(); }

        public string Key { get; set; }          // app:<id>, tweak:<id>, file:<имя ассета>
        public string Kind { get; set; }
        public string Id { get; set; }
        public string Name { get; set; }
        public string Desc { get; set; }         // одна строка в карточке
        public string FullDesc { get; set; }     // полный текст справа
        public string CatKey { get; set; }       // apps|Повседневное
        public string CatName { get; set; }
        public string GroupTitle { get; set; }   // «Программы · Повседневное» — заголовок группы в поиске и в «Итоге»
        public string SearchText { get; set; }
        public bool Interactive { get; set; }
        public bool Irreversible { get; set; }
        public bool IsWeb { get; set; }
        public bool OpenSource { get; set; }      // бейдж «Open source»
        public bool IsMine { get; set; }          // из собственного каталога «Моих данных»: бейдж «мой каталог», можно удалить

        // статус на этом компьютере (lib\status.ps1): installed / update / missing / unknown; для твиков — applied / partial / no
        private string _statusKind = "";
        public string StatusKind
        {
            get { return _statusKind; }
            set
            {
                _statusKind = value ?? "";
                if (_action == "update" && _statusKind != "update") { _action = ""; RaiseAction(); }
                Raise("StatusKind"); Raise("CanUpdate");
            }
        }
        private string _statusText = "";
        public string StatusText { get { return _statusText; } set { _statusText = value ?? ""; Raise("StatusText"); Raise("HasStatus"); } }
        public bool HasStatus { get { return !string.IsNullOrEmpty(_statusText); } }

        // плитка слева: монограмма на спокойном цвете (стабилен по Id) или значок установленной программы из её exe
        public string Monogram { get; set; }
        public object MonoBrush { get; set; }
        public bool HasTile { get; set; }
        private object _icon;
        public object IconSource { get { return _icon; } set { _icon = value; Raise("IconSource"); Raise("HasIcon"); } }
        public bool HasIcon { get { return _icon != null; } }
        public bool HasConfig { get; set; }
        // файл настроек нашёлся (в своих данных или в движке); нет — «с моими» не включается
        private bool _cfgAvail = true;
        public bool ConfigAvailable
        {
            get { return _cfgAvail; }
            set { if (_cfgAvail == value) return; _cfgAvail = value; if (!value) ConfigOn = false; Raise("ConfigAvailable"); }
        }
        private string _cfgHint;                 // почему «с моими» недоступно
        public string ConfigHint { get { return _cfgHint; } set { _cfgHint = value; Raise("ConfigHint"); } }
        public string ConfigFile { get; set; }   // файл настроек внутри configs\ — чтобы перепроверить после входа
        public string ConfigName { get; set; }
        public string ConfigDesc { get; set; }
        public List<Fact> Facts { get; private set; }

        private bool _checked;
        public bool IsChecked
        {
            get { return _checked; }
            set
            {
                if (_locked && !value) return;   // установленную не снять
                if (_checked == value) return;
                _checked = value;
                if (!value && _config) { _config = false; Raise("ConfigOn"); Raise("ConfigOff"); }
                Raise("IsChecked"); Raise("IsPicked");
            }
        }

        // установлена на этом компьютере (статус installed / update): отмечена, серая, не снимается
        private bool _locked;
        public bool IsLocked
        {
            get { return _locked; }
            set
            {
                if (_locked == value) return;
                _locked = value;
                if (value) { _checked = true; Raise("IsChecked"); }
                else { _checked = false; _config = false; _action = ""; Raise("IsChecked"); Raise("ConfigOn"); Raise("ConfigOff"); RaiseAction(); }
                Raise("IsLocked"); Raise("CanToggle"); Raise("IsPicked"); Raise("ConfigLabel"); Raise("ConfigOffText");
            }
        }
        public bool CanToggle { get { return !_locked; } }
        public bool CanUpdate { get { return _locked && _statusKind == "update"; } }
        public bool CanRemove { get; set; }        // удаление — только для программ из winget

        // действие над установленной: "" (оставить), update, reinstall, remove
        private string _action = "";
        public string Action
        {
            get { return _action; }
            set
            {
                value = value ?? "";
                if (!_locked) value = "";
                if (value == "update" && _statusKind != "update") value = "";
                if (value == "remove" && !CanRemove) value = "";
                if (_action == value) return;
                _action = value;
                if (value == "remove" && _config) { _config = false; Raise("ConfigOn"); Raise("ConfigOff"); }
                RaiseAction();
            }
        }
        void RaiseAction() { Raise("Action"); Raise("ActKeep"); Raise("ActUpdate"); Raise("ActReinstall"); Raise("ActRemove"); Raise("ActionText"); Raise("HasAction"); Raise("IsPicked"); }
        public bool ActKeep { get { return _action == ""; } set { if (value) Action = ""; } }
        public bool ActUpdate { get { return _action == "update"; } set { if (value) Action = "update"; } }
        public bool ActReinstall { get { return _action == "reinstall"; } set { if (value) Action = "reinstall"; } }
        public bool ActRemove { get { return _action == "remove"; } set { if (value) Action = "remove"; } }
        public bool HasAction { get { return _action != ""; } }
        public string ActionText
        {
            get
            {
                switch (_action)
                {
                    case "update": return "будет обновлена";
                    case "reinstall": return "переустановка";
                    case "remove": return "будет удалена";
                    default: return "";
                }
            }
        }

        // зависимости (Э8, поле Requires каталога): отмечена автоматически вместе с тем, кому нужна; в сохранение не пишется
        public bool AutoAdded { get; set; }
        private string _neededBy = "";
        public string NeededBy { get { return _neededBy; } set { _neededBy = value ?? ""; Raise("NeededBy"); Raise("HasNeededBy"); Raise("NeededByText"); } }
        public bool HasNeededBy { get { return !string.IsNullOrEmpty(_neededBy); } }
        public string NeededByText { get { return string.IsNullOrEmpty(_neededBy) ? "" : "для " + _neededBy; } }

        // войдёт в прогон: отмеченная неустановленная или установленная с действием либо «с моими настройками»
        public bool IsPicked { get { return _checked && (!_locked || _action != "" || _config); } }

        // блок «Установка» в подробностях: у установленной — «Настройки: не менять / с моими настройками»
        public string ConfigLabel { get { return _locked ? "Настройки" : "Установка"; } }
        public string ConfigOffText { get { return _locked ? "Не менять" : "Чистая"; } }

        private bool _config;
        public bool ConfigOn
        {
            get { return _config; }
            set
            {
                if (!HasConfig || !_cfgAvail) value = false;
                if (_config == value) return;
                _config = value;
                if (value && _action == "remove") { _action = ""; RaiseAction(); }
                Raise("ConfigOn"); Raise("ConfigOff"); Raise("IsPicked");
                if (value) IsChecked = true;
            }
        }
        public bool ConfigOff
        {
            get { return !_config; }
            set { ConfigOn = !value; }
        }
    }

    // чип в шапке: имя компьютера, версия Windows, «в домене»; при нехватке места — значок с подсказкой
    public class Chip
    {
        public string Text { get; set; }
        public string Tip { get; set; }
        public string Icon { get; set; }
        public bool HasIcon { get { return !string.IsNullOrEmpty(Icon); } }
        public double MaxWidth { get; set; }
        public Chip() { MaxWidth = double.PositiveInfinity; }
    }

    // шаг плана и прогона (lib\run.ps1): фаза, название, пометка из плана, состояние и подробности по ходу прогона
    public class RunStep : Bindable
    {
        public string Key { get; set; }
        public string PhaseName { get; set; }
        public string Name { get; set; }
        public string Note { get; set; }
        public bool Irreversible { get; set; }

        private string _state = "wait";
        public string State
        {
            get { return _state; }
            set { if (_state == value) return; _state = value ?? "wait"; Raise("State"); Raise("Glyph"); Raise("StateText"); }
        }
        private string _detail = "";
        public string Detail { get { return _detail; } set { if (_detail == value) return; _detail = value ?? ""; Raise("Detail"); Raise("HasDetail"); } }
        public bool HasDetail { get { return !string.IsNullOrEmpty(_detail); } }

        // значки Segoe Fluent Icons / MDL2: ожидание, идёт, готово, уже было, пропущено, ошибка
        public string Glyph
        {
            get
            {
                switch (_state)
                {
                    case "run": return "\uE895";
                    case "done": return "\uE73E";
                    case "same": return "\uE930";
                    case "skip": return "\uE738";
                    case "error": return "\uE783";
                    default: return "\uEA3A";   // контурный кружок: «ожидает» не спорит с итогами шагов
                }
            }
        }
        public string StateText
        {
            get
            {
                switch (_state)
                {
                    case "run": return "выполняется";
                    case "done": return "готово";
                    case "same": return "уже было";
                    case "skip": return "пропущено";
                    case "error": return "ошибка";
                    default: return "ожидает";
                }
            }
        }
    }

    // строка навигации слева: заголовок раздела (header), категория (cat), разделитель (sep), «Итог» (summary)
    public class NavEntry : Bindable
    {
        public string Key { get; set; }
        public string Kind { get; set; }
        public string Section { get; set; }
        public string Name { get; set; }
        public string Icon { get; set; }          // значок категории (Segoe Fluent Icons / MDL2)

        private string _count = "";
        public string CountText { get { return _count; } set { if (_count != value) { _count = value; Raise("CountText"); } } }

        private bool _full;
        public bool IsFull { get { return _full; } set { if (_full != value) { _full = value; Raise("IsFull"); } } }

        private bool _dim;
        public bool IsDim { get { return _dim; } set { if (_dim != value) { _dim = value; Raise("IsDim"); } } }

        private bool _hit;
        public bool IsHit { get { return _hit; } set { if (_hit != value) { _hit = value; Raise("IsHit"); } } }
    }

    public static class Native
    {
        [DllImport("shcore.dll")]
        private static extern int SetProcessDpiAwareness(int value);
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
        [DllImport("kernel32.dll")]
        private static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hwnd, int cmd);
        [StructLayout(LayoutKind.Sequential)]
        private struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
        [DllImport("user32.dll")]
        private static extern bool FlashWindowEx(ref FLASHWINFO info);

        // консоль setup.ps1 при работе через окно не нужна; -Console оставляет её
        public static void ShowConsole(bool show)
        {
            try { IntPtr h = GetConsoleWindow(); if (h != IntPtr.Zero) ShowWindow(h, show ? 5 : 0); } catch (Exception) { }
        }

        // мигать кнопкой на панели задач, пока окно не активируют (прогон закончился, а окно свёрнуто)
        public static void Flash(IntPtr hwnd)
        {
            try
            {
                FLASHWINFO f = new FLASHWINFO();
                f.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO)); f.hwnd = hwnd; f.dwFlags = 3 | 12; f.uCount = 0; f.dwTimeout = 0;
                FlashWindowEx(ref f);
            } catch (Exception) { }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MARGINS { public int L, R, T, B; }
        [DllImport("dwmapi.dll")]
        private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);

        // фон DWM (Mica) на всю клиентскую область
        public static void ExtendFrame(IntPtr hwnd)
        {
            MARGINS m = new MARGINS(); m.L = -1; m.R = -1; m.T = -1; m.B = -1;
            try { DwmExtendFrameIntoClientArea(hwnd, ref m); } catch (Exception) { }
        }

        // Mica под окном (Windows 11 22H2+: DWMWA_SYSTEMBACKDROP_TYPE = 38, 2 — Mica); false — не поддерживается
        public static bool SetMica(IntPtr hwnd)
        {
            int v = 2;
            try { return DwmSetWindowAttribute(hwnd, 38, ref v, 4) == 0; } catch (Exception) { return false; }
        }

        // своя группа на панели задач: без этого окно садится в группу powershell.exe и берёт его значок
        public static void SetAppId(string appId)
        {
            try { SetCurrentProcessExplicitAppUserModelID(appId); } catch (Exception) { }
        }

        // до первого окна WPF: иначе на 125–150 % Windows растягивает картинку и она мылится
        public static void EnableDpiAwareness()
        {
            try { if (SetProcessDpiAwareness(2) == 0) return; } catch (Exception) { }
            try { SetProcessDPIAware(); } catch (Exception) { }
        }

        // тёмный заголовок окна (Windows 10 20H1+ и 11); на старых сборках молча ничего не делает
        public static void SetDarkTitleBar(IntPtr hwnd, bool dark)
        {
            int v = dark ? 1 : 0;
            try { if (DwmSetWindowAttribute(hwnd, 20, ref v, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref v, 4); } catch (Exception) { }
        }
    }
}
