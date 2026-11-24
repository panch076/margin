using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows;
using Microsoft.Win32;

namespace MarginApp;

/// The Windows-specific half of updating: which version this is, whether it was installed
/// by the setup program, and handing over to a downloaded installer.
public static class UpdateService
{
    public static Version Current => Assembly.GetExecutingAssembly().GetName().Version ?? new Version(1, 0, 0);

    public static string CurrentText => $"{Current.Major}.{Current.Minor}.{Math.Max(Current.Build, 0)}";

    /// True when this exe runs from the folder the installer put it in. The portable exe is not
    /// replaced automatically, because the installer would put the new version somewhere else.
    public static bool IsInstalledCopy
    {
        get
        {
            try
            {
                var exe = Environment.ProcessPath;
                if (exe is null) return false;
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Margin");
                if (key?.GetValue("InstallDir") is not string dir || string.IsNullOrWhiteSpace(dir)) return false;
                var here = Path.GetFullPath(Path.GetDirectoryName(exe) ?? "").TrimEnd('\\');
                return string.Equals(here, Path.GetFullPath(dir).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }
    }

    /// Starts the installer in silent mode and closes the app. The installer waits for the app to exit,
    /// replaces it, and opens the new version.
    public static void RunInstallerAndExit(string installerPath)
    {
        Process.Start(new ProcessStartInfo { FileName = installerPath, Arguments = "/S", UseShellExecute = true });
        Application.Current.Shutdown();
    }

    public static void OpenPage(string url)
    {
        if (!url.StartsWith("https://github.com/", StringComparison.Ordinal)) return;
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { /* no browser available */ }
    }
}
