using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Margin.Core;

namespace MarginApp;

public partial class HistoryPage : UserControl
{
    private readonly MainWindow _main;

    public HistoryPage(MainWindow main)
    {
        _main = main;
        InitializeComponent();
        Fill();
    }

    private void Fill()
    {
        List.Items.Clear();
        foreach (var r in _main.History.OrderByDescending(r => r.Date))
        {
            var score = r.TotalScore is { } t ? $"{t}  (R&W {r.RwScore} · Math {r.MathScore})"
                : r.RwScore is { } rw ? $"R&W {rw}"
                : r.MathScore is { } m ? $"Math {m}"
                : "";
            var right = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
            right.Children.Add(new TextBlock { Text = $"{r.CorrectCount} / {r.QuestionCount} correct", FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Right });
            if (score.Length > 0) right.Children.Add(Muted("Estimated " + score, HorizontalAlignment.Right));
            var left = new StackPanel();
            left.Children.Add(new TextBlock { Text = r.Title, FontWeight = FontWeights.SemiBold });
            left.Children.Add(Muted(r.Date.ToString("dddd, MMM d, yyyy · h:mm tt"), HorizontalAlignment.Left));
            var row = new DockPanel { Margin = new Thickness(4, 6, 4, 6) };
            DockPanel.SetDock(right, Dock.Right);
            row.Children.Add(right);
            row.Children.Add(left);
            List.Items.Add(new ListBoxItem { Content = row, Tag = r, HorizontalContentAlignment = HorizontalAlignment.Stretch });
        }
        Subtitle.Text = _main.History.Count == 0 ? "Finished quizzes and tests are saved here." : "Select a session to review every question with its explanation.";
    }

    private TextBlock Muted(string text, HorizontalAlignment align)
    {
        var t = new TextBlock { Text = text, FontSize = 12.5, HorizontalAlignment = align };
        t.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");
        return t;
    }

    private SessionResult? Selected => (List.SelectedItem as ListBoxItem)?.Tag as SessionResult;

    private void List_SelectionChanged(object sender, SelectionChangedEventArgs e) =>
        OpenButton.IsEnabled = DeleteButton.IsEnabled = Selected is not null;

    private void Open_Click(object sender, RoutedEventArgs e) { if (Selected is { } r) _main.ShowResults(r); }
    private void List_MouseDoubleClick(object sender, MouseButtonEventArgs e) { if (Selected is { } r) _main.ShowResults(r); }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (Selected is not { } r) return;
        if (MessageBox.Show(Window.GetWindow(this), $"Delete \"{r.Title}\" from {r.Date:MMM d}?", "Margin", MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
        _main.DeleteResult(r);
        Fill();
    }
}
