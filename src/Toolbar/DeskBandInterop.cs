using System;
using System.Drawing;
using System.Runtime.InteropServices;

[ComImport, Guid("00000114-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IChildWindow {
 [PreserveSig] int GetWindow(out IntPtr window);
 [PreserveSig] int ContextSensitiveHelp(int enter);
}
[ComVisible(true), Guid("012DD920-7B26-11D0-8CA9-00A0C92DBFE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDockingWindow {
 [PreserveSig] int GetWindow(out IntPtr window);
 [PreserveSig] int ContextSensitiveHelp(int enter);
 [PreserveSig] int ShowDW(int show);
 [PreserveSig] int CloseDW(uint reserved);
 [PreserveSig] int ResizeBorderDW(IntPtr rect, IntPtr site, int reserved);
}
[ComVisible(true), Guid("79D16DE4-ABEE-4021-8D9D-9169B261D657"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDeskBand2 {
 [PreserveSig] int GetWindow(out IntPtr window);
 [PreserveSig] int ContextSensitiveHelp(int enter);
 [PreserveSig] int ShowDW(int show);
 [PreserveSig] int CloseDW(uint reserved);
 [PreserveSig] int ResizeBorderDW(IntPtr rect, IntPtr site, int reserved);
 [PreserveSig] int GetBandInfo(uint id, uint mode, ref BandInfo info);
 [PreserveSig] int CanRenderComposited(out int can);
 [PreserveSig] int SetCompositionState(int enabled);
 [PreserveSig] int GetCompositionState(out int enabled);
}
[ComVisible(true), Guid("EB0FE172-1A3A-11D0-89B3-00A0C90A90AC"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDeskBand {
 [PreserveSig] int GetWindow(out IntPtr window);
 [PreserveSig] int ContextSensitiveHelp(int enter);
 [PreserveSig] int ShowDW(int show);
 [PreserveSig] int CloseDW(uint reserved);
 [PreserveSig] int ResizeBorderDW(IntPtr rect, IntPtr site, int reserved);
 [PreserveSig] int GetBandInfo(uint id, uint mode, ref BandInfo info);
}
[ComVisible(true), Guid("FC4801A3-2BA9-11CF-A229-00AA003D7352"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ISite {
 [PreserveSig] int SetSite([MarshalAs(UnmanagedType.IUnknown)] object site);
 [PreserveSig] int GetSite(ref Guid iid, out IntPtr site);
}
// The taskbar can query IPersist directly to get the CLSID it saves in its layout.
[ComVisible(true), Guid("0000010C-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPersist {
 [PreserveSig] int GetClassID(out Guid id);
}
[ComVisible(true), Guid("00000109-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPersistStream {
 [PreserveSig] int GetClassID(out Guid id);
 [PreserveSig] int IsDirty();
 [PreserveSig] int Load(IntPtr stream);
 [PreserveSig] int Save(IntPtr stream, int clearDirty);
 [PreserveSig] int GetSizeMax(out long size);
}
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct BandInfo {
 public uint Mask;
 public Point Min, Max, Integral, Actual;
 [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Title;
 public uint ModeFlags, Background;
}
