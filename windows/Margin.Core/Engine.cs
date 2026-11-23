namespace Margin.Core;

public sealed class AssemblyOptions
{
    public bool ExcludeLive { get; set; } = true;
    public bool PreferUnseen { get; set; } = true;
    public ISet<string> Seen { get; set; } = new HashSet<string>();
}

public enum ModuleLevel { First, Higher, Lower }

/// Builds test modules from the bank using the published digital SAT blueprint:
/// Reading and Writing has two 27-question, 32-minute modules; Math has two 22-question, 35-minute modules.
public static class Assembler
{
    public static int ModuleSize(Section s) => s == Section.RW ? 27 : 22;
    public static int ModuleSeconds(Section s) => s == Section.RW ? 32 * 60 : 35 * 60;
    public static int PaceSeconds(Section s) => s == Section.RW ? 71 : 95;
    public const int BreakSeconds = 10 * 60;
    public const double RouteThreshold = 0.60;   // share correct in module 1 that routes to the higher module

    private static readonly (string Domain, int Count)[] RwPlan = { ("CAS", 7), ("INI", 7), ("SEC", 7), ("EOI", 6) };
    private static readonly (string Domain, int Count)[] MathPlan = { ("H", 7), ("P", 7), ("Q", 4), ("S", 4) };

    private static (double E, double M, double H) Mix(ModuleLevel level) => level switch
    {
        ModuleLevel.Higher => (0.10, 0.35, 0.55),
        ModuleLevel.Lower => (0.55, 0.35, 0.10),
        _ => (0.35, 0.40, 0.25),
    };

    public static List<Question> Build(Bank bank, Section section, ModuleLevel level, AssemblyOptions opt, ISet<string> used, Random rng)
    {
        List<Question> best = new();
        var bestGap = double.MaxValue;
        // Math modules carry roughly a quarter typed-answer questions; draw a few candidates and keep the closest.
        var tries = section == Section.Math ? 12 : 1;
        for (var t = 0; t < tries; t++)
        {
            var pick = Draw(bank, section, level, opt, used, rng);
            var gap = section == Section.Math ? Math.Abs(pick.Count(q => q.IsSpr) - 5.5) : 0;
            if (gap < bestGap) { best = pick; bestGap = gap; }
            if (gap <= 0.5) break;
        }
        foreach (var q in best) used.Add(q.Id);
        return section == Section.RW
            ? best.OrderBy(q => Catalog.DomainOrder(q.Domain)).ThenBy(q => q.Skill, StringComparer.Ordinal).ThenBy(q => q.Band).ToList()
            : best.OrderBy(q => q.Band).ThenBy(_ => rng.Next()).ToList();
    }

    private static List<Question> Draw(Bank bank, Section section, ModuleLevel level, AssemblyOptions opt, ISet<string> used, Random rng)
    {
        var plan = section == Section.RW ? RwPlan : MathPlan;
        var (e, m, h) = Mix(level);
        var taken = new HashSet<string>();
        var result = new List<Question>();

        List<Question> Pool(Func<Question, bool> filter, bool allowLive)
        {
            var list = bank.Questions.Where(q => q.Section == section && !used.Contains(q.Id) && !taken.Contains(q.Id)
                                                 && (allowLive || !opt.ExcludeLive || !q.Live) && filter(q)).ToList();
            Shuffle(list, rng);
            if (opt.PreferUnseen) list = list.OrderBy(q => opt.Seen.Contains(q.Id) ? 1 : 0).ToList();   // stable: keeps the shuffle within each group
            return list;
        }
        void Take(IEnumerable<Question> source, int n)
        {
            foreach (var q in source)
            {
                if (n <= 0) break;
                if (taken.Add(q.Id)) { result.Add(q); n--; }
            }
        }

        foreach (var (domain, count) in plan)
        {
            var want = Apportion(count, e, m, h);
            var before = result.Count;
            foreach (var (diff, n) in new[] { ("E", want.E), ("M", want.M), ("H", want.H) })
                Take(Pool(q => q.Domain == domain && q.Difficulty == diff, false), n);
            // Top up from the same domain, then relax the rules, if a difficulty pool ran short.
            var missing = count - (result.Count - before);
            if (missing > 0) { Take(Pool(q => q.Domain == domain, false), missing); missing = count - (result.Count - before); }
            if (missing > 0) Take(Pool(q => q.Domain == domain, true), missing);
        }
        var shortBy = ModuleSize(section) - result.Count;
        if (shortBy > 0) Take(Pool(_ => true, true), shortBy);
        return result;
    }

    private static (int E, int M, int H) Apportion(int n, double e, double m, double h)
    {
        var raw = new[] { n * e, n * m, n * h };
        var floor = raw.Select(x => (int)Math.Floor(x)).ToArray();
        var left = n - floor.Sum();
        foreach (var i in Enumerable.Range(0, 3).OrderByDescending(i => raw[i] - floor[i]))
        {
            if (left-- <= 0) break;
            floor[i]++;
        }
        return (floor[0], floor[1], floor[2]);
    }

    public static void Shuffle<T>(IList<T> list, Random rng)
    {
        for (var i = list.Count - 1; i > 0; i--)
        {
            var j = rng.Next(i + 1);
            (list[i], list[j]) = (list[j], list[i]);
        }
    }
}

public static class Scoring
{
    /// A rough section score on the 200-800 scale. Each question's difficulty comes from its score band,
    /// ability is estimated with a one-parameter logistic model, and the result is mapped to the scale.
    /// The real test uses calibrated item parameters that are not published, so treat this as a ballpark.
    public static int Estimate(IEnumerable<(int Band, bool Correct)> responses)
    {
        var items = responses.ToList();
        if (items.Count == 0) return 200;
        const double priorVar = 2.0 * 2.0;
        double theta = 0;
        for (var iter = 0; iter < 40; iter++)
        {
            double g = -theta / priorVar, hess = -1 / priorVar;
            foreach (var (band, correct) in items)
            {
                var b = (band - 4) * 0.6;
                var p = 1 / (1 + Math.Exp(-(theta - b)));
                g += (correct ? 1 : 0) - p;
                hess -= p * (1 - p);
            }
            var step = g / hess;
            theta -= step;
            if (Math.Abs(step) < 1e-6) break;
        }
        var scaled = 500 + 75 * theta;
        return (int)Math.Clamp(Math.Round(scaled / 10) * 10, 200, 800);
    }
}
