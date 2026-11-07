using System.IO;

namespace LumenInstaller.Core;

/// SystemUI Tuner: turns on USB debugging on a stock XGIMI, whose Developer options menu is hidden (install guides,
/// "Prepare the projector"). The APK of its author's release 362 on GitHub (zacharee/Tweaker), checked against the
/// sha256 below. XGIMI's file manager does not open .apk files, so it goes on the USB stick as .apk1.
public static class Tuner
{
    public const string Version = "362";
    public const string Url = "https://github.com/zacharee/Tweaker/releases/download/362/SystemUITuner_362-release.apk";
    public const string Source = "https://github.com/zacharee/Tweaker/releases/tag/362";
    public const long Size = 17_952_121;
    public const string Sha = "ac29d665e5da358d1536ba73b866a9b3b66662b80fdac8e67408f4a257af477e";
    public const string StickName = "SystemUITuner.apk1";
    public static string FilePath => Path.Combine(Paths.WorkRoot, "tools", "SystemUITuner_362-release.apk");

    public static bool Ready => File.Exists(FilePath) && new FileInfo(FilePath).Length == Size && Proc.Sha256(FilePath) == Sha;

    public static async Task FetchAsync(Action<long, long> progress, CancellationToken ct = default)
    {
        await Net.DownloadAsync(Url, FilePath, Size, progress, ct);
        if (await Task.Run(() => Proc.Sha256(FilePath), ct) != Sha) { File.Delete(FilePath); throw new AppError(Loc.T("tuner.err.sha")); }
    }

    /// Copies the APK into a folder (the USB stick) as SystemUITuner.apk1.
    public static string CopyTo(string folder)
    {
        var dst = Path.Combine(folder, StickName);
        File.Copy(FilePath, dst, true);
        return dst;
    }
}
