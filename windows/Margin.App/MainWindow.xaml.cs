using System.Windows;
using System.Windows.Controls;
using Margin.Core;

namespace MarginApp;

public partial class MainWindow : Window
{
    public Bank Bank { get; private set; } = new();
    public List<SessionResult> History { get; private set; } = new();
    private string _page = "home";

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            History = HistoryStore.Load();
            await ReloadBankAsync();
            Nav.SelectedIndex = 0;
        };
        Closing += (_, e) =>
        {
            if (Overlay.Content is SessionView &&
                MessageBox.Show(this, "A test is in progress. Close Margin and discard it?", "Margin", MessageBoxButton.OKCancel) != MessageBoxResult.OK)
                e.Cancel = true;
        };
    }

    public async Task ReloadBankAsync()
    {
        BankFootnote.Text = "Loading question bank…";
        try { Bank = await Task.Run(BankStore.Load); }
        catch (Exception e) { Bank = new Bank(); MessageBox.Show(this, "The local question bank could not be read.\n\n" + e.Message, "Margin"); }
        BankFootnote.Text = Bank.IsEmpty ? "No questions downloaded yet" : $"{Bank.Questions.Count:N0} questions stored on this PC";
    }

    private void Nav_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (Nav.SelectedItem is ListBoxItem item && item.Tag is string key) Show(key);
    }

    public void Navigate(string key)
    {
        foreach (var o in Nav.Items)
            if (o is ListBoxItem i && (string)i.Tag == key) { if (Nav.SelectedItem == i) Show(key); else Nav.SelectedItem = i; return; }
    }

    private void Show(string key)
    {
        _page = key;
        PageHost.Content = key switch
        {
            "bank" => new BankPage(this),
            "test" => new TestPage(this),
            "history" => new HistoryPage(this),
            _ => new HomePage(this),
        };
    }

    public HashSet<string> SeenIds() => HistoryStore.SeenIds(History);
    public HashSet<string> MissedIds() => HistoryStore.MissedIds(History);

    public void StartSession(TestSession session)
    {
        if (session.Phase == Phase.Finished || session.Module.Questions.Count == 0)
        {
            MessageBox.Show(this, "There are not enough questions for that yet. Download the question bank first.", "Margin");
            return;
        }
        ShowOverlay(new SessionView(this, session));
    }

    public void FinishSession(SessionResult? result)
    {
        if (result is null) { CloseOverlay(); return; }
        History.Add(result);
        try { HistoryStore.Save(History); } catch (Exception e) { MessageBox.Show(this, "Could not save this result.\n\n" + e.Message, "Margin"); }
        ShowResults(result);
    }

    public void ShowResults(SessionResult result) => ShowOverlay(new ResultsView(this, result));

    public void DeleteResult(SessionResult result)
    {
        History.Remove(result);
        try { HistoryStore.Save(History); } catch { /* keep going */ }
    }

    private void ShowOverlay(UIElement view)
    {
        (Overlay.Content as SessionView)?.Close();
        Overlay.Content = view;
        Overlay.Visibility = Visibility.Visible;
        Shell.Visibility = Visibility.Collapsed;
    }

    public void CloseOverlay()
    {
        (Overlay.Content as SessionView)?.Close();
        Overlay.Content = null;
        Overlay.Visibility = Visibility.Collapsed;
        Shell.Visibility = Visibility.Visible;
        Show(_page);
    }
}
