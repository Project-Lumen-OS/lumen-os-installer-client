using System.IO;
using System.Net.Http;
using System.Text.Json;

namespace LumenInstaller.Core;

public static class Net
{
    static readonly HttpClient Http = CreateClient();

    static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("lumen-installer");
        return c;
    }

    public static async Task<JsonDocument> JsonAsync(string url, CancellationToken ct = default)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Accept.ParseAdd("application/vnd.github+json");
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(30000);
        using var resp = await Http.SendAsync(req, cts.Token);
        if (!resp.IsSuccessStatusCode) throw new AppError($"GitHub: HTTP {(int)resp.StatusCode}");
        return await JsonDocument.ParseAsync(await resp.Content.ReadAsStreamAsync(cts.Token), cancellationToken: cts.Token);
    }

    /// Downloads to dest (skipped when a file of the expected size is already there), through dest.part.
    public static async Task DownloadAsync(string url, string dest, long? size, Action<long, long> progress, CancellationToken ct = default)
    {
        if (size is long sz && File.Exists(dest) && new FileInfo(dest).Length == sz) { progress(sz, sz); return; }
        Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
        var part = dest + ".part";
        using (var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct))
        {
            if (!resp.IsSuccessStatusCode) throw new AppError($"HTTP {(int)resp.StatusCode}: {url}");
            var total = resp.Content.Headers.ContentLength ?? size ?? 0;
            await using var src = await resp.Content.ReadAsStreamAsync(ct);
            await using var dst = File.Create(part);
            var buf = new byte[1 << 20];
            long seen = 0;
            int n;
            var last = DateTime.MinValue;
            while ((n = await src.ReadAsync(buf, ct)) > 0)
            {
                await dst.WriteAsync(buf.AsMemory(0, n), ct);
                seen += n;
                if ((DateTime.UtcNow - last).TotalMilliseconds > 100) { progress(seen, total); last = DateTime.UtcNow; }
            }
            progress(seen, total);
        }
        if (size is long want && new FileInfo(part).Length != want) throw new AppError(Loc.F("err.incomplete", Path.GetFileName(dest)));
        File.Move(part, dest, true);
    }
}
