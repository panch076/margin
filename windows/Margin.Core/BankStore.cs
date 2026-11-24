using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Margin.Core;

public sealed class Bank
{
    public List<Question> Questions { get; } = new();
    public Dictionary<string, Question> ById { get; } = new();
    public int Unusable { get; set; }
    public DateTime? Updated { get; set; }
    public bool IsEmpty => Questions.Count == 0;
    public int Count(Section s) => Questions.Count(q => q.Section == s);
}

public sealed record DownloadProgress(string Stage, int Done, int Total, int Failed);
public sealed record DownloadSummary(int Added, int Failed, int Total);

/// The local copy of the question bank. Raw responses are kept in bank.jsonl (one question per line),
/// so the download can resume where it stopped and parsing can improve without downloading again.
public static class BankStore
{
    private const string Api = "https://qbank-api.collegeboard.org/msreportingquestionbank-prod/questionbank";
    private const string Disclosed = "https://saic.collegeboard.org/disclosed/";

    public static string DataDir { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Margin");

    public static string BankPath => Path.Combine(DataDir, "bank.jsonl");
    public static string LookupPath => Path.Combine(DataDir, "lookup.json");

    public static Bank Load()
    {
        var bank = new Bank();
        if (!File.Exists(BankPath)) return bank;
        var live = LoadLiveIds();
        var seenKeys = new HashSet<string>();
        foreach (var raw in File.ReadLines(BankPath, Encoding.UTF8))
        {
            if (string.IsNullOrWhiteSpace(raw)) continue;
            JsonNode? node;
            try { node = JsonNode.Parse(raw); } catch (JsonException) { continue; }   // a line cut short by a crash
            var q = Normalizer.FromLine(node, live);
            if (q is null) continue;
            var key = q.ExternalId ?? q.Ibn ?? q.Id;
            if (!seenKeys.Add(key) || bank.ById.ContainsKey(q.Id)) continue;
            if (!q.Gradable) { bank.Unusable++; continue; }
            bank.Questions.Add(q);
            bank.ById[q.Id] = q;
        }
        bank.Updated = File.GetLastWriteTime(BankPath);
        return bank;
    }

    private static HashSet<string> LoadLiveIds()
    {
        var set = new HashSet<string>();
        try
        {
            if (!File.Exists(LookupPath)) return set;
            var root = JsonNode.Parse(File.ReadAllText(LookupPath)) as JsonObject;
            foreach (var name in new[] { "readingLiveItems", "mathLiveItems" })
                if (root?[name] is JsonArray a)
                    foreach (var x in a)
                        if (x is JsonValue v && v.TryGetValue<string>(out var s)) set.Add(s);
        }
        catch { /* the "live" flag is optional */ }
        return set;
    }

    private static HashSet<string> StoredIds()
    {
        var ids = new HashSet<string>();
        if (!File.Exists(BankPath)) return ids;
        foreach (var raw in File.ReadLines(BankPath, Encoding.UTF8))
        {
            try
            {
                if (JsonNode.Parse(raw)?["stub"]?["questionId"] is JsonValue v && v.TryGetValue<string>(out var id)) ids.Add(id);
            }
            catch (JsonException) { }
        }
        return ids;
    }

    /// How many questions are fetched at the same time.
    public const int DefaultParallel = 20;

    /// Base pauses, in seconds, for retries and for backing off when the server says to slow down.
    /// Tests shorten them.
    public static double RetryBaseSeconds { get; set; } = 0.5;
    public static double ThrottleBaseSeconds { get; set; } = 2.0;

    /// Shared pause: when the server answers "too many requests", every worker waits, not just the one that was told.
    private sealed class Throttle
    {
        private long _resumeAt;     // Environment.TickCount64 before which no request should start
        private int _strikes;

        public async Task WaitAsync(CancellationToken ct)
        {
            var wait = Interlocked.Read(ref _resumeAt) - Environment.TickCount64;
            if (wait > 0) await Task.Delay(TimeSpan.FromMilliseconds(Math.Min(wait, 30_000)), ct);
        }

        public void SlowDown()
        {
            var strikes = Math.Min(Interlocked.Increment(ref _strikes), 5);
            var delayMs = (long)(Math.Min(30, ThrottleBaseSeconds * Math.Pow(2, strikes - 1)) * 1000);
            var until = Environment.TickCount64 + delayMs;
            long seen;
            do { seen = Interlocked.Read(ref _resumeAt); }
            while (until > seen && Interlocked.CompareExchange(ref _resumeAt, until, seen) != seen);
        }

        public void Recovered() => Interlocked.Exchange(ref _strikes, 0);
    }

    private static HttpClient CreateClient(HttpMessageHandler? handler, int parallel)
    {
        HttpClient http;
        if (handler is not null)
        {
            http = new HttpClient(handler, disposeHandler: false);
        }
        else
        {
            // Compressed responses, HTTP/2 where the server offers it, and enough connections for every worker otherwise.
            var sockets = new SocketsHttpHandler
            {
                AutomaticDecompression = System.Net.DecompressionMethods.All,
                MaxConnectionsPerServer = Math.Max(parallel, 2),
                EnableMultipleHttp2Connections = true,
                PooledConnectionIdleTimeout = TimeSpan.FromMinutes(2),
            };
            http = new HttpClient(sockets, disposeHandler: true)
            {
                DefaultRequestVersion = System.Net.HttpVersion.Version20,
                DefaultVersionPolicy = HttpVersionPolicy.RequestVersionOrLower,
            };
        }
        http.Timeout = TimeSpan.FromSeconds(60);
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Margin/1.0");
        http.DefaultRequestHeaders.Accept.ParseAdd("application/json");
        return http;
    }

    /// Downloads every question not yet stored. Safe to cancel and run again.
    public static async Task<DownloadSummary> DownloadAsync(
        IProgress<DownloadProgress>? progress, CancellationToken ct, HttpMessageHandler? handler = null, int parallel = DefaultParallel)
    {
        Directory.CreateDirectory(DataDir);
        parallel = Math.Clamp(parallel, 1, 64);
        using var http = CreateClient(handler, parallel);

        progress?.Report(new DownloadProgress("Reading the question list", 0, 0, 0));

        // The practice-test list and the two question lists are independent, so ask for all three at once.
        async Task SaveLookup()
        {
            try
            {
                var lookup = await http.GetStringAsync(Api + "/lookup", ct);
                if (JsonNode.Parse(lookup) is JsonObject) await File.WriteAllTextAsync(LookupPath, lookup, ct);
            }
            catch (Exception e) when (e is not OperationCanceledException) { /* optional */ }
        }
        async Task<List<(int Test, JsonObject Stub)>> List(int test, string domains)
        {
            using var resp = await http.PostAsJsonAsync(Api + "/digital/get-questions",
                new { asmtEventId = 99, test, domain = domains }, ct);
            resp.EnsureSuccessStatusCode();
            var list = JsonNode.Parse(await resp.Content.ReadAsStringAsync(ct)) as JsonArray
                       ?? throw new InvalidDataException("The question list came back in an unexpected format.");
            return list.OfType<JsonObject>().Select(o => (test, o)).ToList();
        }
        var lookupTask = SaveLookup();
        var rwTask = List(1, "INI,CAS,EOI,SEC");
        var mathTask = List(2, "H,P,Q,S");
        await Task.WhenAll(lookupTask, rwTask, mathTask);
        var stubs = rwTask.Result.Concat(mathTask.Result).ToList();

        var have = StoredIds();
        var keys = new HashSet<string>();
        var todo = new List<(int Test, JsonObject Stub, string Id)>();
        foreach (var (test, stub) in stubs)
        {
            var id = stub["questionId"]?.ToString();
            var key = NonEmpty(stub["external_id"]?.ToString()) ?? NonEmpty(stub["ibn"]?.ToString());
            if (string.IsNullOrEmpty(id) || key is null) continue;
            if (!keys.Add(key) || have.Contains(id)) continue;   // the same question is occasionally listed twice
            todo.Add((test, stub, id));
        }

        int done = 0, failed = 0, total = todo.Count;
        progress?.Report(new DownloadProgress("Downloading questions", 0, total, 0));
        if (total == 0) return new DownloadSummary(0, 0, stubs.Count);

        var throttle = new Throttle();
        var writeLock = new SemaphoreSlim(1, 1);
        // Lines are buffered and flushed every so often. Anything lost in a crash is simply fetched again next time.
        await using var writer = new StreamWriter(new FileStream(BankPath, FileMode.Append, FileAccess.Write, FileShare.Read), new UTF8Encoding(false), 1 << 16);
        var unflushed = 0;

        await Parallel.ForEachAsync(todo, new ParallelOptions { MaxDegreeOfParallelism = parallel, CancellationToken = ct }, async (item, token) =>
        {
            var detail = await FetchWithRetry(http, item.Stub, throttle, token);
            if (detail is null) { Interlocked.Increment(ref failed); }
            else
            {
                var line = new JsonObject { ["test"] = item.Test, ["stub"] = item.Stub.DeepClone(), ["detail"] = detail };
                var text = line.ToJsonString();
                await writeLock.WaitAsync(token);
                try
                {
                    await writer.WriteLineAsync(text);
                    if (++unflushed >= 25) { unflushed = 0; await writer.FlushAsync(token); }
                }
                finally { writeLock.Release(); }
            }
            var d = Interlocked.Increment(ref done);
            if (d % 10 == 0 || d == total) progress?.Report(new DownloadProgress("Downloading questions", d, total, Volatile.Read(ref failed)));
        });

        return new DownloadSummary(total - failed, failed, stubs.Count);
    }

    /// One question body, or null if it could not be fetched. Network errors and server errors are retried
    /// a couple of times; "slow down" answers pause every worker and do not count as a failure; other
    /// client errors (a question that no longer exists) give up at once.
    private static async Task<JsonNode?> FetchWithRetry(HttpClient http, JsonObject stub, Throttle throttle, CancellationToken ct)
    {
        var ext = NonEmpty(stub["external_id"]?.ToString());
        var ibn = NonEmpty(stub["ibn"]?.ToString());
        if (ext is null && ibn is null) return null;

        int attempts = 0, throttled = 0;
        while (attempts < 3 && throttled < 8)
        {
            await throttle.WaitAsync(ct);
            try
            {
                using var resp = ext is not null
                    ? await http.PostAsJsonAsync(Api + "/digital/get-question", new { external_id = ext }, ct)
                    : await http.GetAsync(Disclosed + Uri.EscapeDataString(ibn!) + ".json", ct);
                var status = (int)resp.StatusCode;
                if (resp.IsSuccessStatusCode)
                {
                    var node = JsonNode.Parse(await resp.Content.ReadAsStringAsync(ct));
                    if (node is JsonObject or JsonArray) { throttle.Recovered(); return node; }
                }
                else if (status is 429 or 503)
                {
                    throttled++;
                    throttle.SlowDown();
                    continue;
                }
                else if (status is >= 400 and < 500 and not 408)
                {
                    return null;
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception) { /* retried below */ }

            attempts++;
            if (attempts < 3) await Task.Delay(TimeSpan.FromSeconds(RetryBaseSeconds * attempts), ct);
        }
        return null;
    }

    private static string? NonEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s;

    public static void DeleteLocalCopy()
    {
        if (File.Exists(BankPath)) File.Delete(BankPath);
        if (File.Exists(LookupPath)) File.Delete(LookupPath);
    }
}

public static class HistoryStore
{
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = false };
    public static string HistoryPath => Path.Combine(BankStore.DataDir, "history.json");

    public static List<SessionResult> Load()
    {
        try
        {
            if (File.Exists(HistoryPath))
                return JsonSerializer.Deserialize<List<SessionResult>>(File.ReadAllText(HistoryPath), Json) ?? new();
        }
        catch { /* start fresh if the file is damaged */ }
        return new();
    }

    public static void Save(List<SessionResult> all)
    {
        Directory.CreateDirectory(BankStore.DataDir);
        var tmp = HistoryPath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(all, Json));
        File.Move(tmp, HistoryPath, overwrite: true);
    }

    public static HashSet<string> SeenIds(IEnumerable<SessionResult> all) =>
        all.SelectMany(s => s.Modules).SelectMany(m => m.Items).Select(i => i.QuestionId).ToHashSet();

    /// Questions whose most recent attempt was wrong or blank.
    public static HashSet<string> MissedIds(IEnumerable<SessionResult> all)
    {
        var last = new Dictionary<string, bool>();
        foreach (var s in all.OrderBy(s => s.Date))
            foreach (var i in s.Modules.SelectMany(m => m.Items))
                last[i.QuestionId] = i.Correct;
        return last.Where(kv => !kv.Value).Select(kv => kv.Key).ToHashSet();
    }
}
