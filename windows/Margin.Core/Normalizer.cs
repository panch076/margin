using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Margin.Core;

/// Turns one stored bank line (list entry + raw question body) into a Question.
/// The question bank serves two shapes: the current one (stem / answerOptions / correct_answer)
/// and an older "disclosed" one (prompt / answer.choices / correct_choice). Both are handled,
/// and anything unexpected degrades to an unusable question instead of an exception.
public static partial class Normalizer
{
    [GeneratedRegex(@"Choice\s*([A-D])\s*is\s*(?:the\s*)?(?:correct|best)", RegexOptions.IgnoreCase)] private static partial Regex McqKeyRx();
    [GeneratedRegex(@"correct answer is\s*(.+)", RegexOptions.IgnoreCase)] private static partial Regex SprKeyRx();
    [GeneratedRegex(@"-?(?:\d+\.\d+|\.\d+|\d+/\d+|\d+)")] private static partial Regex NumberRx();

    public static Question? FromLine(JsonNode? line, ISet<string>? liveIds = null)
    {
        try
        {
            if (line is not JsonObject o) return null;
            var stub = o["stub"] as JsonObject;
            if (stub is null) return null;
            var q = new Question
            {
                Id = Str(stub, "questionId") ?? Str(stub, "external_id") ?? Str(stub, "ibn") ?? "",
                ExternalId = NullIfEmpty(Str(stub, "external_id")),
                Ibn = NullIfEmpty(Str(stub, "ibn")),
                Domain = Str(stub, "primary_class_cd") ?? "",
                Skill = Str(stub, "skill_desc") ?? "",
                Difficulty = (Str(stub, "difficulty") ?? "M").ToUpperInvariant(),
                Band = Int(stub, "score_band_range_cd") ?? 0,
            };
            if (q.Id.Length == 0) return null;
            q.DomainName = Str(stub, "primary_class_cd_desc") ?? Catalog.DomainName(q.Domain);
            var test = Int(o, "test");
            q.Section = Catalog.SectionOf(q.Domain) ?? (test == 2 ? Section.Math : Section.RW);
            if (q.Difficulty is not ("E" or "M" or "H")) q.Difficulty = "M";
            if (q.Band < 1 || q.Band > 7) q.Band = q.Difficulty == "E" ? 2 : q.Difficulty == "H" ? 6 : 4;
            q.Live = q.ExternalId is not null && liveIds is not null && liveIds.Contains(q.ExternalId);

            var detail = o["detail"];
            if (detail is JsonArray arr) detail = arr.Count > 0 ? arr[0] : null;
            if (detail is JsonObject d) Fill(q, d);
            return q;
        }
        catch { return null; }
    }

    private static void Fill(Question q, JsonObject d)
    {
        if (d["answer"] is JsonObject a && (d.ContainsKey("prompt") || a.ContainsKey("choices") || a.ContainsKey("style")))
        {
            // Older disclosed shape
            q.Stem = Text.DropScripts(Str(d, "prompt") ?? Str(d, "stem"));
            q.Stimulus = Text.DropScripts(Str(d, "body") ?? Str(d, "stimulus"));
            q.Rationale = Text.DropScripts(Str(a, "rationale") ?? Str(d, "rationale"));
            if (a["choices"] is JsonObject ch)
            {
                foreach (var kv in ch.OrderBy(k => k.Key, StringComparer.OrdinalIgnoreCase))
                    q.Choices.Add(Text.DropScripts(kv.Value is JsonObject co ? (Str(co, "body") ?? Str(co, "content")) : kv.Value?.ToString()));
            }
            else if (a["choices"] is JsonArray cha)
            {
                foreach (var c in cha)
                    q.Choices.Add(Text.DropScripts(c is JsonObject co ? (Str(co, "body") ?? Str(co, "content")) : c?.ToString()));
            }
            var style = Str(a, "style") ?? "";
            q.IsSpr = q.Choices.Count == 0 || style.Contains("SPR", StringComparison.OrdinalIgnoreCase);
            var key = Str(a, "correct_choice") ?? Str(a, "correct_answer");
            if (!string.IsNullOrWhiteSpace(key)) q.Correct.Add(q.IsSpr ? key.Trim() : key.Trim().ToUpperInvariant());
        }
        else
        {
            // Current shape
            q.Stem = Text.DropScripts(Str(d, "stem") ?? Str(d, "prompt"));
            q.Stimulus = Text.DropScripts(Str(d, "stimulus") ?? Str(d, "body"));
            q.Rationale = Text.DropScripts(Str(d, "rationale"));
            var optsNode = d["answerOptions"];
            if (optsNode is JsonValue ov && ov.TryGetValue<string>(out var encoded) && encoded.TrimStart().StartsWith('['))
            {
                try { optsNode = JsonNode.Parse(encoded); } catch { optsNode = null; }
            }
            var optionIds = new List<string>();
            if (optsNode is JsonArray opts)
            {
                foreach (var op in opts)
                {
                    if (op is JsonObject oo)
                    {
                        q.Choices.Add(Text.DropScripts(Str(oo, "content") ?? Str(oo, "body")));
                        optionIds.Add(Str(oo, "id") ?? "");
                    }
                    else if (op is not null) { q.Choices.Add(Text.DropScripts(op.ToString())); optionIds.Add(""); }
                }
            }
            var type = (Str(d, "type") ?? "").ToLowerInvariant();
            q.IsSpr = type == "spr" || (type != "mcq" && q.Choices.Count == 0);
            var answers = Strings(d["correct_answer"]);
            if (q.IsSpr)
            {
                q.Correct.AddRange(answers.Select(s => s.Trim()).Where(s => s.Length > 0));
            }
            else
            {
                foreach (var s in answers)
                {
                    var t = s.Trim().ToUpperInvariant();
                    if (t.Length == 1 && t[0] >= 'A' && t[0] <= 'F') q.Correct.Add(t);
                }
                if (q.Correct.Count == 0)
                {
                    foreach (var k in Strings(d["keys"]))
                    {
                        var i = optionIds.IndexOf(k);
                        if (i >= 0) q.Correct.Add(((char)('A' + i)).ToString());
                    }
                }
            }
        }

        if (q.Correct.Count == 0) RecoverKey(q);
    }

    /// Some older items ship without a key; the explanation states it in prose.
    private static void RecoverKey(Question q)
    {
        var text = Text.StripTags(q.Rationale);
        if (text.Length == 0) return;
        if (!q.IsSpr)
        {
            var m = McqKeyRx().Match(text);
            if (m.Success) { q.Correct.Add(m.Groups[1].Value.ToUpperInvariant()); q.KeyRecovered = true; }
            return;
        }
        var s = SprKeyRx().Match(text);
        if (!s.Success) return;
        var tail = s.Groups[1].Value;
        // Stop at the end of the sentence: a period that is not part of a decimal.
        var end = Regex.Match(tail, @"\.(?=\s|$)");
        if (end.Success) tail = tail[..end.Index];
        var cut = tail.IndexOf(" Note", StringComparison.OrdinalIgnoreCase);
        if (cut > 0) tail = tail[..cut];
        foreach (Match n in NumberRx().Matches(tail))
            if (!q.Correct.Contains(n.Value)) q.Correct.Add(n.Value);
        if (q.Correct.Count > 0) q.KeyRecovered = true;
    }

    private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s;

    private static string? Str(JsonObject o, string key)
    {
        if (!o.TryGetPropertyValue(key, out var n) || n is null) return null;
        if (n is JsonValue v)
        {
            if (v.TryGetValue<string>(out var s)) return s;
            return v.ToJsonString().Trim('"');
        }
        return null;
    }

    private static int? Int(JsonObject o, string key)
    {
        if (!o.TryGetPropertyValue(key, out var n) || n is not JsonValue v) return null;
        if (v.TryGetValue<int>(out var i)) return i;
        if (v.TryGetValue<double>(out var dbl)) return (int)dbl;
        if (v.TryGetValue<string>(out var s) && int.TryParse(s, out var p)) return p;
        return null;
    }

    private static List<string> Strings(JsonNode? n)
    {
        var list = new List<string>();
        if (n is JsonArray a)
        {
            foreach (var x in a)
                if (x is JsonValue v) list.Add(v.TryGetValue<string>(out var s) ? s : v.ToJsonString().Trim('"'));
        }
        else if (n is JsonValue v)
        {
            var s = v.TryGetValue<string>(out var str) ? str : v.ToJsonString().Trim('"');
            if (s.TrimStart().StartsWith('['))
            {
                try { return Strings(JsonNode.Parse(s)); } catch (JsonException) { }
            }
            if (s.Length > 0) list.Add(s);
        }
        return list;
    }
}
