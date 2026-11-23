namespace Margin.Core;

public enum Section { RW, Math }

public sealed class Question
{
    public string Id { get; set; } = "";
    public string? ExternalId { get; set; }
    public string? Ibn { get; set; }
    public Section Section { get; set; }
    public string Domain { get; set; } = "";
    public string DomainName { get; set; } = "";
    public string Skill { get; set; } = "";
    public string Difficulty { get; set; } = "M";   // E, M, H
    public int Band { get; set; } = 4;              // 1 (easiest) to 7 (hardest)
    public bool Live { get; set; }                  // also appears on an official full-length practice test
    public bool IsSpr { get; set; }                 // student-produced response (typed answer)
    public string Stimulus { get; set; } = "";
    public string Stem { get; set; } = "";
    public string Rationale { get; set; } = "";
    public List<string> Choices { get; set; } = new();
    public List<string> Correct { get; set; } = new();
    public bool KeyRecovered { get; set; }

    public bool Gradable => Stem.Length > 0 && Correct.Count > 0 && (IsSpr || Choices.Count >= 2);
    public string DifficultyName => Difficulty switch { "E" => "Easy", "H" => "Hard", _ => "Medium" };
    public string SectionName => Section == Section.RW ? "Reading and Writing" : "Math";
}

public sealed record DomainInfo(string Code, string Name, Section Section);

public static class Catalog
{
    // Listed in the order the domains appear inside a Reading and Writing module.
    public static readonly DomainInfo[] Domains =
    {
        new("CAS", "Craft and Structure", Section.RW),
        new("INI", "Information and Ideas", Section.RW),
        new("SEC", "Standard English Conventions", Section.RW),
        new("EOI", "Expression of Ideas", Section.RW),
        new("H", "Algebra", Section.Math),
        new("P", "Advanced Math", Section.Math),
        new("Q", "Problem-Solving and Data Analysis", Section.Math),
        new("S", "Geometry and Trigonometry", Section.Math),
    };

    public static string DomainName(string code) =>
        Domains.FirstOrDefault(d => d.Code == code)?.Name ?? code;

    public static Section? SectionOf(string code) =>
        Domains.FirstOrDefault(d => d.Code == code)?.Section;

    public static int DomainOrder(string code)
    {
        var i = Array.FindIndex(Domains, d => d.Code == code);
        return i < 0 ? 99 : i;
    }

    public static string SectionTitle(Section s) => s == Section.RW ? "Reading and Writing" : "Math";
}

public sealed class ResultItem
{
    public string QuestionId { get; set; } = "";
    public string? Answer { get; set; }
    public bool Correct { get; set; }
    public bool Marked { get; set; }
    public int Seconds { get; set; }
}

public sealed class ModuleResult
{
    public string Title { get; set; } = "";
    public string Section { get; set; } = "";       // "rw", "math" or "mixed"
    public string? Route { get; set; }              // "higher" / "lower" for an adaptive second module
    public int? TimeLimitSec { get; set; }
    public int UsedSec { get; set; }
    public List<ResultItem> Items { get; set; } = new();
    public int CorrectCount => Items.Count(i => i.Correct);
}

public sealed class SessionResult
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public DateTime Date { get; set; } = DateTime.Now;
    public string Kind { get; set; } = "quiz";      // quiz, full, rw, math
    public string Title { get; set; } = "";
    public List<ModuleResult> Modules { get; set; } = new();
    public int? RwScore { get; set; }
    public int? MathScore { get; set; }
    public int? TotalScore => RwScore.HasValue && MathScore.HasValue ? RwScore + MathScore : null;
    public int CorrectCount => Modules.Sum(m => m.CorrectCount);
    public int QuestionCount => Modules.Sum(m => m.Items.Count);
}
