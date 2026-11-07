using System.IO;

namespace LumenInstaller.Core;

/// Where things live. Downloads go to a visible folder of the user's (%USERPROFILE%\Lumen Installer); the app's
/// helpers (Platform-Tools) to %LOCALAPPDATA%\Lumen Installer.
public static class Paths
{
    public static readonly string Home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    public static readonly string WorkRoot = Path.Combine(Home, "Lumen Installer");
    public static readonly string Releases = Path.Combine(WorkRoot, "releases");
    public static readonly string Google = Path.Combine(WorkRoot, "google");
    public static readonly string StateDir = Environment.GetEnvironmentVariable("LUMEN_STATE_DIR") is { Length: > 0 } s ? s : Path.Combine(Home, ".lumen-installer");
    public static readonly string Support = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lumen Installer");

    /// The installer shipped next to the exe (installer\), or, run from the source tree, vendor\lumen-os\installer.
    public static string BundledInstaller
    {
        get
        {
            var next = Path.Combine(AppContext.BaseDirectory, "installer");
            if (File.Exists(Path.Combine(next, "lumen-install.ps1"))) return next;
            var d = new DirectoryInfo(AppContext.BaseDirectory);
            while (d != null)
            {
                var cand = Path.Combine(d.FullName, "vendor", "lumen-os", "installer");
                if (File.Exists(Path.Combine(cand, "lumen-install.ps1"))) return cand;
                d = d.Parent;
            }
            return next;
        }
    }
}
