using System.Runtime.InteropServices;
using Avalonia.Controls;

namespace CodexMonitorHud.Mac;

internal static class MacWindowInterop
{
    private const string ObjectiveCLibrary = "/usr/lib/libobjc.A.dylib";

    public static void SetMousePassthrough(Window window, bool enabled)
    {
        window.IsHitTestVisible = !enabled;
        if (!OperatingSystem.IsMacOS()) return;
        var handle = window.TryGetPlatformHandle();
        if (handle is null || handle.Handle == IntPtr.Zero ||
            !string.Equals(handle.HandleDescriptor, "NSWindow", StringComparison.Ordinal)) return;
        var selector = sel_registerName("setIgnoresMouseEvents:");
        objc_msgSend(handle.Handle, selector, enabled ? (byte)1 : (byte)0);
    }

    [DllImport(ObjectiveCLibrary, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sel_registerName([MarshalAs(UnmanagedType.LPUTF8Str)] string name);

    [DllImport(ObjectiveCLibrary, CallingConvention = CallingConvention.Cdecl)]
    private static extern void objc_msgSend(IntPtr receiver, IntPtr selector, byte value);
}
