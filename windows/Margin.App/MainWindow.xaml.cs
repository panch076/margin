using System.IO;
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
        var started = false;
        Loaded += async (_, _) =>
        {
            if (started) return;     // Loaded fires again when the Windows theme changes
            started = true;
            History = HistoryStore.Load();
            await ReloadBankAsync();
            Nav.SelectedIndex = 0;
            _ = CheckForUpdateAsync(manual: false);
        };
        Closing += (_, e) =>
        {
            if (!_closingForUpdate && Overlay.Content is SessionView &&
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
        (PageHost.Content as HomePage)?.Detach();
        _page = key;
        PageHost.Content = key switch
        {
            "bank" => new BankPage(this),
            "test" => new TestPage(this),
            "history" => new HistoryPage(this),
            _ => new HomePage(this),
        };
    }

    // ---- updates ----

    public UpdateInfo? Update { get; private set; }
    public bool UpdateBusy { get; private set; }
    public double UpdateFraction { get; private set; }
    public string UpdateStatus { get; private set; } = "";
    public event Action? UpdateChanged;
    private string? _readyInstaller;
    private bool _closingForUpdate;

    /// Asks GitHub whether a newer release exists. Quiet at launch; reports "up to date" when asked for by hand.
    public async Task CheckForUpdateAsync(bool manual)
    {
        if (UpdateBusy) return;
        if (manual) { UpdateStatus = "Checking…"; UpdateChanged?.Invoke(); }
        var found = await Updater.CheckAsync(UpdateService.Current);
        if (found is not null && found.Version != Update?.Version) _readyInstaller = null;
        Update = found;
        UpdateStatus = found is null && manual ? $"Margin {UpdateService.CurrentText} is the latest version." : "";
        UpdateChanged?.Invoke();
    }

    /// Downloads the new installer, then (after asking) closes the app so it can be replaced.
    public async Task InstallUpdateAsync()
    {
        var update = Update;
        if (update is null || UpdateBusy) return;
        if (!UpdateService.IsInstalledCopy || update.InstallerUrl is null)
        {
            UpdateService.OpenPage(update.PageUrl);
            return;
        }
        if (_readyInstaller is null || !File.Exists(_readyInstaller))
        {
            UpdateBusy = true;
            UpdateFraction = 0;
            UpdateStatus = "Downloading the update…";
            UpdateChanged?.Invoke();
            try
            {
                var progress = new Progress<(long Done, long Total)>(p =>
                {
                    UpdateFraction = p.Total > 0 ? Math.Clamp((double)p.Done / p.Total, 0, 1) : 0;
                    UpdateChanged?.Invoke();
                });
                _readyInstaller = await Updater.DownloadInstallerAsync(update, progress);
            }
            catch (Exception e)
            {
                UpdateBusy = false;
                UpdateStatus = "The update could not be downloaded: " + e.Message;
                UpdateChanged?.Invoke();
                return;
            }
            UpdateBusy = false;
        }
        if (Overlay.Content is SessionView)
        {
            UpdateStatus = "The update is downloaded. Finish your test, then choose Update again.";
            UpdateChanged?.Invoke();
            return;
        }
        UpdateStatus = "The update is downloaded and ready to install.";
        UpdateChanged?.Invoke();
        var text = $"Margin will close, install version {update.Version} and reopen. Your question bank and results are kept.";
        if (MessageBox.Show(this, text, "Update Margin", MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
        try
        {
            _closingForUpdate = true;
            UpdateService.RunInstallerAndExit(_readyInstaller);
        }
        catch (Exception e)
        {
            _closingForUpdate = false;
            UpdateStatus = "The installer could not be started: " + e.Message;
            UpdateChanged?.Invoke();
        }
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
