using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Margin.Core;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace MarginApp;

/// Shows one question. Question text contains math markup, tables and figures, so it is drawn by the
/// system web engine (WebView2) from a single local page; nothing is loaded from the network.
public sealed class QuestionWeb : ContentControl
{
    private readonly WebView2 _web = new();
    private bool _started, _ready;
    private string? _pending;

    public event Action<string?>? AnswerChanged;
    public event Action<bool>? MarkChanged;
    public event Action<List<string>>? EliminatedChanged;

    public QuestionWeb()
    {
        Content = _web;
        Loaded += async (_, _) => await StartAsync();
    }

    public static string UserDataFolder => Path.Combine(BankStore.DataDir, "WebView2");

    public static Task<CoreWebView2Environment> EnvironmentAsync() =>
        CoreWebView2Environment.CreateAsync(null, UserDataFolder);

    private async Task StartAsync()
    {
        if (_started) return;
        _started = true;
        try
        {
            await _web.EnsureCoreWebView2Async(await EnvironmentAsync());
            var s = _web.CoreWebView2.Settings;
            s.AreDefaultContextMenusEnabled = false;
            s.AreDevToolsEnabled = false;
            s.IsStatusBarEnabled = false;
            s.IsZoomControlEnabled = true;
            _web.CoreWebView2.WebMessageReceived += OnMessage;
            _web.CoreWebView2.NewWindowRequested += (_, e) => e.Handled = true;
            _web.NavigateToString(LoadPage());
        }
        catch (Exception e)
        {
            Content = new TextBlock
            {
                Text = "Questions are displayed with Microsoft Edge WebView2, which could not start on this PC.\n\n" +
                       "Install the \"WebView2 Runtime\" from Microsoft and reopen Margin.\n\n" + e.Message,
                TextWrapping = TextWrapping.Wrap, Margin = new Thickness(40), MaxWidth = 520,
                VerticalAlignment = VerticalAlignment.Center,
            };
        }
    }

    private static string LoadPage()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("question.html")
                           ?? throw new InvalidOperationException("The question page is missing from the app.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("type", out var t)) return;
            root.TryGetProperty("value", out var value);
            switch (t.GetString())
            {
                case "ready":
                    _ready = true;
                    if (_pending is not null) { Run(_pending); _pending = null; }
                    break;
                case "answer":
                    AnswerChanged?.Invoke(value.ValueKind == JsonValueKind.String ? value.GetString() : null);
                    break;
                case "mark":
                    MarkChanged?.Invoke(value.ValueKind == JsonValueKind.True);
                    break;
                case "eliminated":
                    var list = new List<string>();
                    if (value.ValueKind == JsonValueKind.Array)
                        foreach (var x in value.EnumerateArray())
                            if (x.ValueKind == JsonValueKind.String) list.Add(x.GetString()!);
                    EliminatedChanged?.Invoke(list);
                    break;
            }
        }
        catch (JsonException) { /* ignore anything that is not ours */ }
    }

    private void Run(string json) => _ = _web.ExecuteScriptAsync("window.Margin.render(" + json + ")");

    public void Render(object payload)
    {
        var json = JsonSerializer.Serialize(payload);
        if (_ready) Run(json); else _pending = json;
    }

    public void ShowMessage(string text) => Render(new { message = text });

    /// The message format understood by question.html.
    public static object Payload(Question q, int? number, string? answer, bool marked = false,
        IEnumerable<string>? eliminated = null, bool review = false, bool readOnly = false, bool hideBar = false)
    {
        object? reviewInfo = review
            ? new { correct = q.Correct, isCorrect = Grader.IsCorrect(q, answer), rationale = q.Rationale }
            : null;
        return new
        {
            number,
            section = q.Section == Section.Math ? "math" : "rw",
            type = q.IsSpr ? "spr" : "mcq",
            stimulus = q.Stimulus,
            stem = q.Stem,
            choices = q.Choices,
            answer,
            marked,
            eliminated = eliminated?.ToList() ?? new List<string>(),
            review = reviewInfo,
            readOnly,
            hideBar,
        };
    }
}
