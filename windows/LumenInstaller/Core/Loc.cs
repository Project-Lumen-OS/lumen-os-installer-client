using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows.Data;
using System.Windows.Markup;

namespace LumenInstaller.Core;

/// The client's own texts in Russian, English and Simplified Chinese. XAML binds to Loc.Instance[key] (through the
/// {c:T key} extension) and updates live when the language changes; code uses Loc.T / Loc.F. The installer's own
/// output stays in its language: Russian for Russian, English for English and Chinese (it knows only those two).
public sealed class Loc : INotifyPropertyChanged
{
    public static Loc Instance { get; } = new();
    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action? LanguageChanged;

    static readonly string SettingsFile = Path.Combine(Paths.Support, "language.txt");
    public static readonly string[] Languages = ["ru", "en", "zh"];

    public string Lang { get; private set; }
    public string InstallerLang => Lang == "ru" ? "ru" : "en";
    public bool IsRu => Lang == "ru";
    public bool IsEn => Lang == "en";
    public bool IsZh => Lang == "zh";

    Loc()
    {
        string? saved = null;
        try { saved = File.Exists(SettingsFile) ? File.ReadAllText(SettingsFile).Trim() : null; } catch { }
        var sys = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        Lang = saved is "ru" or "en" or "zh" ? saved : sys is "ru" or "zh" ? sys : sys is "uk" or "be" or "kk" ? "ru" : "en";
    }

    public void SetLang(string l)
    {
        if (!Languages.Contains(l) || l == Lang) return;
        Lang = l;
        try { Directory.CreateDirectory(Paths.Support); File.WriteAllText(SettingsFile, l); } catch { }
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));
        LanguageChanged?.Invoke();
    }

    public string this[string key] => T(key);

    public static string T(string key)
    {
        if (!Strings.Table.TryGetValue(key, out var s)) return key;
        return Instance.Lang switch { "en" => s.En, "zh" => s.Zh, _ => s.Ru };
    }

    public static string F(string key, params object[] args) => string.Format(CultureInfo.InvariantCulture, T(key), args);
}

/// {c:T key}: a live-updating localized text.
public sealed class TExtension(string key) : MarkupExtension
{
    public string Key { get; set; } = key;
    public override object ProvideValue(IServiceProvider sp) =>
        new Binding($"[{Key}]") { Source = Loc.Instance, Mode = BindingMode.OneWay }.ProvideValue(sp);
}
