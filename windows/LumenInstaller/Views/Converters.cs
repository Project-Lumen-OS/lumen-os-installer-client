using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace LumenInstaller.Views;

public sealed class InverseBoolToVisibility : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value is true ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class Not : IValueConverter
{
    public static readonly Not Instance = new();
    public object Convert(object value, Type t, object p, CultureInfo c) => value is not true;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => value is not true;
}

/// true → "ok", false → "bad" (for Tag-driven note styles).
public sealed class OkBad : IValueConverter
{
    public static readonly OkBad Instance = new();
    public object Convert(object value, Type t, object p, CultureInfo c) => value is true ? "ok" : "bad";
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}
