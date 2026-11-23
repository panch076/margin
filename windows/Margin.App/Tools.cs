using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Wpf;

namespace MarginApp;

/// A floating graphing calculator: the Desmos calculator in the configuration used for the digital SAT.
/// It needs an internet connection; everything else in the app works offline.
public sealed class CalculatorWindow : Window
{
    private const string Url = "https://www.desmos.com/testing/cb-digital-sat/graphing";

    public CalculatorWindow()
    {
        Title = "Graphing Calculator";
        Width = 560; Height = 640; MinWidth = 360; MinHeight = 360;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var web = new WebView2();
        Content = web;
        Loaded += async (_, _) =>
        {
            try
            {
                await web.EnsureCoreWebView2Async(await QuestionWeb.EnvironmentAsync());
                web.CoreWebView2.Navigate(Url);
            }
            catch (Exception e)
            {
                Content = new TextBlock { Text = "The calculator could not be opened.\n\n" + e.Message, Margin = new Thickness(24), TextWrapping = TextWrapping.Wrap };
            }
        };
    }
}

public sealed class ReferenceWindow : Window
{
    public static readonly (string Title, string[] Lines)[] Sheet =
    {
        ("Circle", new[] { "Area  A = πr²", "Circumference  C = 2πr" }),
        ("Rectangle and triangle", new[] { "Rectangle area  A = ℓw", "Triangle area  A = ½bh" }),
        ("Right triangles", new[] { "Pythagorean theorem  c² = a² + b²", "30°-60°-90° sides  x,  x√3,  2x", "45°-45°-90° sides  s,  s,  s√2" }),
        ("Volume", new[] { "Rectangular prism  V = ℓwh", "Cylinder  V = πr²h", "Sphere  V = (4/3)πr³", "Cone  V = (1/3)πr²h", "Pyramid  V = (1/3)ℓwh" }),
        ("Facts", new[] { "A circle has 360 degrees of arc.", "A circle has 2π radians of arc.", "The angles of a triangle add up to 180 degrees." }),
    };

    public ReferenceWindow()
    {
        Title = "Reference";
        Width = 420; Height = 560; ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var stack = new StackPanel { Margin = new Thickness(24) };
        foreach (var (title, lines) in Sheet)
        {
            stack.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 15, Margin = new Thickness(0, 0, 0, 6) });
            foreach (var line in lines)
                stack.Children.Add(new TextBlock { Text = line, FontSize = 14.5, Margin = new Thickness(0, 0, 0, 4), TextWrapping = TextWrapping.Wrap });
            stack.Children.Add(new Border { Height = 14 });
        }
        Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }
}
