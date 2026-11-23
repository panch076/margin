using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using Margin.Core;

namespace MarginApp;

public sealed class QuestionRow : INotifyPropertyChanged
{
    private bool _selected;
    public Question Q { get; }
    public string Status { get; }
    public Action<QuestionRow>? Changed;

    public QuestionRow(Question q, string status, bool selected) { Q = q; Status = status; _selected = selected; }

    public string Id => Q.Id;
    public string Domain => Q.DomainName;
    public string Skill => Q.Skill;
    public string Difficulty => Q.DifficultyName;

    public bool IsSelected
    {
        get => _selected;
        set
        {
            if (_selected == value) return;
            _selected = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsSelected)));
            Changed?.Invoke(this);
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}

public partial class BankPage : UserControl
{
    private sealed record Option(string Label, string? Value) { public override string ToString() => Label; }

    private readonly MainWindow _main;
    private readonly QuestionWeb _preview = new();
    private readonly HashSet<string> _selected = new();
    private readonly HashSet<string> _seen, _missed;
    private List<QuestionRow> _rows = new();
    private bool _loading = true;

    public BankPage(MainWindow main)
    {
        _main = main;
        _seen = main.SeenIds();
        _missed = main.MissedIds();
        InitializeComponent();
        PreviewHost.Content = _preview;
        _preview.ShowMessage(main.Bank.IsEmpty ? "Download the question bank from Home to see questions here." : "Select a question to preview it.");

        Fill(SectionBox, new Option("All sections", null), new Option("Reading and Writing", "rw"), new Option("Math", "math"));
        Fill(DifficultyBox, new Option("Any difficulty", null), new Option("Easy", "E"), new Option("Medium", "M"), new Option("Hard", "H"));
        Fill(StatusBox, new Option("Any status", null), new Option("Not seen yet", "new"), new Option("Missed", "missed"), new Option("Answered correctly", "done"));
        FillDomains();
        FillSkills();
        _loading = false;
        ApplyFilter();
    }

    private static void Fill(ComboBox box, params Option[] options)
    {
        box.Items.Clear();
        foreach (var o in options) box.Items.Add(o);
        box.SelectedIndex = 0;
    }

    private static string? Value(ComboBox box) => (box.SelectedItem as Option)?.Value;

    private void FillDomains()
    {
        var section = Value(SectionBox);
        var list = new List<Option> { new("All domains", null) };
        list.AddRange(Catalog.Domains
            .Where(d => section is null || (section == "rw") == (d.Section == Section.RW))
            .Select(d => new Option(d.Name, d.Code)));
        Fill(DomainBox, list.ToArray());
    }

    private void FillSkills()
    {
        var domain = Value(DomainBox);
        var list = new List<Option> { new("All skills", null) };
        if (domain is not null)
            list.AddRange(_main.Bank.Questions.Where(q => q.Domain == domain).Select(q => q.Skill).Where(s => s.Length > 0)
                .Distinct().OrderBy(s => s).Select(s => new Option(s, s)));
        Fill(SkillBox, list.ToArray());
        SkillBox.IsEnabled = domain is not null;
    }

    private void Section_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        _loading = true; FillDomains(); FillSkills(); _loading = false;
        ApplyFilter();
    }

    private void Domain_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        _loading = true; FillSkills(); _loading = false;
        ApplyFilter();
    }

    private void Filter_Changed(object sender, SelectionChangedEventArgs e) { if (!_loading) ApplyFilter(); }
    private void Toggle_Changed(object sender, RoutedEventArgs e) { if (!_loading) ApplyFilter(); }

    private string StatusOf(Question q) => _missed.Contains(q.Id) ? "Missed" : _seen.Contains(q.Id) ? "Correct" : "New";

    private void ApplyFilter()
    {
        var section = Value(SectionBox);
        var domain = Value(DomainBox);
        var skill = Value(SkillBox);
        var diff = Value(DifficultyBox);
        var status = Value(StatusBox);
        var hideLive = HideLive.IsChecked == true;

        var query = _main.Bank.Questions.Where(q =>
            (section is null || (section == "rw") == (q.Section == Section.RW)) &&
            (domain is null || q.Domain == domain) &&
            (skill is null || q.Skill == skill) &&
            (diff is null || q.Difficulty == diff) &&
            (!hideLive || !q.Live) &&
            (status is null
             || (status == "new" && !_seen.Contains(q.Id))
             || (status == "missed" && _missed.Contains(q.Id))
             || (status == "done" && _seen.Contains(q.Id) && !_missed.Contains(q.Id))));

        _rows = query
            .OrderBy(q => q.Section).ThenBy(q => Catalog.DomainOrder(q.Domain)).ThenBy(q => q.Skill).ThenBy(q => q.Band)
            .Select(q => new QuestionRow(q, StatusOf(q), _selected.Contains(q.Id)) { Changed = OnRowChanged })
            .ToList();
        Table.ItemsSource = _rows;
        UpdateCount();
    }

    private void OnRowChanged(QuestionRow row)
    {
        if (row.IsSelected) _selected.Add(row.Id); else _selected.Remove(row.Id);
        UpdateCount();
    }

    private void UpdateCount()
    {
        CountText.Text = $"{_selected.Count:N0} selected · {_rows.Count:N0} shown";
        StartButton.IsEnabled = _selected.Count > 0;
    }

    private void Grid_SelectionChanged(object sender, SelectionChangedEventArgs e) => RenderPreview();
    private void ShowAnswer_Changed(object sender, RoutedEventArgs e) => RenderPreview();

    private void RenderPreview()
    {
        if (Table.SelectedItem is not QuestionRow row) return;
        var q = row.Q;
        PreviewTitle.Text = $"{q.Id} · {q.Skill} · {q.DifficultyName}";
        _preview.Render(QuestionWeb.Payload(q, null, null, review: ShowAnswer.IsChecked == true, readOnly: true, hideBar: ShowAnswer.IsChecked != true));
    }

    private void SelectAll_Click(object sender, RoutedEventArgs e)
    {
        foreach (var r in _rows) { _selected.Add(r.Id); }
        ApplyFilter();
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        _selected.Clear();
        ApplyFilter();
    }

    private void AddRandom_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(RandomCount.Text.Trim(), out var n) || n <= 0) { RandomCount.Text = "10"; n = 10; }
        var pool = _rows.Where(r => !_selected.Contains(r.Id)).ToList();
        Assembler.Shuffle(pool, new Random());
        foreach (var r in pool.Take(n)) _selected.Add(r.Id);
        ApplyFilter();
    }

    private void Start_Click(object sender, RoutedEventArgs e)
    {
        var picked = _selected.Where(_main.Bank.ById.ContainsKey).Select(id => _main.Bank.ById[id])
            .OrderBy(q => q.Section).ThenBy(q => Catalog.DomainOrder(q.Domain)).ThenBy(q => q.Band).ToList();
        if (picked.Count == 0) return;
        _main.StartSession(TestSession.Quiz(_main.Bank, picked, Timed.IsChecked == true));
    }
}
