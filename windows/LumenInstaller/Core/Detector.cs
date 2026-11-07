using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

public enum Transport { Usb, Wifi, Fastboot }

public sealed class Device
{
    public string Id => $"{Transport}:{Serial}";
    public required string Serial { get; init; }       // what adb/fastboot calls it (ip:port over Wi-Fi)
    public string? HwSerial { get; set; }               // ro.serialno
    public Transport Transport { get; init; }
    public required string State { get; init; }        // device | unauthorized | offline | fastboot
    public Dictionary<string, string> Props { get; set; } = [];
    public DeviceMatch? Match { get; set; }
    public string? LumenVersion { get; set; }
    public bool Lumen => LumenVersion != null;
    public string? Firmware { get; set; }
    public bool? FirmwareOk { get; set; }
    public string? FbProduct { get; set; }
}

/// Finds connected projectors over adb (cable or network) and in fastboot mode. Read-only: getprop and getvar.
public sealed class Detector(PlatformTools pt)
{
    readonly Dictionary<string, (Dictionary<string, string> Props, DateTime At)> cache = [];
    readonly object gate = new();

    public void ClearCache() { lock (gate) cache.Clear(); }

    public static Dictionary<string, string> ParseGetprop(string text)
    {
        var o = new Dictionary<string, string>();
        foreach (var line in text.Split('\n'))
        {
            var m = Regex.Match(line.Trim(), @"^\[([^\]]+)\]: \[(.*)\]$");
            if (m.Success) o[m.Groups[1].Value] = m.Groups[2].Value;
        }
        return o;
    }

    public async Task<List<Device>> ScanAsync(IList<Profile> profiles)
    {
        var found = new List<Device>();
        var a = await pt.Adb(["devices", "-l"], 10000);
        if (a.Code != 0 && a.Stdout.Length == 0) throw new AppError(a.Stderr.Length > 0 ? a.Stderr.Trim() : "adb");
        foreach (var line in a.Stdout.Split('\n').Skip(1))
        {
            var m = Regex.Match(line.Trim(), @"^(\S+)\s+(device|unauthorized|offline|recovery|sideload|no permissions)\b");
            if (!m.Success) continue;
            var serial = m.Groups[1].Value;
            var wifi = Regex.IsMatch(serial, @"^\d+\.\d+\.\d+\.\d+:\d+$") || serial.Contains("._adb");
            var d = new Device { Serial = serial, Transport = wifi ? Transport.Wifi : Transport.Usb, State = m.Groups[2].Value };
            if (d.State == "device")
            {
                (Dictionary<string, string> Props, DateTime At) c;
                bool have;
                lock (gate) have = cache.TryGetValue(serial, out c);
                if (!have || (DateTime.UtcNow - c.At).TotalSeconds > 15)
                {
                    var r = await pt.Adb(["-s", serial, "shell", "getprop"], 10000);
                    c = (ParseGetprop(r.Stdout), DateTime.UtcNow);
                    lock (gate) cache[serial] = c;
                }
                d.Props = c.Props;
                d.HwSerial = c.Props.GetValueOrDefault("ro.serialno") ?? (wifi ? null : serial);
                d.Match = Profiles.Identify(profiles, c.Props, serial: d.HwSerial);
                d.LumenVersion = c.Props.GetValueOrDefault("ro.z9x.version") ?? c.Props.GetValueOrDefault("ro.lumen.version");
                d.Firmware = c.Props.GetValueOrDefault("ro.vendor.build.version.incremental");
                var p = profiles.FirstOrDefault(x => x.Id == d.Match?.Id);
                if (p != null && d.Firmware != null) d.FirmwareOk = p.Firmware.Contains(d.Firmware.ToLowerInvariant());
            }
            found.Add(d);
        }
        var f = await pt.Fastboot(["devices"], 8000);
        foreach (var line in f.Stdout.Split('\n'))
        {
            var m = Regex.Match(line.Trim(), @"^(\S+)\s+fastboot");
            if (!m.Success) continue;
            var g = await pt.Fastboot(["-s", m.Groups[1].Value, "getvar", "product"], 8000);
            var pm = Regex.Match(g.All, @"product:\s*(\S+)");
            var d = new Device { Serial = m.Groups[1].Value, HwSerial = m.Groups[1].Value, Transport = Transport.Fastboot, State = "fastboot",
                                 FbProduct = pm.Success ? pm.Groups[1].Value : null };
            d.Match = Profiles.Identify(profiles, fbProduct: d.FbProduct, serial: d.Serial);
            found.Add(d);
        }
        return found;
    }

    public async Task<(bool Ok, string Text)> ConnectAsync(string addr)
    {
        var target = Regex.IsMatch(addr, @":\d+$") ? addr : addr + ":5555";
        var r = await pt.Adb(["connect", target], 15000);
        var text = r.All.Trim();
        return (text.Contains("connected to") && !text.Contains("failed", StringComparison.OrdinalIgnoreCase), text);
    }

    public async Task<List<string>> MdnsAsync()
    {
        var r = await pt.Adb(["mdns", "services"], 10000);
        var list = new List<string>();
        foreach (var l in r.Stdout.Split('\n'))
        {
            var m = Regex.Match(l.Trim(), @"^(\S+)\s+_adb[\w.-]*\s+(\d+\.\d+\.\d+\.\d+:\d+)");
            if (m.Success) list.Add(m.Groups[2].Value);
        }
        return list;
    }
}
