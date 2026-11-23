using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Margin.Core;

int pass = 0, fail = 0;
void Check(bool ok, string name) { if (ok) pass++; else { fail++; Console.WriteLine("FAIL: " + name); } }

// ---------- grader ----------
var spr = new Question { IsSpr = true, Stem = "x", Correct = { "2/3", ".6666", ".6667", "0.666", "0.667" } };
Check(Grader.IsCorrect(spr, "2/3"), "fraction");
Check(Grader.IsCorrect(spr, "4/6"), "equivalent fraction");
Check(Grader.IsCorrect(spr, ".667"), "listed form");
Check(Grader.IsCorrect(spr, "0.666"), "truncated");
Check(!Grader.IsCorrect(spr, ".67"), "too short decimal");
Check(!Grader.IsCorrect(spr, "0.7"), "wrong");
Check(!Grader.IsCorrect(spr, ""), "blank");
var spr2 = new Question { IsSpr = true, Stem = "x", Correct = { "9" } };
Check(Grader.IsCorrect(spr2, "9") && Grader.IsCorrect(spr2, "9.0") && Grader.IsCorrect(spr2, "18/2") && !Grader.IsCorrect(spr2, "9.001") && !Grader.IsCorrect(spr2, "-9"), "integer forms");
var neg = new Question { IsSpr = true, Stem = "x", Correct = { "-1/3" } };
Check(Grader.IsCorrect(neg, "-.3333") && Grader.IsCorrect(neg, "-1/3") && !Grader.IsCorrect(neg, "1/3"), "negative");
var mcq = new Question { Stem = "x", Choices = { "a", "b", "c", "d" }, Correct = { "B" } };
Check(Grader.IsCorrect(mcq, "B") && Grader.IsCorrect(mcq, "b") && !Grader.IsCorrect(mcq, "A") && !Grader.IsCorrect(mcq, null), "mcq");

// ---------- normalizer ----------
var live = new HashSet<string> { "ext-1" };
var n1 = Normalizer.FromLine(JsonNode.Parse("""
{"test":1,"stub":{"questionId":"aaa111","external_id":"ext-1","ibn":null,"primary_class_cd":"CAS","primary_class_cd_desc":"Craft and Structure","skill_cd":"WIC","skill_desc":"Words in Context","difficulty":"H","score_band_range_cd":6},
 "detail":{"keys":["k2"],"rationale":"<p>Choice B is the best answer.</p>","stem":"<p>Which?</p>","stimulus":"<p>Text<script>alert(1)</script></p>","type":"mcq","answerOptions":[{"id":"k1","content":"<p>one</p>"},{"id":"k2","content":"<p>two</p>"},{"id":"k3","content":"<p>three</p>"},{"id":"k4","content":"<p>four</p>"}],"correct_answer":["B"]}}
"""), live)!;
Check(n1.Gradable && n1.Section == Section.RW && n1.Correct.SequenceEqual(new[] { "B" }) && n1.Choices.Count == 4 && n1.Live && n1.Band == 6 && !n1.IsSpr && !n1.Stimulus.Contains("script"), "current mcq");
var n2 = Normalizer.FromLine(JsonNode.Parse("""
{"test":1,"stub":{"questionId":"aaa112","external_id":"ext-2","primary_class_cd":"INI","skill_desc":"Inferences","difficulty":"E","score_band_range_cd":2},
 "detail":{"keys":["k3"],"rationale":"r","stem":"s","answerOptions":"[{\"id\":\"k1\",\"content\":\"a\"},{\"id\":\"k2\",\"content\":\"b\"},{\"id\":\"k3\",\"content\":\"c\"},{\"id\":\"k4\",\"content\":\"d\"}]"}}
"""), live)!;
Check(n2.Gradable && n2.Correct.SequenceEqual(new[] { "C" }) && !n2.Live, "key ids + encoded options");
var n3 = Normalizer.FromLine(JsonNode.Parse("""
{"test":2,"stub":{"questionId":"bbb1","external_id":"ext-3","primary_class_cd":"H","skill_desc":"Linear functions","difficulty":"M","score_band_range_cd":4},
 "detail":{"rationale":"<p>The correct answer is 3.5.</p>","stem":"<p>Value?</p>","type":"spr","correct_answer":["3.5","7/2"]}}
"""))!;
Check(n3.Gradable && n3.IsSpr && n3.Section == Section.Math && n3.Correct.Count == 2 && Grader.IsCorrect(n3, "7/2"), "current spr");
var n4 = Normalizer.FromLine(JsonNode.Parse("""
{"test":2,"stub":{"questionId":"ccc1","external_id":null,"ibn":"IBN-9","primary_class_cd":"S","skill_desc":"Circles","difficulty":"H","score_band_range_cd":7},
 "detail":[{"item_id":"IBN-9","prompt":"<p>Old?</p>","body":"<p>fig</p>","answer":{"style":"Multiple Choice","choices":{"b":{"body":"B!"},"a":{"body":"A!"},"d":{"body":"D!"},"c":{"body":"C!"}},"correct_choice":"c","rationale":"<p>Choice C is correct.</p>"}}]}
"""))!;
Check(n4.Gradable && n4.Choices[0] == "A!" && n4.Choices[3] == "D!" && n4.Correct[0] == "C" && n4.Ibn == "IBN-9" && n4.Stimulus.Contains("fig"), "disclosed mcq");
var n5 = Normalizer.FromLine(JsonNode.Parse("""
{"test":2,"stub":{"questionId":"ccc2","ibn":"IBN-10","primary_class_cd":"P","difficulty":"M","score_band_range_cd":3},
 "detail":[{"prompt":"<p>Old spr?</p>","answer":{"style":"SPR","rationale":"<p>The correct answer is <strong>1.5</strong>. Note that 1.5 and 3/2 are examples of ways to enter a correct answer.</p>"}}]}
"""))!;
Check(n5.Gradable && n5.IsSpr && n5.KeyRecovered && n5.Correct.Contains("1.5"), "disclosed spr key recovered: " + string.Join("|", n5.Correct));
var n6 = Normalizer.FromLine(JsonNode.Parse("""
{"test":2,"stub":{"questionId":"ccc3","ibn":"IBN-11","primary_class_cd":"P","difficulty":"M","score_band_range_cd":3},
 "detail":[{"prompt":"<p>Old?</p>","answer":{"style":"Multiple Choice","choices":{"a":{"body":"1"},"b":{"body":"2"},"c":{"body":"3"},"d":{"body":"4"}},"rationale":"<p>Choice D is correct. Choice A is incorrect.</p>"}}]}
"""))!;
Check(n6.Gradable && n6.Correct[0] == "D" && n6.KeyRecovered, "disclosed mcq key recovered");
var n7 = Normalizer.FromLine(JsonNode.Parse("""{"test":1,"stub":{"questionId":"zzz","external_id":"e9","primary_class_cd":"CAS"},"detail":{"unexpected":true}}"""))!;
Check(!n7.Gradable, "unknown shape is unusable, not a crash");
Check(Normalizer.FromLine(JsonNode.Parse("[1,2]")) is null && Normalizer.FromLine(null) is null, "garbage line");

// ---------- synthetic bank ----------
Bank Synthetic(int perCell, int seed)
{
    var rng = new Random(seed);
    var bank = new Bank();
    foreach (var d in Catalog.Domains)
        foreach (var (diff, bands) in new[] { ("E", new[] { 1, 2, 3 }), ("M", new[] { 3, 4, 5 }), ("H", new[] { 5, 6, 7 }) })
            for (var i = 0; i < perCell; i++)
            {
                var isSpr = d.Section == Section.Math && rng.NextDouble() < 0.25;
                var q = new Question
                {
                    Id = $"{d.Code}-{diff}-{i}", ExternalId = $"x-{d.Code}-{diff}-{i}", Section = d.Section, Domain = d.Code, DomainName = d.Name,
                    Skill = "Skill " + (i % 3), Difficulty = diff, Band = bands[rng.Next(3)], IsSpr = isSpr, Stem = "stem", Live = i % 2 == 0,
                };
                if (isSpr) q.Correct.Add("7"); else { q.Choices.AddRange(new[] { "a", "b", "c", "d" }); q.Correct.Add("A"); }
                bank.Questions.Add(q); bank.ById[q.Id] = q;
            }
    return bank;
}
var big = Synthetic(60, 1);

// ---------- assembler ----------
{
    var used = new HashSet<string>();
    var opt = new AssemblyOptions();
    var rw1 = Assembler.Build(big, Section.RW, ModuleLevel.First, opt, used, new Random(2));
    Check(rw1.Count == 27 && rw1.All(q => q.Section == Section.RW && !q.Live), "rw module size, no live");
    Check(rw1.Count(q => q.Domain == "CAS") == 7 && rw1.Count(q => q.Domain == "EOI") == 6, "rw blueprint");
    Check(rw1.Select(q => Catalog.DomainOrder(q.Domain)).SequenceEqual(rw1.Select(q => Catalog.DomainOrder(q.Domain)).OrderBy(x => x)), "rw domain order");
    var hi = Assembler.Build(big, Section.RW, ModuleLevel.Higher, opt, used, new Random(3));
    var lo = Assembler.Build(big, Section.RW, ModuleLevel.Lower, opt, used, new Random(4));
    Check(hi.Count == 27 && lo.Count == 27 && hi.Average(q => q.Band) > rw1.Average(q => q.Band) && lo.Average(q => q.Band) < rw1.Average(q => q.Band), "difficulty by level");
    Check(used.Count == 81, "no repeats across modules");
    var m1 = Assembler.Build(big, Section.Math, ModuleLevel.First, opt, used, new Random(5));
    var sprCount = m1.Count(q => q.IsSpr);
    Check(m1.Count == 22 && sprCount >= 4 && sprCount <= 7, "math module, typed answers = " + sprCount);
    Check(m1.Select(q => q.Band).SequenceEqual(m1.Select(q => q.Band).OrderBy(x => x)), "math ordered by difficulty");
    Console.WriteLine($"  bands  m1 {rw1.Average(q => q.Band):0.00}  higher {hi.Average(q => q.Band):0.00}  lower {lo.Average(q => q.Band):0.00}");
    // prefer unseen
    var seen = big.Questions.Where(q => q.Section == Section.Math && q.Id.EndsWith("1")).Select(q => q.Id).ToHashSet();
    var m2 = Assembler.Build(big, Section.Math, ModuleLevel.First, new AssemblyOptions { Seen = seen }, new HashSet<string>(), new Random(6));
    Check(m2.All(q => !seen.Contains(q.Id)), "prefers unseen");
    // tiny bank still fills what it can without throwing
    var tiny = Synthetic(1, 9);
    var t = Assembler.Build(tiny, Section.RW, ModuleLevel.Higher, new AssemblyOptions(), new HashSet<string>(), new Random(7));
    Check(t.Count == 12 && t.Distinct().Count() == 12, "tiny bank: uses all 12 once, got " + t.Count);
}

// ---------- scoring ----------
{
    int S(IEnumerable<(int, bool)> r) => Scoring.Estimate(r);
    var hard = Enumerable.Range(0, 27).Select(i => 1 + i % 7).Concat(Enumerable.Range(0, 27).Select(i => 4 + i % 4)).ToList();
    var easy = Enumerable.Range(0, 27).Select(i => 1 + i % 7).Concat(Enumerable.Range(0, 27).Select(i => 1 + i % 4)).ToList();
    var perfect = S(hard.Select(b => (b, true)));
    var zero = S(easy.Select(b => (b, false)));
    var miss3 = S(hard.Select((b, i) => (b, i < 51)));
    var miss8 = S(hard.Select((b, i) => (b, i % 7 != 0)));
    var half = S(hard.Take(27).Concat(easy.Skip(27)).Select((b, i) => (b, i % 2 == 0)));
    var third = S(easy.Select((b, i) => (b, i % 3 == 0)));
    Console.WriteLine($"  scores  perfect {perfect}  miss3 {miss3}  miss8 {miss8}  half {half}  third {third}  zero {zero}");
    Check(perfect == 800 && zero == 200, "score endpoints");
    Check(miss3 < 800 && miss3 >= 700 && miss8 < miss3 && half > third && half is > 400 and < 600, "score ordering");
    Check(S(new[] { (4, true) }) is > 500 and < 600, "short tests stay near the middle");
}

// ---------- session ----------
{
    var s = TestSession.Adaptive(big, "full", new AssemblyOptions(), new Random(11));
    Check(s.Modules.Count == 1 && s.Module.Questions.Count == 27 && s.Module.RemainingSec == 1920 && s.Phase == Phase.Question, "full test starts");
    foreach (var q in s.Module.Questions.ToList()) { s.SetAnswer(q.Correct[0]); s.Tick(); s.Next(); }
    Check(s.Phase == Phase.Review, "last Next opens review");
    s.Back(); Check(s.Phase == Phase.Question && s.QuestionIndex == 26, "back from review");
    s.OpenReview(); s.SubmitModule();
    Check(s.Modules.Count == 2 && s.Module.Route == "higher" && s.Phase == Phase.Question && s.QuestionIndex == 0, "routes higher");
    Check(!s.Modules[0].Questions.Select(q => q.Id).Intersect(s.Module.Questions.Select(q => q.Id)).Any(), "module 2 has new questions");
    for (var i = 0; i < 1920; i++) s.Tick();   // run out the clock
    Check(s.Phase == Phase.Break && s.BreakRemaining == 600, "time expiry submits, break starts");
    s.SetAnswer("A"); Check(s.Modules.Count == 2, "input ignored on break");
    s.EndBreak();
    Check(s.Modules.Count == 3 && s.Module.Section == Section.Math && s.Module.RemainingSec == 2100, "math module 1");
    s.SetAnswer("zzz"); s.SubmitModule();
    Check(s.Modules.Count == 4 && s.Module.Route == "lower", "routes lower");
    s.GoTo(5); s.SetMarked(true); s.SetEliminated(new[] { "B" }); s.SubmitModule();
    Check(s.Phase == Phase.Finished, "finishes");
    var r = s.BuildResult();
    Check(r.Modules.Count == 4 && r.RwScore is >= 200 and <= 800 && r.MathScore == 200 && r.TotalScore == r.RwScore + 200, $"result scores rw {r.RwScore} math {r.MathScore}");
    Check(r.Modules[0].CorrectCount == 27 && r.Modules[1].CorrectCount == 0 && r.Modules[3].Items[5].Marked, "result items");

    var quiz = TestSession.Quiz(big, big.Questions.Take(5).ToList(), timed: true);
    Check(quiz.Module.TimeLimitSec == 5 * 71 && !quiz.IsAdaptive, "quiz timing");
    quiz.SubmitModule(); Check(quiz.Phase == Phase.Finished && quiz.BuildResult().RwScore is null, "quiz finishes without a scaled score");
    var untimed = TestSession.Quiz(big, big.Questions.Take(3).ToList(), timed: false);
    for (var i = 0; i < 5000; i++) untimed.Tick();
    Check(untimed.Phase == Phase.Question && untimed.Module.UsedSec == 5000, "untimed never expires");
}

// ---------- downloader against a fake server ----------
{
    var dir = Path.Combine(Path.GetTempPath(), "margin-test-" + Guid.NewGuid().ToString("N"));
    BankStore.DataDir = dir;
    var fake = new FakeBank();
    var first = await BankStore.DownloadAsync(null, CancellationToken.None, fake);
    Check(first.Added == 5 && first.Failed == 1, $"first run: added {first.Added} failed {first.Failed}");   // 7 stubs: 1 duplicate skipped, 1 fails
    var b1 = BankStore.Load();
    Check(b1.Questions.Count == 5 && b1.ById["m2"].IsSpr && b1.ById["r1"].Live && !b1.ById["r2"].Live && b1.ById["old1"].Correct[0] == "C", "load after download");
    fake.Heal = true; var calls = fake.DetailCalls;
    var second = await BankStore.DownloadAsync(null, CancellationToken.None, fake);
    Check(second.Added == 1 && second.Failed == 0 && fake.DetailCalls - calls == 1, "resume fetches only what is missing");
    Check(BankStore.Load().Questions.Count == 6, "bank complete after resume");
    File.AppendAllText(BankStore.BankPath, "{\"test\":1,\"stub\":{\"questionId\":\"trunc");
    Check(BankStore.Load().Questions.Count == 6, "truncated last line is ignored");
    var hist = new List<SessionResult> { new() { Title = "t", Modules = { new ModuleResult { Items = { new ResultItem { QuestionId = "r1", Correct = false }, new ResultItem { QuestionId = "r2", Correct = true } } } } } };
    HistoryStore.Save(hist);
    var back = HistoryStore.Load();
    Check(back.Count == 1 && HistoryStore.MissedIds(back).SetEquals(new[] { "r1" }) && HistoryStore.SeenIds(back).Count == 2, "history round trip");
    Directory.Delete(dir, true);
}

Console.WriteLine($"{pass} passed, {fail} failed");
return fail == 0 ? 0 : 1;

sealed class FakeBank : HttpMessageHandler
{
    public bool Heal;
    public int DetailCalls;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken ct)
    {
        var url = req.RequestUri!.ToString();
        var body = req.Content is null ? "" : await req.Content.ReadAsStringAsync(ct);
        string Json(string s) => s;
        HttpResponseMessage Ok(string s) => new(HttpStatusCode.OK) { Content = new StringContent(Json(s), Encoding.UTF8, "application/json") };
        if (url.EndsWith("/lookup")) return Ok("""{"lookupData":{},"readingLiveItems":["e-r1"],"mathLiveItems":[]}""");
        if (url.EndsWith("/get-questions"))
        {
            return body.Contains("\"test\":1")
                ? Ok("""[{"questionId":"r1","external_id":"e-r1","ibn":null,"primary_class_cd":"CAS","skill_desc":"Words in Context","difficulty":"E","score_band_range_cd":1},{"questionId":"r2","external_id":"e-r2","primary_class_cd":"INI","skill_desc":"Inferences","difficulty":"M","score_band_range_cd":4},{"questionId":"r2dup","external_id":"e-r2","primary_class_cd":"INI","skill_desc":"Inferences","difficulty":"M","score_band_range_cd":4},{"questionId":"r3","external_id":"e-r3","primary_class_cd":"SEC","skill_desc":"Boundaries","difficulty":"H","score_band_range_cd":6}]""")
                : Ok("""[{"questionId":"m1","external_id":"e-m1","primary_class_cd":"H","skill_desc":"Linear functions","difficulty":"E","score_band_range_cd":2},{"questionId":"m2","external_id":"e-m2","primary_class_cd":"P","skill_desc":"Nonlinear functions","difficulty":"H","score_band_range_cd":7},{"questionId":"old1","external_id":"","ibn":"OLD-1","primary_class_cd":"S","skill_desc":"Circles","difficulty":"M","score_band_range_cd":4}]""");
        }
        if (url.EndsWith("/get-question"))
        {
            Interlocked.Increment(ref DetailCalls);
            if (body.Contains("e-r3") && !Heal) return new HttpResponseMessage(HttpStatusCode.InternalServerError);
            if (body.Contains("e-m2")) return Ok("""{"stem":"<p>v?</p>","type":"spr","rationale":"r","correct_answer":["12"]}""");
            return Ok("""{"stem":"<p>q</p>","stimulus":"<p>t</p>","type":"mcq","rationale":"r","answerOptions":[{"id":"1","content":"a"},{"id":"2","content":"b"},{"id":"3","content":"c"},{"id":"4","content":"d"}],"correct_answer":["A"],"keys":["1"]}""");
        }
        if (url.Contains("/disclosed/OLD-1.json"))
        {
            Interlocked.Increment(ref DetailCalls);
            return Ok("""[{"prompt":"<p>o</p>","answer":{"style":"Multiple Choice","choices":{"a":{"body":"1"},"b":{"body":"2"},"c":{"body":"3"},"d":{"body":"4"}},"correct_choice":"c","rationale":"x"}}]""");
        }
        return new HttpResponseMessage(HttpStatusCode.NotFound);
    }
}
