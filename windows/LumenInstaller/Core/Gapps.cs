using System.IO;
using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

/// The one MindTheGapps zip the installer accepts for a projector (lib\*gapps_allow.txt, hashes only — no Google
/// file ships with Lumen OS). The client fetches it from its official URL and checks it before the installer does.
public sealed record GappsZip(string Sha, string Name, long Size, string GmsVersion, string Url);

public static class Gapps
{
    public static GappsZip? Allowed(string installerDir, string? rel)
    {
        if (rel == null) return null;
        var file = Path.Combine(installerDir, rel.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(file)) return null;
        foreach (var line in File.ReadLines(file))
        {
            var m = Regex.Match(line, @"^zip=([0-9a-f]{64}) (\S+) size=(\d+) .*?gmsversion=(\S+) url=(\S+)");
            if (m.Success) return new GappsZip(m.Groups[1].Value, m.Groups[2].Value, long.Parse(m.Groups[3].Value), m.Groups[4].Value, m.Groups[5].Value);
        }
        return null;
    }

    public static string LocalCopy(GappsZip z) => Path.Combine(Paths.Google, z.Name);

    /// null when the file is the accepted zip, else the (localized) reason it is not.
    public static string? Check(string file, GappsZip z, Action<long, long> progress)
    {
        var size = new FileInfo(file).Length;
        if (size != z.Size) return Loc.F("gapps.badsize", size, z.Size, z.Name);
        return Proc.Sha256(file, progress) == z.Sha ? null : Loc.F("gapps.badsha", z.Name);
    }
}
