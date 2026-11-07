using System.IO;
using System.IO.Compression;
using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

public sealed record Asset(string Name, long Size, string Url);

public sealed record Release(string Tag, string Title, bool Prerelease, DateTime? Published, string Device, string Version,
                             Asset Installer, List<Asset> Images, Asset? Sums, Asset? Sig)
{
    public Asset? Image => Images.FirstOrDefault(i => i.Name.Contains("nogms")) ?? Images.FirstOrDefault();
}

/// A release laid out on disk the way the install guide has it: the release files in one folder and the installer
/// in its installer\ subfolder. The client only checks sizes; signature and checksum are the installer's job.
public sealed record Workspace(string Dir, string InstallerDir, string Image, string Tag, string Device);

public static class Releases
{
    const string Repo = "Project-Lumen-OS/lumen-os";
    static readonly Regex InstallerRe = new(@"^lumen-os-(?:(play6|hb)-)?(\d[\w.-]*?)-installer\.zip$");

    public static async Task<List<Release>> ListAsync()
    {
        using var doc = await Net.JsonAsync($"https://api.github.com/repos/{Repo}/releases?per_page=60");
        var list = new List<Release>();
        foreach (var r in doc.RootElement.EnumerateArray())
        {
            var assets = r.GetProperty("assets").EnumerateArray()
                .Select(a => new Asset(a.GetProperty("name").GetString()!, a.GetProperty("size").GetInt64(), a.GetProperty("browser_download_url").GetString()!))
                .ToList();
            var inst = assets.FirstOrDefault(a => InstallerRe.IsMatch(a.Name));
            if (inst == null) continue;
            var m = InstallerRe.Match(inst.Name);
            DateTime? pub = r.TryGetProperty("published_at", out var p) && p.ValueKind == System.Text.Json.JsonValueKind.String ? p.GetDateTime() : null;
            list.Add(new Release(r.GetProperty("tag_name").GetString()!, r.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "",
                r.GetProperty("prerelease").GetBoolean(), pub, m.Groups[1].Success && m.Groups[1].Value.Length > 0 ? m.Groups[1].Value : "z9x",
                m.Groups[2].Value, inst, assets.Where(a => a.Name.EndsWith("-system.img")).ToList(),
                assets.FirstOrDefault(a => a.Name == "SHA256SUMS"), assets.FirstOrDefault(a => a.Name == "SHA256SUMS.sig")));
        }
        return list;
    }

    /// Every file of this release is already in %USERPROFILE%\Lumen Installer\releases\<tag> with the size GitHub gives,
    /// and the installer is unpacked: nothing to download again (the installer checks signature and sha256 before writing).
    public static bool IsDownloaded(Release rel)
    {
        if (rel.Sums == null || rel.Sig == null || rel.Image == null) return false;
        var dir = Path.Combine(Paths.Releases, rel.Tag);
        return new[] { rel.Installer, rel.Sums, rel.Sig, rel.Image }.All(a => File.Exists(Path.Combine(dir, a.Name)) && new FileInfo(Path.Combine(dir, a.Name)).Length == a.Size)
            && File.Exists(Path.Combine(dir, "installer", "lumen-install.ps1"));
    }

    public static async Task<Workspace> PrepareAsync(Release rel, string? ptZip, Action<string, long, long> progress, CancellationToken ct)
    {
        if (rel.Sums == null || rel.Sig == null || rel.Image == null) throw new AppError(Loc.T("err.nosums"));
        var dir = Path.Combine(Paths.Releases, rel.Tag);
        var files = new[] { rel.Installer, rel.Sums, rel.Sig, rel.Image };
        var total = files.Sum(f => f.Size);
        long before = 0;
        foreach (var f in files)
        {
            ct.ThrowIfCancellationRequested();
            var b = before;
            await Net.DownloadAsync(f.Url, Path.Combine(dir, f.Name), f.Size, (d, _) => progress(f.Name, b + d, total), ct);
            before += f.Size;
        }
        await Task.Run(() => ZipFile.ExtractToDirectory(Path.Combine(dir, rel.Installer.Name), dir, true), ct);
        var inst = Path.Combine(dir, "installer");
        if (ptZip != null)   // the checked Google zip: the installer checks it again and unpacks it itself
        {
            var tools = Path.Combine(inst, "tools");
            Directory.CreateDirectory(tools);
            var dst = Path.Combine(tools, Path.GetFileName(ptZip));
            if (!File.Exists(dst)) File.Copy(ptZip, dst);
        }
        return new Workspace(dir, inst, Path.Combine(dir, rel.Image.Name), rel.Tag, rel.Device);
    }

    /// An unpacked release the user already has: the installer folder and an image next to it or one level up.
    public static Workspace Local(string folder)
    {
        var inst = new[] { folder, Path.Combine(folder, "installer") }.FirstOrDefault(d => File.Exists(Path.Combine(d, "lumen-install.ps1")))
                   ?? throw new AppError(Loc.T("err.noinstaller"));
        var parent = Path.GetDirectoryName(inst)!;
        var img = new[] { inst, parent }.SelectMany(d => Directory.Exists(d) ? Directory.GetFiles(d, "lumen-os-*-system.img") : [])
                  .FirstOrDefault() ?? throw new AppError(Loc.T("err.noimage"));
        var device = "z9x";
        var rc = Path.Combine(inst, "release.conf");
        if (File.Exists(rc)) { var m = Regex.Match(File.ReadAllText(rc), @"(?m)^DEVICE=(\w+)"); if (m.Success) device = m.Groups[1].Value; }
        return new Workspace(parent, inst, img, Path.GetFileName(folder), device);
    }
}
