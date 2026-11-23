using System.Net;
using System.Text.RegularExpressions;

namespace Margin.Core;

public static partial class Text
{
    [GeneratedRegex("<[^>]+>")] private static partial Regex TagRx();
    [GeneratedRegex(@"\s+")] private static partial Regex SpaceRx();
    [GeneratedRegex(@"<script\b[^>]*>.*?</script\s*>", RegexOptions.IgnoreCase | RegexOptions.Singleline)] private static partial Regex ScriptRx();

    public static string StripTags(string? html)
    {
        if (string.IsNullOrEmpty(html)) return "";
        var s = TagRx().Replace(html, " ");
        s = WebUtility.HtmlDecode(s).Replace(' ', ' ').Replace('−', '-');
        return SpaceRx().Replace(s, " ").Trim();
    }

    public static string DropScripts(string? html) =>
        string.IsNullOrEmpty(html) ? "" : ScriptRx().Replace(html, "");
}
