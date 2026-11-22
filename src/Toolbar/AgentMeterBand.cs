using System;
using System.Drawing;
using System.Runtime.InteropServices;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

[ComVisible(true), Guid("EA143E8E-217B-4B86-925B-37EA04848915"), ClassInterface(ClassInterfaceType.None)]
public sealed class AgentMeterBand : IDeskBand, IDeskBand2, IDockingWindow, IChildWindow, ISite, IPersist, IPersistStream {
 private const int NoInterface = unchecked((int)0x80004002);
 private const int InvalidWindowHandle = unchecked((int)0x80070006);
 private const int SiteUnavailable = unchecked((int)0x80004005);
 private const int NotImplemented = unchecked((int)0x80004001);
 private const int PersistedStateIsClean = 1;
 private const uint VerticalBandMode = 1;
 private const uint MinimumSizeMask = 1, MaximumSizeMask = 2, IntegralSizeMask = 4, ActualSizeMask = 8;
 private const uint TitleMask = 16, ModeFlagsMask = 32, BackgroundColorMask = 64;
 private const uint VariableHeightModeFlag = 0x0008;
 private const int MinimumHorizontalLength = 70, MinimumHorizontalThickness = 14, PreferredHorizontalThickness = 26;
 private const int VerticalBandLength = 116, VerticalBandThickness = 48;
 private object site;
 private QuotaView view;
 private int composition;
 private bool isVerticalTaskbar;
 [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
 public int SetSite(object value) {
  CloseDW(0);
  site = null;
  if (value == null) return 0;
  try {
   var parentSite = value as IChildWindow;
   if (parentSite == null) return NoInterface;
   IntPtr parentWindow;
   int result = parentSite.GetWindow(out parentWindow);
   if (result < 0) return result;
   if (parentWindow == IntPtr.Zero) return InvalidWindowHandle;
   view = new QuotaView(parentWindow);
   view.SetTaskbarOrientation(isVerticalTaskbar);
   view.CreateControl();
   site = value;
   return 0;
  } catch (Exception ex) {
   CloseDW(0);
   return Marshal.GetHRForException(ex);
  }
 }
 public int GetSite(ref Guid iid, out IntPtr pointer) {
  pointer = IntPtr.Zero;
  if (site == null) return SiteUnavailable;
  IntPtr unknown = Marshal.GetIUnknownForObject(site);
  try { return Marshal.QueryInterface(unknown, ref iid, out pointer); }
  finally { Marshal.Release(unknown); }
 }
 public int GetWindow(out IntPtr window) {
  window = view == null ? IntPtr.Zero : view.Handle;
  return window == IntPtr.Zero ? NotImplemented : 0;
 }
 public int ShowDW(int show) { if (view != null) view.Visible = show != 0; return 0; }
 public int CloseDW(uint reserved) { if (view != null) { view.Dispose(); view = null; } return 0; }
 public int ResizeBorderDW(IntPtr rect, IntPtr site, int reserved) { return NotImplemented; }
 public int ContextSensitiveHelp(int enter) { return NotImplemented; }
 public int GetBandInfo(uint id, uint mode, ref BandInfo info) {
  uint dpi = view == null ? QuotaView.DefaultDpi : GetDpiForWindow(view.Handle);
  if (dpi == 0) dpi = QuotaView.DefaultDpi;
  isVerticalTaskbar = (mode & VerticalBandMode) != 0;
  if (view != null) view.SetTaskbarOrientation(isVerticalTaskbar);
  // The shell measures rebar length along the taskbar and thickness across it.
  var minimumSize = isVerticalTaskbar ? ScaleBandSize(VerticalBandLength, VerticalBandThickness, dpi)
   : ScaleBandSize(MinimumHorizontalLength, MinimumHorizontalThickness, dpi);
  var preferredSize = isVerticalTaskbar ? minimumSize
   : ScaleBandSize(QuotaView.PreferredHorizontalLength, PreferredHorizontalThickness, dpi);
  if ((info.Mask & MinimumSizeMask) != 0) info.Min = minimumSize;
  if ((info.Mask & MaximumSizeMask) != 0) info.Max = new Point(-1, -1);
  if ((info.Mask & IntegralSizeMask) != 0) info.Integral = new Point(1, 1);
  if ((info.Mask & ActualSizeMask) != 0) info.Actual = preferredSize;
  if ((info.Mask & ModeFlagsMask) != 0) info.ModeFlags = isVerticalTaskbar ? 0u : VariableHeightModeFlag;
  info.Mask &= ~(TitleMask | BackgroundColorMask);
  return 0;
 }
 private static Point ScaleBandSize(int length, int thickness, uint dpi) {
  return new Point((int)(length * dpi / QuotaView.DefaultDpi), (int)(thickness * dpi / QuotaView.DefaultDpi));
 }
 public int CanRenderComposited(out int can) { can = 1; return 0; }
 public int SetCompositionState(int enabled) { composition = enabled; return 0; }
 public int GetCompositionState(out int enabled) { enabled = composition; return 0; }
 public int GetClassID(out Guid id) { id = typeof(AgentMeterBand).GUID; return 0; }
 public int IsDirty() { return PersistedStateIsClean; }
 public int Load(IntPtr stream) { return 0; }
 public int Save(IntPtr stream, int clearDirty) { return 0; }
 public int GetSizeMax(out long size) { size = 0; return 0; }
}
