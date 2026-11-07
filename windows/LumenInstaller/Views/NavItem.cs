using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;

namespace LumenInstaller.Views;

/// A step in the sidebar: a numbered circle, its title and a one-line state.
public sealed class NavItem : Button
{
    public static readonly DependencyProperty NumberProperty = DependencyProperty.Register(nameof(Number), typeof(string), typeof(NavItem));
    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(nameof(Title), typeof(string), typeof(NavItem));
    public static readonly DependencyProperty SubProperty = DependencyProperty.Register(nameof(Sub), typeof(string), typeof(NavItem));
    public static readonly DependencyProperty DoneProperty = DependencyProperty.Register(nameof(Done), typeof(bool), typeof(NavItem));
    public static readonly DependencyProperty ActiveProperty = DependencyProperty.Register(nameof(Active), typeof(bool), typeof(NavItem));

    public string Number { get => (string)GetValue(NumberProperty); set => SetValue(NumberProperty, value); }
    public string Title { get => (string)GetValue(TitleProperty); set => SetValue(TitleProperty, value); }
    public string Sub { get => (string)GetValue(SubProperty); set => SetValue(SubProperty, value); }
    public bool Done { get => (bool)GetValue(DoneProperty); set => SetValue(DoneProperty, value); }
    public bool Active { get => (bool)GetValue(ActiveProperty); set => SetValue(ActiveProperty, value); }
}

/// true → "on" (for Tag-driven styles such as the language chips).
public sealed class BoolToOn : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value is true ? "on" : "off";
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}

/// empty string → Collapsed.
public sealed class TextToVisibility : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c) => value is string { Length: > 0 } ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object value, Type t, object p, CultureInfo c) => throw new NotSupportedException();
}
