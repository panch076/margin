using System.Globalization;
using System.Text.RegularExpressions;

namespace Margin.Core;

public static partial class Grader
{
    [GeneratedRegex(@"^-?(\d+|\d*\.\d+|\d+\.)$")] private static partial Regex DecimalRx();
    [GeneratedRegex(@"^(-?\d+)/(\d+)$")] private static partial Regex FractionRx();

    public static double? ParseNumber(string? raw)
    {
        if (raw is null) return null;
        var s = raw.Replace(" ", "").Replace("−", "-").Trim();
        if (s.Length == 0) return null;
        var f = FractionRx().Match(s);
        if (f.Success)
        {
            var den = double.Parse(f.Groups[2].Value, CultureInfo.InvariantCulture);
            if (den == 0) return null;
            return double.Parse(f.Groups[1].Value, CultureInfo.InvariantCulture) / den;
        }
        if (DecimalRx().IsMatch(s) && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var v)) return v;
        return null;
    }

    public static bool IsCorrect(Question q, string? answer)
    {
        if (string.IsNullOrWhiteSpace(answer) || q.Correct.Count == 0) return false;
        var a = answer.Trim();
        if (!q.IsSpr) return q.Correct.Any(c => string.Equals(c, a, StringComparison.OrdinalIgnoreCase));

        var v = ParseNumber(a);
        foreach (var c in q.Correct)
        {
            if (string.Equals(c.Trim(), a, StringComparison.OrdinalIgnoreCase)) return true;
            var cv = ParseNumber(c);
            if (v is null || cv is null) continue;
            if (Math.Abs(v.Value - cv.Value) < 1e-9) return true;
            // A long decimal may be entered rounded or truncated, as long as it fills the entry field.
            var dot = a.IndexOf('.');
            if (dot >= 0 && !a.Contains('/') && a.Count(char.IsDigit) >= 4)
            {
                var scale = Math.Pow(10, a.Length - dot - 1);
                var rounded = Math.Round(cv.Value * scale, MidpointRounding.AwayFromZero) / scale;
                var truncated = Math.Truncate(cv.Value * scale) / scale;
                if (Math.Abs(v.Value - rounded) < 1e-9 || Math.Abs(v.Value - truncated) < 1e-9) return true;
            }
        }
        return false;
    }
}
