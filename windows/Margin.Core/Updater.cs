using System.Security.Cryptography;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Margin.Core;

public sealed record UpdateInfo(
    Version Version, string Tag, string Notes, string PageUrl,
    string? InstallerUrl, string? InstallerName, long InstallerSize, string? Sha256);

/// Over-the-air updates. New versions are published as GitHub Releases of this app's repository;
/// the app asks GitHub for the latest one, and on Windows can download its installer and run it.
/// Only files served from this repository's own release downloads are accepted.
public static partial class Updater
{
    public const string Repo = "panch076/margin";
    public static string LatestUrl => $"https://api.github.com/repos/{Repo}/releases/latest";
    public static string ReleasesPage => $"https://github.com/{Repo}/releases";
    private static string DownloadPrefix => $"https://github.com/{Repo}/releases/download/";

    [GeneratedRegex(@"^v?(\d+)\.(\d+)(?:\.(\d+))?")] private static partial Regex VersionRx();
    [GeneratedRegex(@"^Margin-Setup-[A-Za-z0-9._-]+\.exe$")] private static partial Regex InstallerRx();

    /// "v1.2.3", "1.2" and "1.2.3-beta" all parse; anything else is null.
    public static Version? ParseVersion(string? tag)
    {
        if (string.IsNullOrWhiteSpace(tag)) return null;
        var m = VersionRx().Match(tag.Trim());
        if (!m.Success) return null;
        try
        {
            return new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value),
                m.Groups[3].Success ? int.Parse(m.Groups[3].Value) : 0);
        }
        catch (Exception e) when (e is FormatException or OverflowException or ArgumentException) { return null; }
    }

    private static Version Normalize(Version v) => new(v.Major, v.Minor, Math.Max(v.Build, 0));

    private static HttpClient Client(HttpMessageHandler? handler)
    {
        var http = handler is null ? new HttpClient() : new HttpClient(handler, disposeHandler: false);
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Margin-Updater/1.0");
        return http;
    }

    /// The latest release if it is newer than `current`, otherwise null. Never throws for network problems.
    public static async Task<UpdateInfo?> CheckAsync(Version current, CancellationToken ct = default, HttpMessageHandler? handler = null)
    {
        try
        {
            using var http = Client(handler);
            http.Timeout = TimeSpan.FromSeconds(15);
            using var req = new HttpRequestMessage(HttpMethod.Get, LatestUrl);
            req.Headers.Accept.ParseAdd("application/vnd.github+json");
            using var resp = await http.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode) return null;      // 404 simply means nothing has been released yet
            if (JsonNode.Parse(await resp.Content.ReadAsStringAsync(ct)) is not JsonObject o) return null;
            if (o["draft"]?.GetValue<bool>() == true || o["prerelease"]?.GetValue<bool>() == true) return null;

            var tag = o["tag_name"]?.ToString() ?? "";
            var version = ParseVersion(tag);
            if (version is null || version <= Normalize(current)) return null;

            string? url = null, name = null, sha = null;
            long size = 0;
            if (o["assets"] is JsonArray assets)
            {
                foreach (var a in assets.OfType<JsonObject>())
                {
                    var n = a["name"]?.ToString() ?? "";
                    var u = a["browser_download_url"]?.ToString() ?? "";
                    if (!InstallerRx().IsMatch(n) || !u.StartsWith(DownloadPrefix, StringComparison.Ordinal)) continue;
                    name = n; url = u;
                    size = a["size"] is JsonValue sv && sv.TryGetValue<long>(out var s) ? s : 0;
                    var digest = a["digest"]?.ToString();
                    if (digest is not null && digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)) sha = digest[7..].Trim().ToLowerInvariant();
                    break;
                }
            }
            var page = o["html_url"]?.ToString();
            if (page is null || !page.StartsWith($"https://github.com/{Repo}/", StringComparison.Ordinal)) page = ReleasesPage;
            return new UpdateInfo(version, tag, (o["body"]?.ToString() ?? "").Trim(), page, url, name, size, sha);
        }
        catch (Exception e) when (e is not OperationCanceledException || !ct.IsCancellationRequested)
        {
            return null;
        }
    }

    /// Downloads the release's installer to a temporary folder and returns its path.
    /// The size, and the SHA-256 that GitHub publishes for the file when available, must match.
    public static async Task<string> DownloadInstallerAsync(UpdateInfo info, IProgress<(long Done, long Total)>? progress,
        CancellationToken ct = default, HttpMessageHandler? handler = null, string? folder = null)
    {
        if (info.InstallerUrl is null || info.InstallerName is null || !InstallerRx().IsMatch(info.InstallerName)
            || !info.InstallerUrl.StartsWith(DownloadPrefix, StringComparison.Ordinal))
            throw new InvalidOperationException("This release has no Windows installer attached.");

        folder ??= Path.Combine(Path.GetTempPath(), "Margin-Update");
        Directory.CreateDirectory(folder);
        var target = Path.Combine(folder, info.InstallerName);
        var partial = target + ".part";

        using var http = Client(handler);
        http.Timeout = TimeSpan.FromMinutes(30);
        using var resp = await http.GetAsync(info.InstallerUrl, HttpCompletionOption.ResponseHeadersRead, ct);
        resp.EnsureSuccessStatusCode();
        var total = info.InstallerSize > 0 ? info.InstallerSize : resp.Content.Headers.ContentLength ?? 0;

        string hash;
        long done = 0;
        try
        {
            using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            await using (var input = await resp.Content.ReadAsStreamAsync(ct))
            await using (var output = new FileStream(partial, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, useAsync: true))
            {
                var buffer = new byte[1 << 16];
                int n;
                long lastReport = 0;
                while ((n = await input.ReadAsync(buffer, ct)) > 0)
                {
                    await output.WriteAsync(buffer.AsMemory(0, n), ct);
                    sha.AppendData(buffer, 0, n);
                    done += n;
                    if (done - lastReport >= 1 << 20) { lastReport = done; progress?.Report((done, total)); }
                }
            }
            hash = Convert.ToHexString(sha.GetHashAndReset()).ToLowerInvariant();
            if (info.InstallerSize > 0 && done != info.InstallerSize)
                throw new InvalidDataException("The update did not download completely. Try again.");
            if (info.Sha256 is not null && !string.Equals(hash, info.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The downloaded update does not match the published file, so it was discarded.");
        }
        catch
        {
            try { File.Delete(partial); } catch (IOException) { }
            throw;
        }
        progress?.Report((done, Math.Max(total, done)));
        File.Move(partial, target, overwrite: true);
        return target;
    }
}
