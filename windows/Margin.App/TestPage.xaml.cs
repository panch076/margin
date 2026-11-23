using System.Windows;
using System.Windows.Controls;
using Margin.Core;

namespace MarginApp;

public partial class TestPage : UserControl
{
    private readonly MainWindow _main;

    public TestPage(MainWindow main)
    {
        _main = main;
        InitializeComponent();
        ExcludeLive.Checked += (_, _) => UpdatePool();
        ExcludeLive.Unchecked += (_, _) => UpdatePool();
        UpdatePool();
    }

    private void UpdatePool()
    {
        var b = _main.Bank;
        var skipLive = ExcludeLive.IsChecked == true;
        int Count(Section s) => b.Questions.Count(q => q.Section == s && (!skipLive || !q.Live));
        PoolText.Text = b.IsEmpty
            ? "Download the question bank from Home before starting a test."
            : $"Drawing from {Count(Section.RW):N0} Reading and Writing and {Count(Section.Math):N0} Math questions.";
    }

    private void Start_Click(object sender, RoutedEventArgs e)
    {
        if (_main.Bank.IsEmpty)
        {
            MessageBox.Show(Window.GetWindow(this), "Download the question bank from Home first.", "Margin");
            return;
        }
        var kind = RwRadio.IsChecked == true ? "rw" : MathRadio.IsChecked == true ? "math" : "full";
        var options = new AssemblyOptions
        {
            ExcludeLive = ExcludeLive.IsChecked == true,
            PreferUnseen = PreferUnseen.IsChecked == true,
            Seen = _main.SeenIds(),
        };
        _main.StartSession(TestSession.Adaptive(_main.Bank, kind, options));
    }
}
