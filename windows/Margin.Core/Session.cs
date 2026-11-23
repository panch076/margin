namespace Margin.Core;

public enum Phase { Question, Review, Break, Finished }

public sealed class ModuleState
{
    public string Title { get; set; } = "";
    public Section? Section { get; set; }           // null for a mixed custom quiz
    public List<Question> Questions { get; set; } = new();
    public int? TimeLimitSec { get; set; }
    public int RemainingSec { get; set; }
    public int UsedSec { get; set; }
    public string? Route { get; set; }
    public Dictionary<string, string> Answers { get; } = new();
    public HashSet<string> Marked { get; } = new();
    public Dictionary<string, List<string>> Eliminated { get; } = new();
    public Dictionary<string, int> Seconds { get; } = new();

    public bool IsAnswered(Question q) => Answers.TryGetValue(q.Id, out var a) && !string.IsNullOrWhiteSpace(a);
    public int AnsweredCount => Questions.Count(IsAnswered);
}

/// One sitting: a custom quiz (a single module) or an adaptive test (two modules per section,
/// the second one chosen by how the first went).
public sealed class TestSession
{
    private readonly Bank _bank;
    private readonly AssemblyOptions _options;
    private readonly Random _rng;
    private readonly HashSet<string> _used = new();
    private readonly List<(Section Section, int Number)> _plan = new();
    private int _planIndex;

    public string Kind { get; private set; } = "quiz";
    public string Title { get; private set; } = "";
    public List<ModuleState> Modules { get; } = new();
    public Phase Phase { get; private set; } = Phase.Question;
    public int QuestionIndex { get; private set; }
    public int BreakRemaining { get; private set; }

    public ModuleState Module => Modules[^1];
    public Question Current => Module.Questions[Math.Clamp(QuestionIndex, 0, Module.Questions.Count - 1)];
    public bool IsAdaptive => _plan.Count > 0;
    public bool IsLastModule => !IsAdaptive || _planIndex >= _plan.Count - 1;

    private TestSession(Bank bank, AssemblyOptions options, Random? rng)
    {
        _bank = bank; _options = options; _rng = rng ?? new Random();
    }

    public static TestSession Quiz(Bank bank, IReadOnlyList<Question> questions, bool timed, string? title = null)
    {
        var s = new TestSession(bank, new AssemblyOptions(), null) { Kind = "quiz", Title = title ?? "Custom Quiz" };
        var sections = questions.Select(q => q.Section).Distinct().ToList();
        var m = new ModuleState
        {
            Title = s.Title,
            Section = sections.Count == 1 ? sections[0] : null,
            Questions = questions.ToList(),
        };
        if (timed)
        {
            m.TimeLimitSec = Math.Max(60, questions.Sum(q => Assembler.PaceSeconds(q.Section)));
            m.RemainingSec = m.TimeLimitSec.Value;
        }
        s.Modules.Add(m);
        return s;
    }

    /// kind: "full" (both sections), "rw" or "math".
    public static TestSession Adaptive(Bank bank, string kind, AssemblyOptions options, Random? rng = null)
    {
        var s = new TestSession(bank, options, rng) { Kind = kind };
        if (kind is "full" or "rw") { s._plan.Add((Section.RW, 1)); s._plan.Add((Section.RW, 2)); }
        if (kind is "full" or "math") { s._plan.Add((Section.Math, 1)); s._plan.Add((Section.Math, 2)); }
        s.Title = kind switch { "rw" => "Reading and Writing Section", "math" => "Math Section", _ => "Full-Length Adaptive Test" };
        s.StartPlannedModule(null);
        return s;
    }

    private void StartPlannedModule(string? route)
    {
        var (section, number) = _plan[_planIndex];
        var level = number == 1 ? ModuleLevel.First : route == "higher" ? ModuleLevel.Higher : ModuleLevel.Lower;
        var m = new ModuleState
        {
            Title = $"{Catalog.SectionTitle(section)} · Module {number}",
            Section = section,
            Questions = Assembler.Build(_bank, section, level, _options, _used, _rng),
            TimeLimitSec = Assembler.ModuleSeconds(section),
            Route = number == 2 ? route : null,
        };
        m.RemainingSec = m.TimeLimitSec.Value;
        Modules.Add(m);
        QuestionIndex = 0;
        Phase = m.Questions.Count == 0 ? Phase.Finished : Phase.Question;
    }

    // ---- interaction ----

    public void SetAnswer(string? value)
    {
        if (Phase != Phase.Question) return;
        if (string.IsNullOrWhiteSpace(value)) Module.Answers.Remove(Current.Id);
        else Module.Answers[Current.Id] = value.Trim();
    }

    public void SetMarked(bool on)
    {
        if (Phase != Phase.Question) return;
        if (on) Module.Marked.Add(Current.Id); else Module.Marked.Remove(Current.Id);
    }

    public void SetEliminated(IEnumerable<string> letters)
    {
        if (Phase != Phase.Question) return;
        Module.Eliminated[Current.Id] = letters.ToList();
    }

    public void GoTo(int index)
    {
        if (Phase is Phase.Break or Phase.Finished) return;
        QuestionIndex = Math.Clamp(index, 0, Module.Questions.Count - 1);
        Phase = Phase.Question;
    }

    /// Moves forward; after the last question this opens the module's review page.
    public void Next()
    {
        if (Phase != Phase.Question) return;
        if (QuestionIndex >= Module.Questions.Count - 1) Phase = Phase.Review;
        else QuestionIndex++;
    }

    public void Back()
    {
        if (Phase == Phase.Review) { Phase = Phase.Question; QuestionIndex = Module.Questions.Count - 1; }
        else if (Phase == Phase.Question && QuestionIndex > 0) QuestionIndex--;
    }

    public void OpenReview() { if (Phase == Phase.Question) Phase = Phase.Review; }

    /// Call once per second while the session is on screen.
    public void Tick()
    {
        switch (Phase)
        {
            case Phase.Question:
            case Phase.Review:
                var m = Module;
                m.UsedSec++;
                if (Phase == Phase.Question)
                    m.Seconds[Current.Id] = m.Seconds.GetValueOrDefault(Current.Id) + 1;
                if (m.TimeLimitSec.HasValue)
                {
                    m.RemainingSec = Math.Max(0, m.RemainingSec - 1);
                    if (m.RemainingSec == 0) SubmitModule();
                }
                break;
            case Phase.Break:
                BreakRemaining = Math.Max(0, BreakRemaining - 1);
                if (BreakRemaining == 0) EndBreak();
                break;
        }
    }

    public void SubmitModule()
    {
        if (Phase is Phase.Break or Phase.Finished) return;
        if (!IsAdaptive || _planIndex >= _plan.Count - 1) { Phase = Phase.Finished; return; }

        var finished = _plan[_planIndex];
        _planIndex++;
        var next = _plan[_planIndex];
        if (next.Section == finished.Section)
        {
            var m = Module;
            var correct = m.Questions.Count(q => Grader.IsCorrect(q, m.Answers.GetValueOrDefault(q.Id)));
            var share = m.Questions.Count == 0 ? 0 : (double)correct / m.Questions.Count;
            StartPlannedModule(share >= Assembler.RouteThreshold ? "higher" : "lower");
        }
        else
        {
            Phase = Phase.Break;
            BreakRemaining = Assembler.BreakSeconds;
        }
    }

    public void EndBreak()
    {
        if (Phase != Phase.Break) return;
        StartPlannedModule(null);
    }

    // ---- results ----

    public SessionResult BuildResult()
    {
        var r = new SessionResult { Kind = Kind, Title = Title, Date = DateTime.Now };
        foreach (var m in Modules)
        {
            var mr = new ModuleResult
            {
                Title = m.Title,
                Section = m.Section switch { Section.RW => "rw", Section.Math => "math", _ => "mixed" },
                Route = m.Route,
                TimeLimitSec = m.TimeLimitSec,
                UsedSec = m.UsedSec,
            };
            foreach (var q in m.Questions)
            {
                var a = m.Answers.GetValueOrDefault(q.Id);
                mr.Items.Add(new ResultItem
                {
                    QuestionId = q.Id,
                    Answer = a,
                    Correct = Grader.IsCorrect(q, a),
                    Marked = m.Marked.Contains(q.Id),
                    Seconds = m.Seconds.GetValueOrDefault(q.Id),
                });
            }
            r.Modules.Add(mr);
        }
        if (IsAdaptive)
        {
            foreach (var section in new[] { Section.RW, Section.Math })
            {
                var mods = Modules.Where(m => m.Section == section).ToList();
                if (mods.Count < 2) continue;   // a section only gets a score when both modules were taken
                var responses = mods.SelectMany(m => m.Questions.Select(q => (q.Band, Grader.IsCorrect(q, m.Answers.GetValueOrDefault(q.Id)))));
                var score = Scoring.Estimate(responses);
                if (section == Section.RW) r.RwScore = score; else r.MathScore = score;
            }
        }
        return r;
    }
}
