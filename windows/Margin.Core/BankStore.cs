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

    /// Downloads every question not yet stored. Safe to cancel and run again.
    public static async Task<DownloadSummary> DownloadAsync(
        IProgress<DownloadProgress>? progress, CancellationToken ct, HttpMessageHandler? handler = null, int parallel = 6)
    {
        Directory.CreateDirectory(DataDir);
        using var http = handler is null ? new HttpClient() : new HttpClient(handler, disposeHandler: false);
        http.Timeout = TimeSpan.FromSeconds(60);
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Margin/1.0");
        http.DefaultRequestHeaders.Accept.ParseAdd("application/json");

        progress?.Report(new DownloadProgress("Reading the question list", 0, 0, 0));
        try
        {
            var lookup = await http.GetStringAsync(Api + "/lookup", ct);
            if (JsonNode.Parse(lookup) is JsonObject) await File.WriteAllTextAsync(LookupPath, lookup, ct);
        }
        catch (Exception e) when (e is not OperationCanceledException) { /* optional */ }

        var stubs = new List<(int Test, JsonObject Stub)>();
        foreach (var (test, domains) in new[] { (1, "INI,CAS,EOI,SEC"), (2, "H,P,Q,S") })
        {
            using var resp = await http.PostAsJsonAsync(Api + "/digital/get-questions",
                new { asmtEventId = 99, test, domain = domains }, ct);
            resp.EnsureSuccessStatusCode();
            var list = JsonNode.Parse(await resp.Content.ReadAsStringAsync(ct)) as JsonArray
                       ?? throw new InvalidDataException("The question list came back in an unexpected format.");
            foreach (var n in list)
                if (n is JsonObject o) stubs.Add((test, o));
        }

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
        var writeLock = new SemaphoreSlim(1, 1);
        await using var writer = new StreamWriter(new FileStream(BankPath, FileMode.Append, FileAccess.Write, FileShare.Read), new UTF8Encoding(false));

        await Parallel.ForEachAsync(todo, new ParallelOptions { MaxDegreeOfParallelism = parallel, CancellationToken = ct }, async (item, token) =>
        {
            JsonNode? detail = null;
            for (var attempt = 0; attempt < 3 && detail is null; attempt++)
            {
                try
                {
                    detail = await FetchDetail(http, item.Stub, token);
                }
                catch (Exception e) when (e is not OperationCanceledException || !token.IsCancellationRequested)
                {
                    await Task.Delay(TimeSpan.FromSeconds(1 + attempt * 2), token);
                }
            }
            if (detail is null) { Interlocked.Increment(ref failed); }
            else
            {
                var line = new JsonObject { ["test"] = item.Test, ["stub"] = item.Stub.DeepClone(), ["detail"] = detail };
                var text = line.ToJsonString();
                await writeLock.WaitAsync(token);
                try { await writer.WriteLineAsync(text); await writer.FlushAsync(token); }
                finally { writeLock.Release(); }
            }
            var d = Interlocked.Increment(ref done);
            if (d % 5 == 0 || d == total) progress?.Report(new DownloadProgress("Downloading questions", d, total, Volatile.Read(ref failed)));
        });

        return new DownloadSummary(total - failed, failed, stubs.Count);
    }

    private static async Task<JsonNode?> FetchDetail(HttpClient http, JsonObject stub, CancellationToken ct)
    {
        var ext = NonEmpty(stub["external_id"]?.ToString());
        if (ext is not null)
        {
            using var resp = await http.PostAsJsonAsync(Api + "/digital/get-question", new { external_id = ext }, ct);
            resp.EnsureSuccessStatusCode();
            return JsonNode.Parse(await resp.Content.ReadAsStringAsync(ct));
        }
        var ibn = NonEmpty(stub["ibn"]?.ToString());
        if (ibn is null) return null;
        var body = await http.GetStringAsync(Disclosed + Uri.EscapeDataString(ibn) + ".json", ct);
        return JsonNode.Parse(body);
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
