using System.Windows;
using System.Windows.Threading;

namespace MarginApp;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += OnUnhandled;
        base.OnStartup(e);
    }

    private static void OnUnhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show("Something went wrong:\n\n" + e.Exception.Message, "Margin", MessageBoxButton.OK, MessageBoxImage.Warning);
        e.Handled = true;
    }
}
