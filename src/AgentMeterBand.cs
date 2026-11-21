using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]
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
 private const int HorizontalBandHeight = 30, VerticalBandWidth = 116, VerticalBandHeight = 48;
 private object site;
 private QuotaView view;
 private int composition;
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
  bool isVertical = (mode & VerticalBandMode) != 0;
  int width = isVertical ? VerticalBandWidth : QuotaView.PreferredWidth;
  int height = isVertical ? VerticalBandHeight : HorizontalBandHeight;
  var bandSize = new Point((int)(width * dpi / QuotaView.DefaultDpi), (int)(height * dpi / QuotaView.DefaultDpi));
  if ((info.Mask & MinimumSizeMask) != 0) info.Min = bandSize;
  if ((info.Mask & MaximumSizeMask) != 0) info.Max = new Point(-1, -1);
  if ((info.Mask & IntegralSizeMask) != 0) info.Integral = new Point(1, 1);
  if ((info.Mask & ActualSizeMask) != 0) info.Actual = bandSize;
  if ((info.Mask & ModeFlagsMask) != 0) info.ModeFlags = 0;
  info.Mask &= ~(TitleMask | BackgroundColorMask);
  return 0;
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

internal sealed class QuotaView : Control {
 internal const int DefaultDpi = 96;
 internal const int PreferredWidth = 88;
 internal const string SemiboldTypeface = "Segoe UI Semibold";
 private const int SnapshotPollIntervalMilliseconds = 5000;
 private const int QuotaPeriodsPerProvider = 2;
 private const int IncreaseRiseMilliseconds = 2100;
 private const int IncreaseHoldMilliseconds = 300;
 private const int IncreaseDisplayMilliseconds = IncreaseRiseMilliseconds + IncreaseHoldMilliseconds;
 private const int IncreaseFrameIntervalMilliseconds = 25;
 private static readonly TimeSpan MaximumDataAge = TimeSpan.FromMinutes(3);
 private static readonly string[] QuotaKeys = { "claude_c1", "claude_c2", "codex_c1", "codex_c2" };
 internal static readonly Color FiveHourTop = Color.FromArgb(115, 227, 242);
 private static readonly Color FiveHourBottom = Color.FromArgb(69, 134, 237);
 internal static readonly Color WeeklyTop = Color.FromArgb(255, 209, 168);
 private static readonly Color WeeklyBottom = Color.FromArgb(224, 119, 77);
 private static readonly Color FiveHourIncreaseTextColor = Color.FromArgb(26, 88, 190);
 private static readonly Color WeeklyIncreaseTextColor = Color.FromArgb(192, 33, 44);
 private readonly Timer snapshotTimer = new Timer { Interval = SnapshotPollIntervalMilliseconds };
 private readonly Timer increaseDisplayTimer = new Timer { Interval = IncreaseFrameIntervalMilliseconds };
 private readonly Stopwatch increaseDisplayClock = new Stopwatch();
 private readonly int[] usageIncreases = new int[QuotaKeys.Length];
 private readonly FontFamily increaseTypeface = new FontFamily(SemiboldTypeface);
 private bool animateIncreaseRise;
 private QuotaPopup popup;
 private readonly JavaScriptSerializer jsonSerializer = new JavaScriptSerializer();
 private readonly IntPtr parentWindow;
 private readonly string snapshotPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
  @"AgentMeterTaskbar\data.json");
 private Dictionary<string, string> snapshot = new Dictionary<string, string>();
 private DateTimeOffset snapshotWrittenAt;
 private bool lightTheme;
 [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
 [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
 private static extern bool SystemParametersInfo(uint action, uint parameter,
  [MarshalAs(UnmanagedType.Bool)] out bool enabled, uint flags);
 // The taskbar follows the Windows mode, not the app mode.
 private static bool SystemUsesLightTheme() {
  try {
   object value = Microsoft.Win32.Registry.GetValue(
    @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", null);
   return value is int && (int)value == 1;
  }
  catch (IOException) { return false; }
  catch (UnauthorizedAccessException) { return false; }
  catch (System.Security.SecurityException) { return false; }
 }
 internal QuotaView(IntPtr parentWindow) {
  this.parentWindow = parentWindow;
  Text = "AgentMeter Taskbar Quotas";
  SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
  snapshotTimer.Tick += delegate { RefreshSnapshot(); };
  increaseDisplayTimer.Tick += delegate {
   long elapsedMilliseconds = increaseDisplayClock.ElapsedMilliseconds;
   if (elapsedMilliseconds >= IncreaseDisplayMilliseconds) StopIncreaseDisplay();
   else if (!animateIncreaseRise) {
    increaseDisplayTimer.Interval = IncreaseDisplayMilliseconds - (int)elapsedMilliseconds;
   }
   Invalidate();
  };
  RefreshSnapshot();
  snapshotTimer.Start();
 }
 protected override CreateParams CreateParams {
  get {
   var parameters = base.CreateParams;
   parameters.Parent = parentWindow;
   return parameters;
  }
 }
 protected override void OnMouseHover(EventArgs e) {
  base.OnMouseHover(e);
  if (!IsHandleCreated || !Visible || !ClientRectangle.Contains(PointToClient(Cursor.Position))) return;
  if (popup == null) popup = new QuotaPopup();
  UpdatePopup();
  if (!popup.Visible) popup.Show(this);
 }
 protected override void OnMouseLeave(EventArgs e) {
  base.OnMouseLeave(e);
  if (popup != null) popup.Hide();
 }
 protected override void OnVisibleChanged(EventArgs e) {
  base.OnVisibleChanged(e);
  if (!Visible) {
   if (popup != null) popup.Hide();
   StopIncreaseDisplay();
  }
 }
 protected override void OnHandleDestroyed(EventArgs e) {
  StopIncreaseDisplay();
  if (popup != null) {
   popup.Dispose();
   popup = null;
  }
  base.OnHandleDestroyed(e);
 }
 private void UpdatePopup() {
  int dpi = (int)GetDpiForWindow(Handle);
  popup.UpdateContentAndPosition(BuildPopupRows(), lightTheme, dpi == 0 ? DefaultDpi : dpi,
   RectangleToScreen(ClientRectangle), Screen.FromHandle(Handle).WorkingArea);
 }
 private void RefreshSnapshot() {
  const int MaximumSnapshotBytes = 65536;
  try {
   // Keep the file replaceable while the collector publishes its next snapshot.
   using (var stream = File.Open(snapshotPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
   using (var reader = new StreamReader(stream)) {
    if (stream.Length <= MaximumSnapshotBytes) {
     var nextSnapshot = jsonSerializer.Deserialize<Dictionary<string, string>>(reader.ReadToEnd());
     if (nextSnapshot != null) {
      string writtenAtText;
      DateTimeOffset writtenAt;
      if (!nextSnapshot.TryGetValue("updated_at", out writtenAtText)) {
       writtenAt = File.GetLastWriteTimeUtc(snapshotPath);
      } else if (!DateTimeOffset.TryParseExact(writtenAtText, "o", CultureInfo.InvariantCulture,
                 DateTimeStyles.None, out writtenAt)) {
       writtenAt = DateTimeOffset.MinValue;
      }
      ApplySnapshot(nextSnapshot, writtenAt, DateTimeOffset.UtcNow);
     }
    }
   }
  }
  catch (FileNotFoundException) { snapshotWrittenAt = DateTimeOffset.MinValue; }
  catch (DirectoryNotFoundException) { snapshotWrittenAt = DateTimeOffset.MinValue; }
  catch (IOException) { }
  catch (UnauthorizedAccessException) { }
  catch (ArgumentException) { }
  catch (InvalidOperationException) { }
  lightTheme = SystemUsesLightTheme();
  if (popup != null && popup.Visible) UpdatePopup();
  Invalidate();
 }
 private void ApplySnapshot(Dictionary<string, string> nextSnapshot, DateTimeOffset writtenAt, DateTimeOffset now) {
  bool canCompareUsage = IsHandleCreated && Visible && writtenAt > snapshotWrittenAt && HasFreshSnapshot(now);
  var previousSnapshot = snapshot;
  snapshot = nextSnapshot;
  snapshotWrittenAt = writtenAt;
  if (!canCompareUsage || !HasFreshSnapshot(now)) return;

  bool hasIncrease = false;
  for (int index = 0; index < usageIncreases.Length; index++) {
   usageIncreases[index] = GetUsageIncrease(previousSnapshot, nextSnapshot, index, now);
   hasIncrease |= usageIncreases[index] > 0;
  }
  if (!hasIncrease) {
   StopIncreaseDisplay();
   return;
  }

  const uint SpiGetClientAreaAnimation = 0x1042;
  bool windowsAnimationEnabled;
  animateIncreaseRise = SystemParametersInfo(SpiGetClientAreaAnimation, 0, out windowsAnimationEnabled, 0) &&
   windowsAnimationEnabled;
  increaseDisplayClock.Restart();
  increaseDisplayTimer.Interval = animateIncreaseRise ? IncreaseFrameIntervalMilliseconds : IncreaseDisplayMilliseconds;
  increaseDisplayTimer.Start();
 }
 private static int GetUsageIncrease(Dictionary<string, string> previousSnapshot, Dictionary<string, string> nextSnapshot,
  int index, DateTimeOffset now) {
  string quotaKey = QuotaKeys[index];
  DateTimeOffset? resetAt = ReadResetTime(nextSnapshot, quotaKey);
  int previousPercent, nextPercent;
  if (resetAt != ReadResetTime(previousSnapshot, quotaKey) ||
      !TryGetUsagePercent(previousSnapshot, index, now, resetAt, out previousPercent) ||
      !TryGetUsagePercent(nextSnapshot, index, now, resetAt, out nextPercent)) return 0;
  return Math.Max(0, nextPercent - previousPercent);
 }
 private void StopIncreaseDisplay() {
  increaseDisplayTimer.Stop();
  increaseDisplayClock.Reset();
 }
 private string SnapshotValue(string key) {
  string value;
  return snapshot.TryGetValue(key, out value) ? value : "";
 }
 private bool HasFreshSnapshot(DateTimeOffset now) {
  TimeSpan age = now - snapshotWrittenAt;
  return age >= TimeSpan.Zero && age <= MaximumDataAge;
 }
 private static DateTimeOffset? ReadResetTime(Dictionary<string, string> snapshot, string quotaKey) {
  string resetAtText;
  DateTimeOffset resetAt;
  if (snapshot.TryGetValue(quotaKey + "_reset_at", out resetAtText) &&
      DateTimeOffset.TryParseExact(resetAtText, "o", CultureInfo.InvariantCulture, DateTimeStyles.None, out resetAt)) return resetAt;
  return null;
 }
 private static bool TryGetUsagePercent(Dictionary<string, string> snapshot, int index, DateTimeOffset now,
  DateTimeOffset? resetAt, out int percent) {
  string status, percentText;
  string statusKey = index < QuotaPeriodsPerProvider ? "claude_status" : "codex_status";
  percent = 0;
  if (resetAt <= now ||
      !snapshot.TryGetValue(statusKey, out status) || status != "ok" ||
      !snapshot.TryGetValue(QuotaKeys[index] + "_pct", out percentText) || !int.TryParse(percentText, out percent)) return false;
  percent = Math.Min(100, Math.Max(0, percent));
  return true;
 }
 private Rectangle GetTrackBounds(int index, int dpi) {
  int availableWidth = Math.Min(ClientSize.Width, PreferredWidth * dpi / DefaultDpi);
  int trackCount = QuotaKeys.Length;
  if (availableWidth < trackCount) return Rectangle.Empty;
  const int ExtraGapUnitsBetweenProviders = 2;
  int gapsBetweenTracks = trackCount - 1;
  int totalGapUnits = gapsBetweenTracks + ExtraGapUnitsBetweenProviders;
  int trackGap = Math.Min(2 * dpi / DefaultDpi, (availableWidth - trackCount) / totalGapUnits);
  int extraProviderGap = ExtraGapUnitsBetweenProviders * trackGap;
  int horizontalPadding = 12 * dpi / DefaultDpi;
  int trackWidth = Math.Max(1, (availableWidth - horizontalPadding - extraProviderGap - gapsBetweenTracks * trackGap) / trackCount);
  int totalTrackWidth = trackCount * trackWidth + gapsBetweenTracks * trackGap + extraProviderGap;
  int firstTrackLeft = (ClientSize.Width - totalTrackWidth) / 2;
  int trackLeft = firstTrackLeft + index * (trackWidth + trackGap) + (index >= QuotaPeriodsPerProvider ? extraProviderGap : 0);
  int verticalPadding = 3 * dpi / DefaultDpi;
  return new Rectangle(trackLeft, verticalPadding, trackWidth, Math.Max(0, ClientSize.Height - 2 * verticalPadding));
 }
 protected override void OnPaint(PaintEventArgs e) {
  e.Graphics.Clear(lightTheme ? Color.FromArgb(238, 238, 238) : Color.FromArgb(25, 25, 31));
  int dpi = IsHandleCreated ? (int)GetDpiForWindow(Handle) : DefaultDpi;
  if (dpi == 0) dpi = DefaultDpi;
  DateTimeOffset now = DateTimeOffset.UtcNow;
  bool hasFreshSnapshot = HasFreshSnapshot(now);
  for (int index = 0; index < QuotaKeys.Length; index++) {
   Rectangle track = GetTrackBounds(index, dpi);
   if (track.Width == 0 || track.Height == 0) continue;
   e.Graphics.FillRectangle(lightTheme ? Brushes.Silver : Brushes.DimGray, track);
   if (!hasFreshSnapshot) continue;
   DateTimeOffset? resetAt = ReadResetTime(snapshot, QuotaKeys[index]);
   int percent;
   if (!TryGetUsagePercent(snapshot, index, now, resetAt, out percent) || percent <= 0) continue;
   int fillHeight = Math.Max(1, percent * track.Height / 100);
   var fill = new Rectangle(track.X, track.Bottom - fillHeight, track.Width, fillHeight);
   bool weekly = index % QuotaPeriodsPerProvider == 1;
   using (var brush = new LinearGradientBrush(fill, weekly ? WeeklyTop : FiveHourTop,
    weekly ? WeeklyBottom : FiveHourBottom, LinearGradientMode.Vertical)) {
    e.Graphics.FillRectangle(brush, fill);
   }
   const int WarningPercent = 60, CriticalPercent = 85;
   if (percent >= WarningPercent && fillHeight > 1) {
    e.Graphics.FillRectangle(percent >= CriticalPercent ? Brushes.Tomato : Brushes.Gold, fill.X, fill.Y, fill.Width, 1);
   }
  }
  if (hasFreshSnapshot && increaseDisplayClock.IsRunning) {
   DrawUsageIncreases(e.Graphics, increaseDisplayClock.Elapsed.TotalMilliseconds, dpi);
  }
 }
 private void DrawUsageIncreases(Graphics graphics, double elapsedMilliseconds, int dpi) {
  if (elapsedMilliseconds >= IncreaseDisplayMilliseconds) return;
  float dpiScale = (float)dpi / DefaultDpi;
  const int MinimumBlockSize = 8;
  if (ClientSize.Height <= MinimumBlockSize * dpiScale) return;

  float riseProgress = (float)Math.Min(1, elapsedMilliseconds / IncreaseRiseMilliseconds);
  float easedRiseProgress = riseProgress * riseProgress * (3 - 2 * riseProgress);
  float verticalPosition = animateIncreaseRise ? 1 - easedRiseProgress : 0.5f;
  float blockHeight = Math.Min(23 * dpiScale, ClientSize.Height * 0.8f);
  float blockTop = (float)Math.Round((ClientSize.Height - blockHeight) * verticalPosition);
  SmoothingMode previousSmoothing = graphics.SmoothingMode;
  graphics.SmoothingMode = SmoothingMode.AntiAlias;
  for (int fiveHourIndex = 0; fiveHourIndex < usageIncreases.Length; fiveHourIndex += QuotaPeriodsPerProvider) {
   int weeklyIndex = fiveHourIndex + 1;
   bool showWeeklyIncrease = usageIncreases[weeklyIndex] > 0;
   int displayedIncrease = usageIncreases[showWeeklyIncrease ? weeklyIndex : fiveHourIndex];
   if (displayedIncrease == 0) continue;
   Rectangle providerTracks = Rectangle.Union(GetTrackBounds(fiveHourIndex, dpi), GetTrackBounds(weeklyIndex, dpi));
   if (providerTracks.Width <= MinimumBlockSize * dpiScale) continue;
   var block = new RectangleF(providerTracks.X, blockTop, providerTracks.Width, blockHeight);
   Color numberColor = showWeeklyIncrease ? WeeklyIncreaseTextColor : FiveHourIncreaseTextColor;
   DrawIncreaseCard(graphics, displayedIncrease, block, numberColor, dpiScale);
  }
  graphics.SmoothingMode = previousSmoothing;
 }
 private void DrawIncreaseCard(Graphics graphics, int increase, RectangleF block, Color numberColor, float dpiScale) {
  RectangleF borderBounds = RectangleF.Inflate(block, -dpiScale / 2, -dpiScale / 2);
  using (var outline = PopupOutline.CreateRoundedRectangle(borderBounds, 4 * dpiScale))
  using (var borderPen = new Pen(Color.FromArgb(60, numberColor), dpiScale)) {
   graphics.FillPath(Brushes.White, outline);
   graphics.DrawPath(borderPen, outline);
  }

  using (var numberPath = new GraphicsPath())
  using (var format = StringFormat.GenericTypographic)
  using (var transform = new Matrix())
  using (var numberBrush = new SolidBrush(numberColor)) {
   numberPath.AddString(increase.ToString(CultureInfo.InvariantCulture), increaseTypeface, (int)FontStyle.Regular,
    28 * dpiScale, PointF.Empty, format);
   RectangleF glyphBounds = numberPath.GetBounds();
   const int HorizontalPadding = 6, VerticalPadding = 7;
   float contentWidth = block.Width - HorizontalPadding * dpiScale;
   float numberMaxHeight = Math.Max(1, block.Height - VerticalPadding * dpiScale);
   float numberScale = Math.Min(contentWidth / glyphBounds.Width, numberMaxHeight / glyphBounds.Height);
   float numberLeft = block.X + (block.Width - glyphBounds.Width * numberScale) / 2;
   float numberTop = block.Y + (block.Height - glyphBounds.Height * numberScale) / 2;
   transform.Translate(numberLeft, numberTop);
   transform.Scale(numberScale, numberScale);
   transform.Translate(-glyphBounds.X, -glyphBounds.Y);
   numberPath.Transform(transform);
   graphics.FillPath(numberBrush, numberPath);
  }
 }
 private List<QuotaPopup.Row> BuildPopupRows() {
  DateTimeOffset now = DateTimeOffset.UtcNow;
  var rows = new List<QuotaPopup.Row>();
  if (!HasFreshSnapshot(now)) {
   rows.Add(new QuotaPopup.Row(QuotaPopup.RowKind.Notice,
    snapshotWrittenAt == DateTimeOffset.MinValue ? "Waiting for quota data." : "Quota data is stale."));
  } else {
   AddProviderRows(rows, "Claude Code", "claude", now);
   AddProviderRows(rows, "Codex", "codex", now);
  }
  return rows;
 }
 private void AddProviderRows(List<QuotaPopup.Row> rows, string title, string provider, DateTimeOffset now) {
  rows.Add(new QuotaPopup.Row(QuotaPopup.RowKind.Heading, title));
  if (SnapshotValue(provider + "_status") != "ok") {
   string message = SnapshotValue(provider + "_msg");
   rows.Add(new QuotaPopup.Row(QuotaPopup.RowKind.Notice,
    String.IsNullOrWhiteSpace(message) ? "Quota data unavailable." : message));
   return;
  }
  rows.Add(CreatePeriodRow(provider + "_c1", "5h", QuotaPopup.RowKind.FiveHour, now));
  rows.Add(CreatePeriodRow(provider + "_c2", "7d", QuotaPopup.RowKind.Weekly, now));
 }
 private QuotaPopup.Row CreatePeriodRow(string quotaKey, string defaultLabel, QuotaPopup.RowKind kind, DateTimeOffset now) {
  string label = SnapshotValue(quotaKey + "_label");
  if (String.IsNullOrWhiteSpace(label)) label = defaultLabel;
  DateTimeOffset? resetAt = ReadResetTime(snapshot, quotaKey);
  if (resetAt <= now) return new QuotaPopup.Row(kind, label, note: "Waiting for fresh usage data.");
  int percent;
  if (!int.TryParse(SnapshotValue(quotaKey + "_pct"), out percent)) {
   return new QuotaPopup.Row(kind, label, note: "Quota data unavailable.");
  }
  string usage = Math.Min(100, Math.Max(0, percent)) + "%";
  if (!resetAt.HasValue) {
   return new QuotaPopup.Row(kind, label, usage, note: "Reset time unavailable.");
  }
  return new QuotaPopup.Row(kind, label, usage, FormatTimeUntilReset(resetAt.Value - now));
 }
 private static string FormatTimeUntilReset(TimeSpan remaining) {
  if (remaining.Days > 0) return remaining.Days + "d " + remaining.Hours + "h";
  if (remaining.Hours > 0) return remaining.Hours + "h " + remaining.Minutes + "m";
  if (remaining.Minutes > 0) return remaining.Minutes + "m";
  return "<1m";
 }
 protected override void Dispose(bool disposing) {
  if (disposing) {
   snapshotTimer.Dispose();
   StopIncreaseDisplay();
  }
  base.Dispose(disposing);
  if (disposing) {
   increaseDisplayTimer.Dispose();
   increaseTypeface.Dispose();
  }
 }
}

internal static class PopupOutline {
 internal static GraphicsPath CreateRoundedRectangle(RectangleF bounds, float radius) {
  float diameter = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
  var outline = new GraphicsPath();
  if (diameter <= 0) {
   outline.AddRectangle(bounds);
   return outline;
  }
  outline.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
  outline.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
  outline.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
  outline.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
  outline.CloseFigure();
  return outline;
 }
}

internal sealed class QuotaPopup : Form {
 private const int PreferredUsageFontPixels = 23;
 private const int PreferredHeadingFontPixels = 15;
 private const int PreferredDetailFontPixels = 13;
 private const int PreferredContentWidth = 252;
 private const int PopupCornerRadius = 12;
 private const int GapFromTaskbar = 8;
 private const TextFormatFlags LineFlags = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix |
  TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter;
 private const TextFormatFlags NoteFlags = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.WordBreak;
 private static readonly string VersionLabel = GetVersionLabel();

 internal enum RowKind { Heading, FiveHour, Weekly, Notice }

 internal struct Row {
  internal readonly RowKind Kind;
  internal readonly string Label, Percent, Remaining, Note;
  internal Row(RowKind kind, string label, string percent = null, string remaining = null, string note = null) {
   Kind = kind;
   Label = label;
   Percent = percent;
   Remaining = remaining;
   Note = note;
  }
 }

 private List<Row> rows;
 private Font usageFont, headingFont, detailFont;
 private int dpi, usageFontPixels, padding, minimumColumnGap;
 private int periodColumnWidth, percentColumnWidth, countdownColumnWidth;
 private Size roundedWindowSize;
 private int roundedWindowRadius;
 private Color textColor, detailColor, borderColor, separatorColor, fiveHourTextColor, weeklyTextColor;

 internal QuotaPopup() {
  Text = "AgentMeter Quotas";
  FormBorderStyle = FormBorderStyle.None;
  ShowInTaskbar = false;
  StartPosition = FormStartPosition.Manual;
  AutoScaleMode = AutoScaleMode.None;
  SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
 }

 private static string GetVersionLabel() {
  var version = (AssemblyInformationalVersionAttribute)Attribute.GetCustomAttribute(
   typeof(QuotaPopup).Assembly, typeof(AssemblyInformationalVersionAttribute));
  return version == null ? "Development build" : "v" + version.InformationalVersion;
 }

 protected override bool ShowWithoutActivation { get { return true; } }

 protected override CreateParams CreateParams {
  get {
   const int WsExToolWindow = 0x00000080, WsExNoActivate = 0x08000000;
   var parameters = base.CreateParams;
   parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
   return parameters;
  }
 }

 internal void UpdateContentAndPosition(List<Row> content, bool lightTheme, int ownerDpi, Rectangle bandBounds, Rectangle workArea) {
  rows = content;
  dpi = ownerDpi;
  padding = Math.Min(Scale(16), Math.Min(workArea.Width, workArea.Height) / 8);
  minimumColumnGap = Scale(12);
  bool highContrast = SystemInformation.HighContrast;
  BackColor = highContrast ? SystemColors.Window : lightTheme ? Color.FromArgb(251, 252, 255) : Color.FromArgb(28, 30, 37);
  textColor = highContrast ? SystemColors.WindowText : lightTheme ? Color.FromArgb(25, 33, 48) : Color.FromArgb(244, 247, 253);
  detailColor = highContrast ? textColor : lightTheme ? Color.FromArgb(77, 89, 110) : Color.FromArgb(182, 192, 210);
  borderColor = highContrast ? textColor : lightTheme ? Color.FromArgb(208, 217, 232) : Color.FromArgb(76, 84, 102);
  separatorColor = highContrast ? textColor : lightTheme ? Color.FromArgb(224, 230, 241) : Color.FromArgb(61, 68, 84);
  fiveHourTextColor = highContrast ? textColor : lightTheme ? Color.FromArgb(27, 82, 173) : QuotaView.FiveHourTop;
  weeklyTextColor = highContrast ? textColor : lightTheme ? Color.FromArgb(158, 60, 26) : QuotaView.WeeklyTop;

  int availableContentWidth = Math.Max(1, workArea.Width - 2 * padding);
  SetFonts(Math.Min(Scale(PreferredUsageFontPixels), Math.Max(1, availableContentWidth / 8)));
  int contentWidth = MeasureContentWidthAndColumns();
  if (contentWidth > availableContentWidth) {
   SetFonts(Math.Max(1, usageFontPixels * availableContentWidth / contentWidth));
   contentWidth = MeasureContentWidthAndColumns();
  }
  contentWidth = Math.Min(availableContentWidth, Math.Max(Scale(PreferredContentWidth), contentWidth));
  int popupHeight = MeasureAndDrawRows(null, contentWidth) + padding;
  while (popupHeight > workArea.Height && usageFontPixels > 1) {
   SetFonts(Math.Max(1, Math.Min(usageFontPixels - 1, usageFontPixels * workArea.Height / popupHeight)));
   MeasureContentWidthAndColumns();
   popupHeight = MeasureAndDrawRows(null, contentWidth) + padding;
  }
  var popupSize = new Size(contentWidth + 2 * padding, Math.Min(popupHeight, workArea.Height));
  int popupLeft = Math.Max(workArea.Left, Math.Min(bandBounds.Left, workArea.Right - popupSize.Width));
  int popupTop = bandBounds.Bottom + Scale(GapFromTaskbar);
  if (popupTop + popupSize.Height > workArea.Bottom) popupTop = bandBounds.Top - popupSize.Height - Scale(GapFromTaskbar);
  popupTop = Math.Max(workArea.Top, Math.Min(popupTop, workArea.Bottom - popupSize.Height));
  Bounds = new Rectangle(new Point(popupLeft, popupTop), popupSize);
  int cornerRadius = Scale(PopupCornerRadius);
  if (ClientSize != roundedWindowSize || cornerRadius != roundedWindowRadius) {
   using (var outline = PopupOutline.CreateRoundedRectangle(ClientRectangle, cornerRadius)) {
    Region = new Region(outline);
   }
   roundedWindowSize = ClientSize;
   roundedWindowRadius = cornerRadius;
  }
  AccessibleDescription = String.Join(Environment.NewLine, rows.ConvertAll(row =>
   String.Join(" ", new[] { row.Label, row.Percent, row.Remaining, row.Note }).Trim()).ToArray()) +
   Environment.NewLine + "AgentMeter Taskbar " + VersionLabel;
  Invalidate();
 }

 private int Scale(int pixels) { return (pixels * dpi + QuotaView.DefaultDpi / 2) / QuotaView.DefaultDpi; }

 private void SetFonts(int pixels) {
  if (pixels == usageFontPixels) return;
  DisposeFonts();
  usageFontPixels = pixels;
  float fontScale = (float)pixels / PreferredUsageFontPixels;
  usageFont = new Font(QuotaView.SemiboldTypeface, pixels, FontStyle.Regular, GraphicsUnit.Pixel);
  headingFont = new Font(QuotaView.SemiboldTypeface, Math.Max(1, PreferredHeadingFontPixels * fontScale),
   FontStyle.Regular, GraphicsUnit.Pixel);
  detailFont = new Font("Segoe UI Variable Text", Math.Max(1, PreferredDetailFontPixels * fontScale),
   FontStyle.Regular, GraphicsUnit.Pixel);
 }

 private static bool IsPeriod(Row row) {
  return row.Kind == RowKind.FiveHour || row.Kind == RowKind.Weekly;
 }

 private static int MeasureLine(string value, Font font) {
  return String.IsNullOrEmpty(value) ? 0 : TextRenderer.MeasureText(value, font, Size.Empty, LineFlags).Width;
 }

 private int MeasureContentWidthAndColumns() {
  periodColumnWidth = MeasureLine("7d", detailFont);
  percentColumnWidth = MeasureLine("100%", usageFont);
  countdownColumnWidth = MeasureLine("00h 00m", detailFont);
  int headingWidth = 0;
  foreach (Row row in rows) {
   if (IsPeriod(row)) {
    periodColumnWidth = Math.Max(periodColumnWidth, MeasureLine(row.Label, detailFont));
    countdownColumnWidth = Math.Max(countdownColumnWidth, MeasureLine(row.Remaining, detailFont));
   } else if (row.Kind == RowKind.Heading) {
    headingWidth = Math.Max(headingWidth, MeasureLine(row.Label, headingFont));
   }
  }
  int quotaRowWidth = periodColumnWidth + percentColumnWidth + countdownColumnWidth + 2 * minimumColumnGap;
  return Math.Max(Math.Max(headingWidth, quotaRowWidth), MeasureLine(VersionLabel, detailFont));
 }

 // Use the same layout for measurement and painting so DPI and wrapped notices agree.
 private int MeasureAndDrawRows(Graphics graphics, int contentWidth) {
  int freeColumnSpace = Math.Max(0, contentWidth - periodColumnWidth - percentColumnWidth - countdownColumnWidth);
  int percentLeft = padding + periodColumnWidth + freeColumnSpace / 2;
  int countdownLeft = padding + contentWidth - countdownColumnWidth;
  int y = padding;
  for (int i = 0; i < rows.Count; i++) {
   Row row = rows[i];
   if (row.Kind == RowKind.Heading) {
    if (i > 0) {
     y += Scale(7);
     if (graphics != null) {
      using (var separatorPen = new Pen(separatorColor, Scale(1))) {
       graphics.DrawLine(separatorPen, padding, y, padding + contentWidth, y);
      }
     }
     y += Scale(11);
    }
    int headingHeight = headingFont.Height + Scale(6);
    DrawLine(graphics, row.Label, headingFont, textColor, padding, y, contentWidth, headingHeight, LineFlags);
    y += headingHeight;
   } else if (IsPeriod(row)) {
    Color accent = row.Kind == RowKind.Weekly ? weeklyTextColor : fiveHourTextColor;
    int rowHeight = usageFont.Height + Scale(3);
    DrawLine(graphics, row.Label, detailFont, accent, padding, y, periodColumnWidth, rowHeight, LineFlags);
    DrawLine(graphics, row.Percent, usageFont, accent, percentLeft, y, percentColumnWidth, rowHeight,
     LineFlags | TextFormatFlags.Right);
    DrawLine(graphics, row.Remaining, detailFont, detailColor, countdownLeft, y, countdownColumnWidth, rowHeight,
     LineFlags | TextFormatFlags.Right);
    y += rowHeight;
    if (!String.IsNullOrEmpty(row.Note)) y += DrawNotice(graphics, row.Note, detailColor, y, contentWidth);
   } else {
    y += DrawNotice(graphics, row.Label, detailColor, y, contentWidth);
   }
  }
  y += Scale(8);
  DrawLine(graphics, VersionLabel, detailFont, detailColor, padding, y, contentWidth, detailFont.Height,
   LineFlags | TextFormatFlags.Right);
  return y + detailFont.Height;
 }

 private int DrawNotice(Graphics graphics, string value, Color color, int y, int width) {
  int height = TextRenderer.MeasureText(value, detailFont, new Size(width, Int32.MaxValue), NoteFlags).Height;
  DrawLine(graphics, value, detailFont, color, padding, y, width, height, NoteFlags);
  return height + Scale(4);
 }

 private static void DrawLine(Graphics graphics, string value, Font font, Color color,
  int x, int y, int width, int height, TextFormatFlags flags) {
  if (graphics != null && !String.IsNullOrEmpty(value) && width > 0) {
   TextRenderer.DrawText(graphics, value, font, new Rectangle(x, y, width, height), color, flags);
  }
 }

 protected override void OnPaint(PaintEventArgs e) {
  int borderWidth = Math.Max(1, Scale(1));
  RectangleF borderBounds = RectangleF.Inflate(ClientRectangle, -borderWidth / 2f, -borderWidth / 2f);
  SmoothingMode previousSmoothing = e.Graphics.SmoothingMode;
  e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
  using (var outline = PopupOutline.CreateRoundedRectangle(borderBounds, roundedWindowRadius - borderWidth / 2f))
  using (var pen = new Pen(borderColor, borderWidth)) {
   e.Graphics.DrawPath(pen, outline);
  }
  e.Graphics.SmoothingMode = previousSmoothing;
  if (rows != null) MeasureAndDrawRows(e.Graphics, ClientSize.Width - 2 * padding);
  base.OnPaint(e);
 }

 private void DisposeFonts() {
  if (usageFont == null) return;
  usageFont.Dispose();
  headingFont.Dispose();
  detailFont.Dispose();
 }

 protected override void Dispose(bool disposing) {
  if (disposing) DisposeFonts();
  base.Dispose(disposing);
 }
}
