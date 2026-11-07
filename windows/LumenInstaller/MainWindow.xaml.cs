using System.Collections.Specialized;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using LumenInstaller.Core;
using LumenInstaller.Views;

namespace LumenInstaller;

public partial class MainWindow : Window
{
    readonly MainViewModel vm = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = vm;
        vm.PromptRequested += OnPrompt;
        vm.PromptWithdrawn += () => current?.Withdraw();
        vm.Log.CollectionChanged += (_, e) =>
        {
            if (e.Action == NotifyCollectionChangedAction.Add) Dispatcher.BeginInvoke(() => LogScroll.ScrollToEnd());
        };
        SourceInitialized += (_, _) => DarkTitleBar();
        SizeChanged += (_, _) => DrawStars();
    }

    PromptWindow? current;

    void OnPrompt(Prompt p)
    {
        var dlg = new PromptWindow(p) { Owner = this };
        current = dlg;
        dlg.ShowDialog();
        current = null;
        if (!dlg.Withdrawn) vm.Answer(dlg.Answer ?? "no");
    }

    /// A fixed scatter of stars (the same every time), like the backdrop of the macOS client.
    void DrawStars()
    {
        Stars.Children.Clear();
        var rnd = new Random(7);
        for (var i = 0; i < 90; i++)
        {
            var r = 0.6 + rnd.NextDouble();
            var e = new Ellipse { Width = r, Height = r, Fill = new SolidColorBrush(Color.FromArgb((byte)(60 + rnd.Next(110)), 255, 255, 255)) };
            Canvas.SetLeft(e, rnd.NextDouble() * ActualWidth);
            Canvas.SetTop(e, rnd.NextDouble() * ActualHeight);
            Stars.Children.Add(e);
        }
    }

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    /// Windows 10 1809+ / 11: a dark title bar to match the window.
    void DarkTitleBar()
    {
        try
        {
            var h = new WindowInteropHelper(this).Handle;
            var on = 1;
            if (DwmSetWindowAttribute(h, 20, ref on, sizeof(int)) != 0) DwmSetWindowAttribute(h, 19, ref on, sizeof(int));
        }
        catch { }
    }
}
