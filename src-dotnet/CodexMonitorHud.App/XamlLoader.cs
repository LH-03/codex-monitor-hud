using System.Windows;
using System.Windows.Markup;
using System.Xml;

namespace CodexMonitorHud.App;

internal static class XamlLoader
{
    public static Window LoadWindow(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = XmlReader.Create(stream, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null
        });
        return (Window)XamlReader.Load(reader);
    }

    public static T Require<T>(FrameworkElement root, string name) where T : class =>
        root.FindName(name) as T ?? throw new InvalidDataException($"Required XAML control not found: {name}");
}
