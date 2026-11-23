using System.Windows;
using System.Windows.Controls;
using Margin.Core;

namespace MarginApp;

public partial class ResultsView : UserControl
{
    private sealed record Entry(ResultItem Item, Question? Q, int Number, string Module);

    private readonly MainWindow _main;
    private readonly SessionResult _r;
    private readonly QuestionWeb _web = new();
    private readonly List<Entry> _entries = new();

    public ResultsView(MainWindow main, SessionResult result)
    {
        _main = main; _r = result;
        InitializeComponent();
        WebHost.Content = _web;
        _web.ShowMessage("Select a question to see the answer and explanation.");

        foreach (var m in result.Modules)
            for (var i = 0; i < m.Items.Count; i++)
                _entries.Add(new Entry(m.Items[i], main.Bank.ById.GetValueOrDefault(m.Items[i].QuestionId), i + 1, m.Title));

        TitleText.Text = result.Title;
        DateText.Text = result.Date.ToString("dddd, MMMM d, yyyy · h:mm tt");
        RetryButton.IsEnabled = _entries.Any(e => !e.Item.Correct && e.Q is not null);
        BuildSummary();
        FillQuestions();
    }

    private static string Mmss(int sec) => $"{sec / 60}:{sec % 60:00}";

    private TextBlock Muted(string text, double size = 12.5)
    {
        var t = new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap };
        t.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");
        return t;
    }

    private void Tile(string value, string label)
    {
        var stack = new StackPanel();
        stack.Children.Add(new TextBlock { Text = value, FontSize = 26, FontWeight = FontWeights.SemiBold });
        stack.Children.Add(Muted(label, 12));
        var card = new Border { Margin = new Thickness(5), Padding = new Thickness(14, 10, 14, 12), Child = stack };
        card.Style = (Style)FindResource("Card");
        card.Padding = new Thickness(14, 10, 14, 12);
        Tiles.Children.Add(card);
    }

    private void BuildSummary()
    {
        var total = _r.QuestionCount;
        if (_r.TotalScore is { } t) { Tile(t.ToString(), "Total"); Tile(_r.RwScore.ToString()!, "Reading & Writing"); Tile(_r.MathScore.ToString()!, "Math"); }
        else if (_r.RwScore is { } rw) { Tile(rw.ToString(), "Reading & Writing"); Tile($"{_r.CorrectCount}/{total}", "Correct"); }
        else if (_r.MathScore is { } ms) { Tile(ms.ToString(), "Math"); Tile($"{_r.CorrectCount}/{total}", "Correct"); }
        else { Tile($"{_r.CorrectCount}/{total}", "Correct"); Tile(total == 0 ? "–" : $"{100.0 * _r.CorrectCount / total:0}%", "Accuracy"); }
        var scored = _r.RwScore.HasValue || _r.MathScore.HasValue;
        EstimateNote.Text = scored ? "Scores are rough estimates on the 200–800 scale, not official results." : "";
        EstimateNote.Visibility = scored ? Visibility.Visible : Visibility.Collapsed;

        foreach (var m in _r.Modules)
        {
            var route = m.Route switch { "higher" => " · higher-difficulty module", "lower" => " · lower-difficulty module", _ => "" };
            var time = m.TimeLimitSec is { } limit ? $"{Mmss(m.UsedSec)} of {Mmss(limit)} used" : $"{Mmss(m.UsedSec)} spent";
            var row = new StackPanel { Margin = new Thickness(0, 0, 0, 8) };
            row.Children.Add(new TextBlock { Text = $"{m.Title}: {m.CorrectCount} of {m.Items.Count} correct", FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            row.Children.Add(Muted(time + route));
            ModuleLines.Children.Add(row);
        }

        foreach (var g in _entries.Where(e => e.Q is not null).GroupBy(e => e.Q!.Domain).OrderBy(g => Catalog.DomainOrder(g.Key)))
        {
            var right = g.Count(e => e.Item.Correct);
            var line = new DockPanel { Margin = new Thickness(0, 0, 0, 7) };
            var count = new TextBlock { Text = $"{right}/{g.Count()}", Width = 46, TextAlignment = TextAlignment.Right };
            DockPanel.SetDock(count, Dock.Right);
            var bar = new ProgressBar { Minimum = 0, Maximum = g.Count(), Value = right, Height = 5, Width = 110, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(bar, Dock.Right);
            line.Children.Add(count);
            line.Children.Add(bar);
            line.Children.Add(new TextBlock { Text = Catalog.DomainName(g.Key), TextTrimming = TextTrimming.CharacterEllipsis });
            DomainLines.Children.Add(line);
        }
    }

    private void FillQuestions()
    {
        Questions.Items.Clear();
        var onlyMissed = OnlyMissed.IsChecked == true;
        string? module = null;
        foreach (var e in _entries)
        {
            if (onlyMissed && e.Item.Correct) continue;
            if (_r.Modules.Count > 1 && e.Module != module)
            {
                module = e.Module;
                Questions.Items.Add(new ListBoxItem { Content = new TextBlock { Text = module, FontWeight = FontWeights.SemiBold, FontSize = 12.5 }, IsEnabled = false, IsHitTestVisible = false });
            }
            var blank = string.IsNullOrWhiteSpace(e.Item.Answer);
            var mark = new TextBlock { Text = e.Item.Correct ? "✓" : blank ? "–" : "✕", Width = 22, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center };
            mark.SetResourceReference(TextBlock.ForegroundProperty,
                e.Item.Correct ? "SystemFillColorSuccessBrush" : blank ? "TextFillColorTertiaryBrush" : "SystemFillColorCriticalBrush");
            var text = new StackPanel();
            text.Children.Add(new TextBlock { Text = $"{e.Number}.  {e.Q?.Skill ?? "Question no longer in the bank"}", TextTrimming = TextTrimming.CharacterEllipsis });
            var detail = e.Q is null ? "" : $"{e.Q.DifficultyName} · " + (blank ? "unanswered" : "you answered " + e.Item.Answer) +
                                              (e.Item.Correct ? "" : $" · correct: {string.Join(" or ", e.Q.Correct.Take(2))}") + $" · {Mmss(e.Item.Seconds)}";
            text.Children.Add(Muted(detail, 12));
            var row = new DockPanel { Margin = new Thickness(2, 3, 2, 3) };
            DockPanel.SetDock(mark, Dock.Left);
            row.Children.Add(mark);
            row.Children.Add(text);
            Questions.Items.Add(new ListBoxItem { Content = row, Tag = e });
        }
    }

    private void OnlyMissed_Changed(object sender, RoutedEventArgs e) => FillQuestions();

    private void Questions_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((Questions.SelectedItem as ListBoxItem)?.Tag is not Entry entry) return;
        if (entry.Q is null) { _web.ShowMessage("This question is no longer in the local bank."); return; }
        _web.Render(QuestionWeb.Payload(entry.Q, entry.Number, entry.Item.Answer, review: true));
    }

    private void Retry_Click(object sender, RoutedEventArgs e)
    {
        var missed = _entries.Where(x => !x.Item.Correct && x.Q is not null).Select(x => x.Q!).DistinctBy(q => q.Id).ToList();
        if (missed.Count == 0) return;
        _main.StartSession(TestSession.Quiz(_main.Bank, missed, timed: false, title: "Missed Questions"));
    }

    private void Done_Click(object sender, RoutedEventArgs e) => _main.CloseOverlay();
}
