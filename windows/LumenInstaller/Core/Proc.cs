using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace LumenInstaller.Core;

public sealed record ProcResult(int Code, string Stdout, string Stderr)
{
    public string All => Stdout + Stderr;
}

public sealed class AppError(string message) : Exception(message);

public static class Proc
{
    /// Runs a program with a time limit; never throws (a program that cannot start returns code -1).
    /// env: a null value removes the variable (ADB_SERVER_SOCKET must be absent, an empty one breaks adb).
    public static async Task<ProcResult> RunAsync(string exe, IEnumerable<string> args, IDictionary<string, string?>? env = null,
                                                  int timeoutMs = 15000, string? cwd = null)
    {
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        if (cwd != null) psi.WorkingDirectory = cwd;
        Apply(psi, env);
        try
        {
            using var p = Process.Start(psi)!;
            p.StandardInput.Close();
            var o = p.StandardOutput.ReadToEndAsync();
            var e = p.StandardError.ReadToEndAsync();
            using var cts = new CancellationTokenSource(timeoutMs);
            try { await p.WaitForExitAsync(cts.Token); }
            catch (OperationCanceledException) { try { p.Kill(true); } catch { } return new ProcResult(124, await o, await e + "\n(timeout)"); }
            return new ProcResult(p.ExitCode, await o, await e);
        }
        catch (Exception ex) { return new ProcResult(-1, "", ex.Message); }
    }

    public static void Apply(ProcessStartInfo psi, IDictionary<string, string?>? env)
    {
        if (env == null) return;
        foreach (var (k, v) in env)
        {
            if (v == null) psi.Environment.Remove(k); else psi.Environment[k] = v;
        }
    }

    public static string Sha256(string file, Action<long, long>? progress = null)
    {
        using var fs = File.OpenRead(file);
        using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buf = new byte[4 << 20];
        long seen = 0, total = fs.Length;
        int n;
        while ((n = fs.Read(buf, 0, buf.Length)) > 0)
        {
            h.AppendData(buf, 0, n);
            seen += n;
            progress?.Invoke(seen, total);
        }
        return Convert.ToHexString(h.GetHashAndReset()).ToLowerInvariant();
    }

    public static Match Re(string pattern, string text, RegexOptions o = RegexOptions.None) => Regex.Match(text, pattern, o);
}
