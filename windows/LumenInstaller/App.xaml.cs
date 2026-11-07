using System.Windows;
using System.Windows.Threading;

namespace LumenInstaller;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += (_, a) =>
        {
            MainViewModel.ShowError(a.Exception.Message);
            a.Handled = true;
        };
        base.OnStartup(e);
    }
}
