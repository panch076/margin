using System.Windows;
using System.Windows.Controls;
using Margin.Core;

namespace MarginApp;

public partial class HomePage : UserControl
{
    private readonly MainWindow _main;
    private static CancellationTokenSource? _cts;   // a download keeps running if you look at another page

    public HomePage(MainWindow main)
    {
        _main = main;
        InitializeComponent();
        RefreshText();
    }

    private void RefreshText()
    {
        var bank = _main.Bank;
        if (bank.IsEmpty)
        {
            BankSummary.Text = "Nothing is stored yet. Download the question bank once (about 3,800 questions, a few minutes) and everything afterwards works offline.";
            DownloadButton.Content = "Download question bank";
        }
        else
        {
            var live = bank.Questions.Count(q => q.Live);
            BankSummary.Text = $"{bank.Questions.Count:N0} questions on this PC: {bank.Count(Section.RW):N0} Reading and Writing, {bank.Count(Section.Math):N0} Math. " +
                               $"{live:N0} of them also appear on official full-length practice tests." +
                               (bank.Unusable > 0 ? $" {bank.Unusable:N0} could not be read and are left out." : "") +
                               (bank.Updated is { } u ? $" Last updated {u:MMM d, yyyy}." : "");
            DownloadButton.Content = "Check for new questions";
        }
        var busy = _cts is not null;
        DownloadButton.IsEnabled = !busy;
        CancelButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;

        var missed = _main.MissedIds().Count(id => bank.ById.ContainsKey(id));
        MissedText.Text = missed == 0
            ? "Questions you get wrong are collected here so you can try them again."
            : $"{missed:N0} questions were wrong or blank on your last attempt. Retry up to 20 of them as a quiz.";
        MissedButton.IsEnabled = missed > 0;

        var items = _main.History.SelectMany(s => s.Modules).SelectMany(m => m.Items).ToList();
        var tests = _main.History.Count(s => s.Kind != "quiz");
        var best = _main.History.Where(s => s.TotalScore.HasValue).Select(s => s.TotalScore!.Value).DefaultIfEmpty(0).Max();
        StatsText.Text = items.Count == 0
            ? "Nothing yet. Results from quizzes and tests appear here and under History."
            : $"{items.Count:N0} questions answered across {_main.History.Count:N0} sessions, {100.0 * items.Count(i => i.Correct) / items.Count:0}% correct. " +
              $"{tests:N0} practice test{(tests == 1 ? "" : "s")} taken" + (best > 0 ? $", best estimated total {best}." : ".");
    }

    private async void Download_Click(object sender, RoutedEventArgs e)
    {
        if (_cts is not null) return;
        _cts = new CancellationTokenSource();
        RefreshText();
        Progress.Visibility = ProgressText.Visibility = Visibility.Visible;
        Progress.IsIndeterminate = true;
        ProgressText.Text = "Connecting…";
        var progress = new Progress<DownloadProgress>(p =>
        {
            Progress.IsIndeterminate = p.Total == 0;
            Progress.Value = p.Total == 0 ? 0 : (double)p.Done / p.Total;
            ProgressText.Text = p.Total == 0 ? p.Stage + "…" : $"{p.Stage}: {p.Done:N0} of {p.Total:N0}" + (p.Failed > 0 ? $" ({p.Failed:N0} to retry)" : "");
        });
        string message;
        try
        {
            var token = _cts.Token;
            var sum = await Task.Run(() => BankStore.DownloadAsync(progress, token));
            message = sum.Added == 0 && sum.Failed == 0
                ? "Already up to date."
                : $"Added {sum.Added:N0} questions." + (sum.Failed > 0 ? $" {sum.Failed:N0} could not be fetched; run the download again to retry them." : "");
        }
        catch (OperationCanceledException) { message = "Stopped. What was downloaded so far is kept; start again to continue."; }
        catch (Exception ex) { message = "The download did not finish: " + ex.Message + " What was downloaded so far is kept."; }
        _cts.Dispose();
        _cts = null;
        await _main.ReloadBankAsync();
        Progress.Visibility = Visibility.Collapsed;
        ProgressText.Text = message;
        RefreshText();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => _cts?.Cancel();
    private void OpenBank_Click(object sender, RoutedEventArgs e) => _main.Navigate("bank");
    private void OpenTest_Click(object sender, RoutedEventArgs e) => _main.Navigate("test");

    private void Missed_Click(object sender, RoutedEventArgs e)
    {
        var pool = _main.MissedIds().Where(_main.Bank.ById.ContainsKey).Select(id => _main.Bank.ById[id]).ToList();
        Assembler.Shuffle(pool, new Random());
        var pick = pool.Take(20).OrderBy(q => q.Section).ThenBy(q => Catalog.DomainOrder(q.Domain)).ThenBy(q => q.Band).ToList();
        if (pick.Count > 0) _main.StartSession(TestSession.Quiz(_main.Bank, pick, timed: false, title: "Missed Questions"));
    }
}
