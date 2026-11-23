using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Margin.Core;

namespace MarginApp;

public partial class SessionView : UserControl
{
    private readonly MainWindow _main;
    private readonly TestSession _s;
    private readonly QuestionWeb _web = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private bool _clockHidden, _closed;
    private int _shownModules;
    private Phase _shownPhase;
    private CalculatorWindow? _calculator;

    public SessionView(MainWindow main, TestSession session)
    {
        _main = main; _s = session;
        InitializeComponent();
        WebHost.Content = _web;
        _web.AnswerChanged += a => { _s.SetAnswer(a); UpdateCounts(); };
        _web.MarkChanged += m => _s.SetMarked(m);
        _web.EliminatedChanged += l => _s.SetEliminated(l);
        _timer.Tick += (_, _) => OnTick();
        Loaded += (_, _) => _timer.Start();
        Refresh();
    }

    /// Stops the clock and closes tool windows. Called when the session ends or its view is replaced.
    public void Close()
    {
        if (_closed) return;
        _closed = true;
        _timer.Stop();
        _calculator?.Close();
    }

    private void OnTick()
    {
        _s.Tick();
        if (_s.Phase != _shownPhase || _s.Modules.Count != _shownModules) Refresh();
        else UpdateClock();
    }

    private static string Mmss(int sec) => $"{sec / 60}:{sec % 60:00}";

    private void UpdateClock()
    {
        if (_s.Phase == Phase.Break) { BreakClock.Text = Mmss(_s.BreakRemaining); return; }
        var m = _s.Module;
        var timed = m.TimeLimitSec.HasValue;
        var value = timed ? m.RemainingSec : m.UsedSec;
        Clock.Text = _clockHidden ? "· · ·" : Mmss(value);
        Clock.SetResourceReference(TextBlock.ForegroundProperty,
            timed && m.RemainingSec <= 300 && !_clockHidden ? "SystemFillColorCriticalBrush" : "TextFillColorPrimaryBrush");
        HideClock.Content = _clockHidden ? "Show" : "Hide";
    }

    private void UpdateCounts()
    {
        var m = _s.Module;
        AnsweredText.Text = $"{m.AnsweredCount} of {m.Questions.Count} answered";
    }

    private void Refresh()
    {
        if (_closed) return;
        _shownPhase = _s.Phase;
        _shownModules = _s.Modules.Count;
        NavPopup.IsOpen = false;

        if (_s.Phase == Phase.Finished)
        {
            Close();
            _main.FinishSession(_s.BuildResult());
            return;
        }

        var m = _s.Module;
        ModuleTitle.Text = m.Title;
        ModuleSub.Text = _s.IsAdaptive ? _s.Title : (m.TimeLimitSec.HasValue ? "Timed quiz" : "Untimed quiz");
        var onBreak = _s.Phase == Phase.Break;
        var onReview = _s.Phase == Phase.Review;
        _web.Visibility = _s.Phase == Phase.Question ? Visibility.Visible : Visibility.Collapsed;
        ReviewPanel.Visibility = onReview ? Visibility.Visible : Visibility.Collapsed;
        BreakPanel.Visibility = onBreak ? Visibility.Visible : Visibility.Collapsed;
        BottomBar.Visibility = onBreak ? Visibility.Collapsed : Visibility.Visible;
        Clock.Visibility = HideClock.Visibility = onBreak ? Visibility.Hidden : Visibility.Visible;

        var math = !onBreak && (onReview ? m.Section == Section.Math : _s.Current.Section == Section.Math);
        CalcButton.Visibility = RefButton.Visibility = math ? Visibility.Visible : Visibility.Collapsed;
        if (!math) _calculator?.Hide();

        if (onBreak) { ModuleTitle.Text = "Break"; UpdateClock(); return; }

        UpdateCounts();
        UpdateClock();
        if (onReview)
        {
            ReviewTitle.Text = m.Title;
            var blank = m.Questions.Count - m.AnsweredCount;
            ReviewHint.Text = (blank == 0 ? "Every question has an answer. " : $"{blank} question{(blank == 1 ? " is" : "s are")} unanswered. ") +
                              "Select any number to go back to it" + (m.TimeLimitSec.HasValue ? " while time remains." : ".");
            FillGrid(ReviewGrid, -1);
            NavButton.Visibility = Visibility.Hidden;
            BackButton.IsEnabled = true;
            NextButton.Content = _s.IsLastModule ? (_s.IsAdaptive ? "Finish test" : "Finish quiz") : "Submit module";
        }
        else
        {
            var q = _s.Current;
            NavButton.Visibility = Visibility.Visible;
            NavLabel.Text = $"Question {_s.QuestionIndex + 1} of {m.Questions.Count}";
            BackButton.IsEnabled = _s.QuestionIndex > 0;
            NextButton.Content = "Next";
            _web.Render(QuestionWeb.Payload(q, _s.QuestionIndex + 1, m.Answers.GetValueOrDefault(q.Id),
                m.Marked.Contains(q.Id), m.Eliminated.GetValueOrDefault(q.Id)));
        }
    }

    /// Number buttons for the navigator popup and the review page.
    private void FillGrid(WrapPanel panel, int current)
    {
        panel.Children.Clear();
        var m = _s.Module;
        for (var i = 0; i < m.Questions.Count; i++)
        {
            var q = m.Questions[i];
            var index = i;
            var label = (i + 1).ToString() + (m.Marked.Contains(q.Id) ? " ⚑" : "");
            var b = new Button
            {
                Content = label, Width = 52, Height = 40, Margin = new Thickness(4), Padding = new Thickness(0),
                FontWeight = i == current ? FontWeights.Bold : FontWeights.Normal,
            };
            if (m.IsAnswered(q)) b.SetResourceReference(StyleProperty, "AccentButtonStyle");
            if (i == current) { b.BorderThickness = new Thickness(2); b.SetResourceReference(BorderBrushProperty, "TextFillColorPrimaryBrush"); }
            b.Click += (_, _) => { _s.GoTo(index); Refresh(); };
            panel.Children.Add(b);
        }
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        PopupTitle.Text = _s.Module.Title;
        FillGrid(PopupGrid, _s.QuestionIndex);
        NavPopup.IsOpen = true;
    }

    private void GoReview_Click(object sender, RoutedEventArgs e) { _s.OpenReview(); Refresh(); }
    private void Back_Click(object sender, RoutedEventArgs e) { _s.Back(); Refresh(); }

    private void Next_Click(object sender, RoutedEventArgs e)
    {
        if (_s.Phase == Phase.Review)
        {
            var m = _s.Module;
            var blank = m.Questions.Count - m.AnsweredCount;
            var text = (blank > 0 ? $"{blank} question{(blank == 1 ? " is" : "s are")} unanswered. " : "") +
                       (_s.IsLastModule ? "Finish and see your results?" : "Submit this module? You will not be able to return to it.");
            if (MessageBox.Show(Window.GetWindow(this), text, m.Title, MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
            _s.SubmitModule();
        }
        else _s.Next();
        Refresh();
    }

    private void Resume_Click(object sender, RoutedEventArgs e) { _s.EndBreak(); Refresh(); }
    private void HideClock_Click(object sender, RoutedEventArgs e) { _clockHidden = !_clockHidden; UpdateClock(); }

    private void Calculator_Click(object sender, RoutedEventArgs e)
    {
        if (_calculator is null)
        {
            var created = new CalculatorWindow { Owner = Window.GetWindow(this) };
            created.Closed += (_, _) => { if (ReferenceEquals(_calculator, created)) _calculator = null; };
            _calculator = created;
        }
        _calculator.Show();
        _calculator.Activate();
    }

    private void Reference_Click(object sender, RoutedEventArgs e) =>
        new ReferenceWindow { Owner = Window.GetWindow(this) }.Show();

    private void Exit_Click(object sender, RoutedEventArgs e)
    {
        var answer = MessageBox.Show(Window.GetWindow(this),
            "Score what you have answered so far and save it to History?\n\nYes: end now and see results.\nNo: leave without saving.\nCancel: keep going.",
            "Exit " + _s.Title, MessageBoxButton.YesNoCancel);
        if (answer == MessageBoxResult.Cancel) return;
        Close();
        _main.FinishSession(answer == MessageBoxResult.Yes ? _s.BuildResult() : null);
    }
}
