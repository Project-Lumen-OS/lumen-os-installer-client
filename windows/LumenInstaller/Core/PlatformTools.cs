using System.IO;
using System.IO.Compression;
using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

/// adb and fastboot for finding the projector: Google's Platform-Tools in the version and with the sha256 that
/// lumen-install.ps1 pins (read from the script, never typed twice), on the installer's own adb server port 5038.
public sealed class PlatformTools
{
    public const string AdbPort = "5038";
    public string? Dir { get; private set; }
    public string? ZipPath { get; private set; }

    public sealed record Pin(string Ver, string Sha, string Zip, string Url);

    public static Pin Pinned()
    {
        var ps = File.ReadAllText(Path.Combine(Paths.BundledInstaller, "lumen-install.ps1"));
        var v = Regex.Match(ps, "(?m)^\\$PtVer\\s*=\\s*\"([^\"]+)\"");
        var s = Regex.Match(ps, "win\\s*=\\s*\"([0-9a-f]{64})\"");
        if (!v.Success || !s.Success) throw new AppError("lumen-install.ps1: no pinned Platform-Tools");
        var zip = $"platform-tools_r{v.Groups[1].Value}-win.zip";
        return new Pin(v.Groups[1].Value, s.Groups[1].Value, zip, $"https://dl.google.com/android/repository/{zip}");
    }

    public async Task EnsureAsync(Action<long, long> progress, CancellationToken ct = default)
    {
        var pin = Pinned();
        var baseDir = Path.Combine(Paths.Support, "platform-tools");
        var zip = Path.Combine(baseDir, pin.Zip);
        var outDir = Path.Combine(baseDir, "platform-tools");
        var marker = Path.Combine(outDir, ".lumen-client");
        if (File.Exists(marker) && File.ReadAllText(marker).Trim() == pin.Sha && File.Exists(zip) && File.Exists(Path.Combine(outDir, "adb.exe")))
        {
            Dir = outDir; ZipPath = zip; return;
        }
        if (!File.Exists(zip) || await Task.Run(() => Proc.Sha256(zip)) != pin.Sha)
        {
            await Net.DownloadAsync(pin.Url, zip, null, progress, ct);
            var got = await Task.Run(() => Proc.Sha256(zip));
            if (got != pin.Sha) { File.Delete(zip); throw new AppError(Loc.F("err.ptsha", pin.Zip, got[..12])); }
        }
        if (Directory.Exists(outDir)) Directory.Delete(outDir, true);
        await Task.Run(() => ZipFile.ExtractToDirectory(zip, baseDir, true), ct);
        if (!File.Exists(Path.Combine(outDir, "adb.exe"))) throw new AppError(Loc.F("err.ptunpack", pin.Zip));
        File.WriteAllText(marker, pin.Sha);
        Dir = outDir; ZipPath = zip;
    }

    static readonly Dictionary<string, string?> AdbEnv = new() { ["ANDROID_ADB_SERVER_PORT"] = AdbPort, ["ADB_SERVER_SOCKET"] = null };

    public Task<ProcResult> Adb(IEnumerable<string> args, int timeoutMs = 8000) =>
        Dir == null ? Task.FromResult(new ProcResult(-1, "", "adb not ready")) : Proc.RunAsync(Path.Combine(Dir, "adb.exe"), args, AdbEnv, timeoutMs);

    public Task<ProcResult> Fastboot(IEnumerable<string> args, int timeoutMs = 8000) =>
        Dir == null ? Task.FromResult(new ProcResult(-1, "", "fastboot not ready")) : Proc.RunAsync(Path.Combine(Dir, "fastboot.exe"), args, null, timeoutMs);

    public async Task KillServerAsync() { if (Dir != null) await Adb(["kill-server"], 5000); }
}
