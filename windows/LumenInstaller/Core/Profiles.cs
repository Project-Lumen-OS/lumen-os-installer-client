using System.IO;
using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

public enum Connection { Usb, Wifi }

/// A projector the client knows. What it IS comes from the installer's own lib\devices.conf (model code, board,
/// fastboot product, firmware); the client adds how the computer reaches it.
public sealed record Profile(string Id, string Name, string Model, string Board, string FbProduct, string[] Firmware,
                             Connection Connection, string? GappsAllow)
{
    public string GuideUrl(string lang) => $"https://github.com/Project-Lumen-OS/lumen-os/blob/main/docs/install/{Id}/{(lang == "ru" ? "ru" : "en")}.md";
    public string FirmwareText => string.Join(", ", Firmware);
}

public enum MatchBy { Model, Board, Fastboot, Serial }

/// detail: what identified it (the model code, board...), note: a localized remark (serial batches).
public sealed record DeviceMatch(string Id, MatchBy By, string Value, string? NoteKey = null, bool Warn = false);

public static class Profiles
{
    static readonly HashSet<string> Known = ["z9x", "play6", "hb"];

    /// Serial prefixes printed on the label / in ro.serialno. Only what the project has seen: a serial that matches
    /// nothing is not guessed, the user picks the model from the list.
    static readonly (string Prefix, string Id, string NoteKey, bool Warn)[] SerialRules =
    [
        ("XHN", "play6", "serial.xhn", false),
        ("XHF", "play6", "serial.xhf", true),
    ];

    public static List<Profile> Load(string installerDir)
    {
        var file = Path.Combine(installerDir, "lib", "devices.conf");
        var conf = new Dictionary<string, Dictionary<string, string>>();
        var order = new List<string>();
        if (!File.Exists(file)) return [];
        foreach (var raw in File.ReadAllLines(file))
        {
            var line = raw.Trim();
            if (line.StartsWith('#')) continue;
            var m = Regex.Match(line, @"^([a-z0-9]+)\.([A-Z0-9_]+)=(.*)$");
            if (!m.Success) continue;
            if (!conf.ContainsKey(m.Groups[1].Value)) { conf[m.Groups[1].Value] = []; order.Add(m.Groups[1].Value); }
            conf[m.Groups[1].Value][m.Groups[2].Value] = m.Groups[3].Value;
        }
        var list = new List<Profile>();
        foreach (var id in order)
        {
            if (!Known.Contains(id)) continue;
            var c = conf[id];
            string? gapps = c.GetValueOrDefault("GAPPS_ALLOW") ?? (id == "z9x" ? "lib/gapps_allow.txt" : id == "play6" ? "lib/play6/gapps_allow.txt" : null);
            list.Add(new Profile(id, c.GetValueOrDefault("NAME", id), c.GetValueOrDefault("MODEL", ""), c.GetValueOrDefault("BOARD", ""),
                c.GetValueOrDefault("FB_PRODUCT", ""), c.GetValueOrDefault("VENDOR_OK", "").Split(' ', StringSplitOptions.RemoveEmptyEntries),
                id == "z9x" ? Connection.Usb : Connection.Wifi, gapps));
        }
        return list;
    }

    /// Strongest evidence first: XGIMI's model code, the board, the fastboot product, then the serial prefix.
    public static DeviceMatch? Identify(IList<Profile> profiles, IDictionary<string, string>? props = null, string? fbProduct = null, string? serial = null)
    {
        if (props != null && props.TryGetValue("ro.boot.xgimi.modelname", out var model) && profiles.FirstOrDefault(p => p.Model == model) is { } a)
            return new DeviceMatch(a.Id, MatchBy.Model, model);
        if (props != null && props.TryGetValue("ro.boot.hardware", out var board) && profiles.FirstOrDefault(p => p.Board == board) is { } b)
            return new DeviceMatch(b.Id, MatchBy.Board, board);
        if (fbProduct != null && profiles.FirstOrDefault(p => p.FbProduct == fbProduct) is { } f)
            return new DeviceMatch(f.Id, MatchBy.Fastboot, fbProduct);
        return IdentifySerial(profiles, serial);
    }

    public static DeviceMatch? IdentifySerial(IList<Profile> profiles, string? serial)
    {
        var s = serial?.Trim().ToUpperInvariant();
        if (string.IsNullOrEmpty(s)) return null;
        foreach (var r in SerialRules)
            if (s.StartsWith(r.Prefix) && profiles.Any(p => p.Id == r.Id))
                return new DeviceMatch(r.Id, MatchBy.Serial, r.Prefix, r.NoteKey, r.Warn);
        return null;
    }
}
