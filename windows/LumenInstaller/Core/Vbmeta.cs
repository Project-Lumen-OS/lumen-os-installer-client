using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

public enum VbmetaState { Off, On, Unknown }

/// The one vbmeta step of the Z9X and the Z9X HB, done by the client when the user asks for it: exactly the
/// commands of the install guide (docs/install/z9x, "vbmeta"), with Google's unchanged vbmeta.img.
///
/// The file is the vbmeta.img of Google's Android 14 GSI aosp_arm64 UQ1A.231205.015 (developer.android.com,
/// "GSI releases"; the zip's sha256 below is the one Google publishes). Only its 2 KB deflated entry is fetched
/// with an HTTP range and inflated; the result must match the sha256 taken from the verified zip.
/// The installer then proves on its own, read-only, that verification is off (/dev/block/mapper).
public static class Vbmeta
{
    public const string ZipUrl = "https://dl.google.com/developers/android/udc/images/gsi/aosp_arm64-exp-UQ1A.231205.015-11084887-e291b838.zip";
    public const string ZipSha = "e291b838f9e2786eb44c952ca25469745c8085cf91611397d7f620136b48c086";
    const long EntryFrom = 935_876_542, EntryTo = 935_878_815;   // vbmeta.img, deflate
    public const int Size = 4096;
    public const string Sha = "b3281c527ecf2a6a743b37f5b9e118f492d2038e0a82e6777d292d1c5b42601a";
    public static string FilePath => Path.Combine(Paths.Support, "vbmeta", "vbmeta.img");

    /// Google's vbmeta.img, checked; fetched once.
    public static async Task<string> FetchAsync(CancellationToken ct)
    {
        if (File.Exists(FilePath) && Proc.Sha256(FilePath) == Sha) return FilePath;
        using var http = new HttpClient();
        using var req = new HttpRequestMessage(HttpMethod.Get, ZipUrl);
        req.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(EntryFrom, EntryTo);
        req.Headers.TryAddWithoutValidation("Accept-Encoding", "identity");   // with gzip allowed Google answers a range with 416
        using var resp = await http.SendAsync(req, ct);
        var data = await resp.Content.ReadAsByteArrayAsync(ct);
        if ((int)resp.StatusCode != 206 || data.Length != EntryTo - EntryFrom + 1) throw new AppError(Loc.T("vb.err.download"));
        using var inflate = new DeflateStream(new MemoryStream(data), CompressionMode.Decompress);
        using var img = new MemoryStream();
        await inflate.CopyToAsync(img, ct);
        if (img.Length != Size || Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(img.ToArray())).ToLowerInvariant() != Sha) throw new AppError(Loc.T("vb.err.sha"));
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        await File.WriteAllBytesAsync(FilePath, img.ToArray(), ct);
        return FilePath;
    }

    /// The installer's own read-only test: with verification off no dm-verity device is set up. The Z9X looks for
    /// system-verity, the Z9X HB for any *-verity.
    public static async Task<VbmetaState> StateAsync(PlatformTools pt, string serial, string device)
    {
        var r = await pt.Adb(["-s", serial, "shell", "ls", "/dev/block/mapper/"], 10000);
        var names = r.Stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (r.Code != 0 || names.Length == 0) return VbmetaState.Unknown;
        var on = device == "hb" ? names.Any(n => n.EndsWith("-verity")) : names.Contains("system-verity");
        return on ? VbmetaState.On : VbmetaState.Off;
    }

    /// adb reboot fastboot → fastboot --disable-verity --disable-verification --slot=all flash vbmeta → fastboot reboot,
    /// then waits for the stock system and checks the result. Nothing else is written.
    public static async Task RunAsync(PlatformTools pt, string img, string serial, string? hwSerial, string? ip, string device,
                                      Action<string, LineKind> log, CancellationToken ct)
    {
        log($"> adb -s {serial} reboot fastboot", LineKind.Cmd);
        await pt.Adb(["-s", serial, "reboot", "fastboot"], 20000);
        log(Loc.T("vb.wait.fb"), LineKind.Info);
        string? fb = null;
        for (var i = 0; i < 45 && fb == null; i++)
        {
            await Task.Delay(2000, ct);
            var list = (await pt.Fastboot(["devices"], 8000)).Stdout.Split('\n', StringSplitOptions.TrimEntries)
                .Select(l => Regex.Match(l, @"^(\S+)\s+fastboot")).Where(m => m.Success).Select(m => m.Groups[1].Value).ToList();
            if (hwSerial != null && list.Contains(hwSerial)) fb = hwSerial;
            else if (list.Count == 1) fb = list[0];
            else if (list.Count > 1) throw new AppError(Loc.T("vb.err.many"));
        }
        if (fb == null) throw new AppError(Loc.T(device == "hb" ? "vb.err.nofb.hb" : "vb.err.nofb"));

        string[] args = ["-s", fb, "--disable-verity", "--disable-verification", "--slot=all", "flash", "vbmeta", img];
        log("> fastboot " + string.Join(' ', args).Replace(img, "vbmeta.img"), LineKind.Cmd);
        var f = await pt.Fastboot(args, 60000);
        foreach (var l in f.All.Split('\n', StringSplitOptions.RemoveEmptyEntries)) log(l.TrimEnd('\r'), LineKind.Info);
        var both = new[] { "vbmeta_a", "vbmeta_b" }.All(s => Regex.IsMatch(f.All, $@"Writing '{s}'\s+OKAY"));

        log($"> fastboot -s {fb} reboot", LineKind.Cmd);
        await pt.Fastboot(["-s", fb, "reboot"], 20000);
        if (!both) throw new AppError(Loc.T("vb.err.notboth"));
        log(Loc.T("vb.ok.written"), LineKind.Ok);

        log(Loc.T("vb.wait.boot"), LineKind.Info);
        string? back = null;
        var want = ip ?? serial;
        for (var i = 0; i < 80 && back == null; i++)
        {
            await Task.Delay(3000, ct);
            if (ip != null && i % 3 == 0) await pt.Adb(["connect", ip], 10000);
            var devs = (await pt.Adb(["devices"], 8000)).Stdout.Split('\n', StringSplitOptions.TrimEntries);
            if (!devs.Any(l => l.Split((char[])[' ', '\t'], StringSplitOptions.RemoveEmptyEntries) is [var s, "device", ..] && s == want)) continue;
            if ((await pt.Adb(["-s", want, "shell", "getprop", "sys.boot_completed"], 8000)).Stdout.Trim() == "1") back = want;
        }
        if (back == null) throw new AppError(Loc.T("vb.err.noboot"));
        switch (await StateAsync(pt, back, device))
        {
            case VbmetaState.Off: log(Loc.T("vb.ok.off"), LineKind.Ok); break;
            case VbmetaState.On: throw new AppError(Loc.T("vb.err.stillon"));
            default: log(Loc.T("vb.warn.unknown"), LineKind.Warn); break;
        }
    }
}
