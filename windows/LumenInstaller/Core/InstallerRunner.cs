using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

public enum LineKind { Cmd, Info, Ok, Warn, Stop, Answer }

public sealed record LogLine(string Text, LineKind Kind);

public enum PromptKind { YesNo, Word, Enter, Text }

public sealed record Prompt(string Question, IReadOnlyList<string> Context, PromptKind Kind, string? Word);

public sealed class RunOptions
{
    public string? Command;
    public string Device = "z9x";
    public string? Serial, Ip, Image, GappsZip, Zip;
    public bool Remove, KeepData, NoBlobs;
    public string Lang = "ru";   // the installer knows en and ru

    /// lumen-install.ps1: the command first, then its named options.
    public List<string> Args()
    {
        var a = new List<string>();
        if (Command != null) a.Add(Command);
        a.AddRange(["-Lang", Lang]);
        if (Device != "z9x") a.AddRange(["-Device", Device]);
        if (Ip != null) a.AddRange(["-Ip", Ip]);
        if (Serial != null) a.AddRange(["-Serial", Serial]);
        if (Image != null) a.AddRange(["-Image", Image]);
        if (GappsZip != null) a.AddRange(["-GappsZip", GappsZip]);
        if (Zip != null) a.AddRange(["-Zip", Zip]);
        if (Remove) a.Add("-Remove");
        if (KeepData) a.Add("-KeepData");
        if (NoBlobs) a.Add("-NoBlobs");
        return a;
    }
}

/// Runs lumen-install.ps1 in Windows PowerShell and turns its console dialogue into lines and questions (yes/no, or a
/// word to type such as ERASE). Answers go to its stdin as typed; the script alone decides what is written.
/// Events are raised on the thread that started the run (the UI thread) through the captured SynchronizationContext.
public sealed class InstallerRunner
{
    public event Action<LogLine>? Line;
    public event Action<Prompt>? PromptAsked;
    public event Action? PromptGone;   // the "question" was output that went on (fastboot's progress), not a question
    bool asking;
    public event Action<int>? Exited;

    Process? proc;
    SynchronizationContext? ui;
    readonly object gate = new();
    string partial = "";
    readonly List<string> context = [];
    System.Threading.Timer? idle;

    public bool Running => proc is { HasExited: false };

    public void Start(string installerDir, RunOptions o)
    {
        ui = SynchronizationContext.Current;
        var psi = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = installerDir,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
            StandardInputEncoding = new UTF8Encoding(false),
        };
        foreach (var a in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(installerDir, "lumen-install.ps1") }) psi.ArgumentList.Add(a);
        var args = o.Args();
        foreach (var a in args) psi.ArgumentList.Add(a);
        Proc.Apply(psi, new Dictionary<string, string?> { ["ADB_SERVER_SOCKET"] = null });
        lock (gate) { partial = ""; context.Clear(); }
        Post(() => Line?.Invoke(new LogLine("> lumen-install.cmd " + string.Join(' ', args.Select(Quote)), LineKind.Cmd)));
        var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
        p.Start();
        proc = p;
        var o1 = Pump(p.StandardOutput);
        var o2 = Pump(p.StandardError);
        _ = Task.Run(async () =>
        {
            await p.WaitForExitAsync();
            await Task.WhenAll(o1, o2);
            lock (gate)
            {
                idle?.Dispose();
                if (partial.Length > 0) { EmitLine(partial); partial = ""; }
            }
            var code = p.ExitCode;
            Post(() => { proc = null; Exited?.Invoke(code); });
        });
    }

    static string Quote(string s) => s.Contains(' ') ? $"\"{s}\"" : s;

    Task Pump(StreamReader r) => Task.Run(async () =>
    {
        var buf = new char[4096];
        int n;
        while ((n = await r.ReadAsync(buf, 0, buf.Length)) > 0) Feed(new string(buf, 0, n));
    });

    void Feed(string s)
    {
        lock (gate)
        {
            idle?.Dispose();
            if (asking) { asking = false; Post(() => PromptGone?.Invoke()); }
            var parts = (partial + s.Replace("\r\n", "\n").Replace('\r', '\n')).Split('\n');
            partial = parts[^1];
            foreach (var l in parts[..^1]) EmitLine(l);
            if (partial.Length > 0) idle = new System.Threading.Timer(_ => PromptNow(), null, 300, Timeout.Infinite);
        }
    }

    void EmitLine(string text)
    {
        var body = Regex.Replace(text, @"^\d\d:\d\d:\d\d\s+", "");
        var kind = LineKind.Info;
        if (body.StartsWith("+ ") || body.StartsWith("✓")) kind = LineKind.Ok;
        else if (body.StartsWith("! ")) kind = LineKind.Warn;
        if (body.StartsWith("СТОП:") || body.StartsWith("STOP:")) kind = LineKind.Stop;
        if (text.Trim().Length == 0) context.Clear(); else context.Add(text);
        if (context.Count > 14) context.RemoveAt(0);
        var line = new LogLine(text, kind);
        Post(() => Line?.Invoke(line));
    }

    void PromptNow()
    {
        Prompt? p = null;
        lock (gate)
        {
            if (partial.Length == 0 || !Running) return;
            var q = partial.Trim();
            // only the installer's own questions: [yes/no], "Type ERASE", "press Enter", "Type this serial ...:".
            // Anything else without a newline is output still running (fastboot's "Sending sparse ... 3/4").
            PromptKind kind;
            string? word = null;
            if (Regex.IsMatch(q, @"\[(yes/no|да/нет)\]\s*:?\s*$")) kind = PromptKind.YesNo;
            else if (Regex.Match(q, @"(?:Type|Введите)\s+([A-Z]{3,})\b") is { Success: true } m) { kind = PromptKind.Word; word = m.Groups[1].Value; }
            else if (Regex.IsMatch(q, @"(?:press|нажмите) Enter\.?\s*:?\s*$", RegexOptions.IgnoreCase)) kind = PromptKind.Enter;
            else if (Regex.IsMatch(q, @"(?:Type|Введите)\b.*:\s*$")) kind = PromptKind.Text;
            else return;
            asking = true;
            p = new Prompt(q, context.ToList(), kind, word);
        }
        Post(() => PromptAsked?.Invoke(p));
    }

    /// The answer as typed. yes/no answers are sent as ASCII "yes"/"no": the script accepts them in both languages
    /// and they survive any console input code page.
    public void Answer(string text)
    {
        string shown;
        lock (gate) { shown = partial; partial = ""; context.Clear(); asking = false; }
        Line?.Invoke(new LogLine(shown + text, LineKind.Answer));
        try { proc?.StandardInput.WriteLine(text); proc?.StandardInput.Flush(); } catch { }
    }

    /// Windows has no Ctrl+C for a process without a console: the installer and its adb/fastboot are ended.
    public void Stop()
    {
        try { proc?.Kill(true); } catch { }
    }

    void Post(Action a)
    {
        if (ui != null) ui.Post(_ => a(), null); else a();
    }

    public static string StateFile(string device, string root) =>
        device == "z9x" ? Path.Combine(root, "state") : Path.Combine(root, device, "state");

    public static Dictionary<string, string> ReadState(string file)
    {
        var o = new Dictionary<string, string>();
        try
        {
            using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var r = new StreamReader(fs);
            string? l;
            while ((l = r.ReadLine()) != null)
            {
                var i = l.IndexOf('=');
                if (i > 0) o[l[..i].TrimStart('\uFEFF')] = l[(i + 1)..];
            }
        }
        catch { }
        return o;
    }
}
