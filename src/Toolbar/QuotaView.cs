using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal sealed class QuotaView : Control {
 internal const int DefaultDpi = 96;
 internal const int PreferredHorizontalLength = 104;
 private const int PreferredVerticalLayoutWidth = 88;
 internal const string SemiboldTypeface = "Segoe UI Semibold";
 private const int SnapshotPollIntervalMilliseconds = 5000;
 private const int QuotaPeriodsPerProvider = 2;
 private const int ClaudeFiveHourTrackIndex = 0;
 private const int CodexFiveHourTrackIndex = QuotaPeriodsPerProvider;
 private const int WeeklyTrackOffset = 1;
 private const string FiveHourSnapshotSlot = "five_hour";
 private const string WeeklySnapshotSlot = "weekly";
 private const int IncreaseRiseMilliseconds = 2100;
 private const int IncreaseHoldMilliseconds = 300;
 private const int IncreaseDisplayMilliseconds = IncreaseRiseMilliseconds + IncreaseHoldMilliseconds;
 private const int IncreaseFrameIntervalMilliseconds = 25;
 private const int PopupPointerPollMilliseconds = 75;
 private const int PopupPointerLeaveMilliseconds = 300;
 private static readonly TimeSpan MaximumDataAge = TimeSpan.FromMinutes(3);
 private static readonly QuotaTrack[] QuotaTracks = {
  new QuotaTrack("claude", FiveHourSnapshotSlot, "5h", QuotaPopup.RowKind.FiveHour),
  new QuotaTrack("claude", WeeklySnapshotSlot, "7d", QuotaPopup.RowKind.Weekly),
  new QuotaTrack("codex", FiveHourSnapshotSlot, "5h", QuotaPopup.RowKind.FiveHour),
  new QuotaTrack("codex", WeeklySnapshotSlot, "7d", QuotaPopup.RowKind.Weekly)
 };
 internal static readonly Color FiveHourTop = Color.FromArgb(115, 227, 242);
 private static readonly Color FiveHourBottom = Color.FromArgb(69, 134, 237);
 internal static readonly Color WeeklyTop = Color.FromArgb(255, 209, 168);
 private static readonly Color WeeklyBottom = Color.FromArgb(224, 119, 77);
 private static readonly Color FiveHourIncreaseTextColor = Color.FromArgb(26, 88, 190);
 private static readonly Color WeeklyIncreaseTextColor = Color.FromArgb(192, 33, 44);
 private readonly Timer snapshotTimer = new Timer { Interval = SnapshotPollIntervalMilliseconds };
 private readonly Timer increaseDisplayTimer = new Timer { Interval = IncreaseFrameIntervalMilliseconds };
 private readonly Timer popupPointerTimer = new Timer { Interval = PopupPointerPollMilliseconds };
 private readonly Stopwatch increaseDisplayClock = new Stopwatch();
 private readonly Stopwatch popupPointerClock = new Stopwatch();
 private readonly int[] usageIncreases = new int[QuotaTracks.Length];
 private readonly FontFamily increaseTypeface = new FontFamily(SemiboldTypeface);
 private bool animateIncreaseRise;
 private QuotaPopup popup;
 private readonly JavaScriptSerializer jsonSerializer = new JavaScriptSerializer();
 private readonly IntPtr parentWindow;
 private readonly string snapshotPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
  InstallationLayout.DirectoryName, "data.json");
 private Dictionary<string, string> snapshot = new Dictionary<string, string>();
 private DateTimeOffset snapshotWrittenAt;
 private bool lightTheme;
 private bool isVerticalTaskbar;
 private struct QuotaTrack {
  internal readonly string ProviderKey, SnapshotKey, Label;
  internal readonly QuotaPopup.RowKind Period;

  internal QuotaTrack(string providerKey, string snapshotSlot, string label, QuotaPopup.RowKind period) {
   ProviderKey = providerKey;
   SnapshotKey = providerKey + "_" + snapshotSlot;
   Label = label;
   Period = period;
  }
 }
 private enum UpdateAction { Check, Install, Restart }
 private UpdateAction nextUpdateAction;
 private Version updateVersion;
 private string updateNotice;
 private bool updateInProgress;
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
  popupPointerTimer.Tick += delegate { CheckPopupPointer(); };
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
 internal void SetTaskbarOrientation(bool vertical) {
  if (isVerticalTaskbar == vertical) return;
  isVerticalTaskbar = vertical;
  HidePopup();
  Invalidate();
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
  if (popup == null) {
   popup = new QuotaPopup();
   popup.UpdateRequested += delegate { RunUpdateAction(); };
  }
  UpdatePopup();
  if (!popup.Visible) popup.Show(this);
  popupPointerClock.Restart();
  popupPointerTimer.Start();
 }
 private void CheckPopupPointer() {
  Point pointer = Cursor.Position;
  if (popup != null && popup.Visible &&
      (ClientRectangle.Contains(PointToClient(pointer)) || popup.Bounds.Contains(pointer))) {
   popupPointerClock.Restart();
  } else if (popupPointerClock.ElapsedMilliseconds >= PopupPointerLeaveMilliseconds) {
   HidePopup();
  }
 }
 private void HidePopup() {
  popupPointerTimer.Stop();
  popupPointerClock.Reset();
  if (popup != null) popup.Hide();
 }
 private async void RunUpdateAction() {
  if (updateInProgress) return;
  updateInProgress = true;
  string directory = Path.GetDirectoryName(snapshotPath);
  try {
   if (nextUpdateAction == UpdateAction.Restart) {
    await RestartUpdatedToolbar(directory);
    return;
   }
   Version target = nextUpdateAction == UpdateAction.Install ? updateVersion : null;
   updateNotice = target == null ? "Checking for updates…" : "Installing v" + target + "…";
   RefreshUpdatePopup();
   ToolbarUpdater.Result reply = await ToolbarUpdater.RequestAsync(directory, target);
   switch (reply.Outcome) {
    case ToolbarUpdater.Status.Available:
     updateVersion = reply.Version;
     nextUpdateAction = UpdateAction.Install;
     updateNotice = "v" + updateVersion + " is available." + Environment.NewLine + "Updating will restart Explorer.";
     break;
    case ToolbarUpdater.Status.Current:
     if (ToolbarUpdater.RunningVersion != null && reply.Version > ToolbarUpdater.RunningVersion) {
      updateVersion = reply.Version;
      nextUpdateAction = UpdateAction.Restart;
      updateNotice = "v" + updateVersion + " is installed and ready to load.";
     } else {
      nextUpdateAction = UpdateAction.Check;
      updateNotice = "You're up to date.";
     }
     break;
    case ToolbarUpdater.Status.Installed:
     updateVersion = reply.Version;
     nextUpdateAction = UpdateAction.Restart;
     await RestartUpdatedToolbar(directory);
     break;
    case ToolbarUpdater.Status.Busy:
     updateNotice = "An update check is already running.";
     break;
    default:
     updateNotice = target == null ? "Could not check for updates. Try again." : "Could not install the update. Try again.";
     break;
   }
  } finally {
   updateInProgress = false;
   RefreshUpdatePopup();
  }
 }
 private async Task RestartUpdatedToolbar(string directory) {
  updateNotice = "v" + updateVersion + " installed. Restarting Explorer…";
  RefreshUpdatePopup();
  if (await ToolbarUpdater.RestartExplorerAsync(directory)) {
   nextUpdateAction = UpdateAction.Check;
   updateNotice = "v" + updateVersion + " is installed.";
  } else {
   updateNotice = "v" + updateVersion + " is installed. Explorer could not restart.";
  }
 }
 private void RefreshUpdatePopup() {
  if (!IsDisposed && !Disposing && IsHandleCreated && popup != null && popup.Visible) UpdatePopup();
 }
 protected override void OnVisibleChanged(EventArgs e) {
  base.OnVisibleChanged(e);
  if (!Visible) {
   HidePopup();
   StopIncreaseDisplay();
  }
 }
 protected override void OnHandleDestroyed(EventArgs e) {
  StopIncreaseDisplay();
  HidePopup();
  if (popup != null) {
   popup.Dispose();
   popup = null;
  }
  base.OnHandleDestroyed(e);
 }
 private void UpdatePopup() {
  string actionText = nextUpdateAction == UpdateAction.Install ? "Update" :
   nextUpdateAction == UpdateAction.Restart ? "Restart Explorer" : "Check for updates";
  popup.SetUpdateState(actionText, updateNotice, !updateInProgress);
  int dpi = (int)GetDpiForWindow(Handle);
  popup.UpdateContentAndPosition(BuildPopupRows(), lightTheme, dpi == 0 ? DefaultDpi : dpi,
   RectangleToScreen(ClientRectangle), Screen.FromHandle(Handle).WorkingArea, isVerticalTaskbar);
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
      if (!nextSnapshot.TryGetValue("updated_at", out writtenAtText) ||
          !DateTimeOffset.TryParseExact(writtenAtText, "o", CultureInfo.InvariantCulture,
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
  for (int trackIndex = 0; trackIndex < usageIncreases.Length; trackIndex++) {
   usageIncreases[trackIndex] = GetUsageIncrease(previousSnapshot, nextSnapshot, trackIndex, now);
   hasIncrease |= usageIncreases[trackIndex] > 0;
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
  int trackIndex, DateTimeOffset now) {
  QuotaTrack track = QuotaTracks[trackIndex];
  string quotaKey = track.SnapshotKey;
  DateTimeOffset? resetAt = ReadResetTime(nextSnapshot, quotaKey);
  int previousPercent, nextPercent;
  if (resetAt != ReadResetTime(previousSnapshot, quotaKey) ||
      !TryGetUsagePercent(previousSnapshot, track, now, resetAt, out previousPercent) ||
      !TryGetUsagePercent(nextSnapshot, track, now, resetAt, out nextPercent)) return 0;
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
  return ReadTimestamp(snapshot, quotaKey + "_reset_at");
 }
 private static DateTimeOffset? ReadTimestamp(Dictionary<string, string> snapshot, string key) {
  string value;
  DateTimeOffset timestamp;
  if (snapshot.TryGetValue(key, out value) &&
      DateTimeOffset.TryParseExact(value, "o", CultureInfo.InvariantCulture, DateTimeStyles.None, out timestamp)) return timestamp;
  return null;
 }
 private static bool TryReadPercent(Dictionary<string, string> snapshot, string key, out int percent) {
  string text;
  percent = 0;
  if (!snapshot.TryGetValue(key, out text) || !int.TryParse(text, out percent)) return false;
  percent = Math.Min(100, Math.Max(0, percent));
  return true;
 }
 private static bool TryGetUsagePercent(Dictionary<string, string> snapshot, QuotaTrack track, DateTimeOffset now,
  DateTimeOffset? resetAt, out int percent) {
  string status;
  string quotaKey = track.SnapshotKey;
  string statusKey = track.ProviderKey + "_status";
  percent = 0;
  if (resetAt <= now || ReadTimestamp(snapshot, quotaKey + "_fresh_until") <= now ||
      !snapshot.TryGetValue(statusKey, out status) || status != "ok" ||
      !TryReadPercent(snapshot, quotaKey + "_pct", out percent)) return false;
  return true;
 }
 private Rectangle GetTrackBounds(int trackIndex, int dpi) {
  return isVerticalTaskbar ? GetVerticalTrackBounds(trackIndex, dpi) : GetHorizontalTrackBounds(trackIndex, dpi);
 }
 private Rectangle GetHorizontalTrackBounds(int trackIndex, int dpi) {
  const int ProviderCount = 2;
  int availableWidth = Math.Min(ClientSize.Width, PreferredHorizontalLength * dpi / DefaultDpi);
  if (availableWidth < ProviderCount || ClientSize.Height < QuotaPeriodsPerProvider) return Rectangle.Empty;

  int providerGap = Math.Min(6 * dpi / DefaultDpi, (availableWidth - ProviderCount) / 3);
  int sidePadding = Math.Min(5 * dpi / DefaultDpi, (availableWidth - providerGap - ProviderCount) / 2);
  int trackWidth = (availableWidth - 2 * sidePadding - providerGap) / ProviderCount;
  int firstTrackLeft = (ClientSize.Width - (ProviderCount * trackWidth + providerGap)) / 2;
  int providerIndex = trackIndex / QuotaPeriodsPerProvider;
  int trackLeft = firstTrackLeft + providerIndex * (trackWidth + providerGap);

  int periodGap = Math.Min(3 * dpi / DefaultDpi, (ClientSize.Height - QuotaPeriodsPerProvider) / 3);
  int trackHeight = Math.Min(7 * dpi / DefaultDpi, (ClientSize.Height - periodGap) / QuotaPeriodsPerProvider);
  int firstTrackTop = (ClientSize.Height - (QuotaPeriodsPerProvider * trackHeight + periodGap)) / 2;
  int periodIndex = trackIndex % QuotaPeriodsPerProvider;
  return new Rectangle(trackLeft, firstTrackTop + periodIndex * (trackHeight + periodGap), trackWidth, trackHeight);
 }
 private Rectangle GetVerticalTrackBounds(int trackIndex, int dpi) {
  int availableWidth = Math.Min(ClientSize.Width, PreferredVerticalLayoutWidth * dpi / DefaultDpi);
  int trackCount = QuotaTracks.Length;
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
  int trackLeft = firstTrackLeft + trackIndex * (trackWidth + trackGap) + (trackIndex >= CodexFiveHourTrackIndex ? extraProviderGap : 0);
  int verticalPadding = 3 * dpi / DefaultDpi;
  return new Rectangle(trackLeft, verticalPadding, trackWidth, Math.Max(0, ClientSize.Height - 2 * verticalPadding));
 }
 protected override void OnPaint(PaintEventArgs e) {
  e.Graphics.Clear(lightTheme ? Color.FromArgb(238, 238, 238) : Color.FromArgb(25, 25, 31));
  int dpi = IsHandleCreated ? (int)GetDpiForWindow(Handle) : DefaultDpi;
  if (dpi == 0) dpi = DefaultDpi;
  DateTimeOffset now = DateTimeOffset.UtcNow;
  bool hasFreshSnapshot = HasFreshSnapshot(now);
  for (int trackIndex = 0; trackIndex < QuotaTracks.Length; trackIndex++) {
   QuotaTrack track = QuotaTracks[trackIndex];
   Rectangle trackBounds = GetTrackBounds(trackIndex, dpi);
   if (trackBounds.Width == 0 || trackBounds.Height == 0) continue;
   e.Graphics.FillRectangle(lightTheme ? Brushes.Silver : Brushes.DimGray, trackBounds);
   string quotaKey = track.SnapshotKey;
   DateTimeOffset? resetAt = ReadResetTime(snapshot, quotaKey);
   int percent = 0;
   bool hasCurrentUsage = hasFreshSnapshot && TryGetUsagePercent(snapshot, track, now, resetAt, out percent);
   if (!hasCurrentUsage && !TryReadPercent(snapshot, quotaKey + "_last_pct", out percent)) continue;
   if (percent == 0) continue;
   int trackLength = isVerticalTaskbar ? trackBounds.Height : trackBounds.Width;
   int fillLength = Math.Max(1, percent * trackLength / 100);
   var fill = isVerticalTaskbar ? new Rectangle(trackBounds.X, trackBounds.Bottom - fillLength, trackBounds.Width, fillLength)
    : new Rectangle(trackBounds.X, trackBounds.Y, fillLength, trackBounds.Height);
   bool weekly = track.Period == QuotaPopup.RowKind.Weekly;
   int opacity = hasCurrentUsage ? 255 : 105;
   Color startColor = Color.FromArgb(opacity, weekly ? WeeklyTop : FiveHourTop);
   Color endColor = Color.FromArgb(opacity, weekly ? WeeklyBottom : FiveHourBottom);
   using (var brush = new LinearGradientBrush(fill, startColor, endColor, LinearGradientMode.Vertical)) {
    e.Graphics.FillRectangle(brush, fill);
   }
   const int WarningPercent = 60, CriticalPercent = 85;
   if (hasCurrentUsage && percent >= WarningPercent && fillLength > 1) {
    var warningEdge = isVerticalTaskbar ? new Rectangle(fill.X, fill.Y, fill.Width, 1)
     : new Rectangle(fill.Right - 1, fill.Y, 1, fill.Height);
    e.Graphics.FillRectangle(percent >= CriticalPercent ? Brushes.Tomato : Brushes.Gold, warningEdge);
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
  float availableHeight = isVerticalTaskbar ? ClientSize.Height * 0.8f : ClientSize.Height;
  float blockHeight = Math.Min(23 * dpiScale, availableHeight);
  float blockTop = (float)Math.Round((ClientSize.Height - blockHeight) * verticalPosition);
  SmoothingMode previousSmoothing = graphics.SmoothingMode;
  graphics.SmoothingMode = SmoothingMode.AntiAlias;
  for (int fiveHourIndex = 0; fiveHourIndex < usageIncreases.Length; fiveHourIndex += QuotaPeriodsPerProvider) {
   int weeklyIndex = fiveHourIndex + WeeklyTrackOffset;
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
   float verticalPadding = Math.Min(VerticalPadding * dpiScale, block.Height * 0.32f);
   float numberMaxHeight = Math.Max(1, block.Height - verticalPadding);
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
   if (snapshot.ContainsKey(QuotaTracks[ClaudeFiveHourTrackIndex].SnapshotKey + "_last_pct") ||
       snapshot.ContainsKey(QuotaTracks[ClaudeFiveHourTrackIndex + WeeklyTrackOffset].SnapshotKey + "_last_pct")) {
    AddProviderRows(rows, "Claude", ClaudeFiveHourTrackIndex, now);
   }
   rows.Add(new QuotaPopup.Row(QuotaPopup.RowKind.Notice,
    snapshotWrittenAt == DateTimeOffset.MinValue ? "Waiting for quota data." : "Quota data is stale."));
  } else {
   AddProviderRows(rows, "Claude", ClaudeFiveHourTrackIndex, now);
   AddProviderRows(rows, "Codex", CodexFiveHourTrackIndex, now);
  }
  return rows;
 }
 private void AddProviderRows(List<QuotaPopup.Row> rows, string title, int fiveHourTrackIndex, DateTimeOffset now) {
  QuotaTrack fiveHourTrack = QuotaTracks[fiveHourTrackIndex];
  QuotaTrack weeklyTrack = QuotaTracks[fiveHourTrackIndex + WeeklyTrackOffset];
  string providerKey = fiveHourTrack.ProviderKey;
  rows.Add(new QuotaPopup.Row(QuotaPopup.RowKind.Heading, title));
  if (SnapshotValue(providerKey + "_status") != "ok") {
   string message = SnapshotValue(providerKey + "_msg");
   rows.Add(new QuotaPopup.Row(QuotaPopup.RowKind.Notice,
    String.IsNullOrWhiteSpace(message) ? "Quota data unavailable." : message));
   return;
  }
  rows.Add(CreatePeriodRow(fiveHourTrack, now));
  rows.Add(CreatePeriodRow(weeklyTrack, now));
 }
 private QuotaPopup.Row CreatePeriodRow(QuotaTrack track, DateTimeOffset now) {
  string quotaKey = track.SnapshotKey;
  QuotaPopup.RowKind kind = track.Period;
  string label = track.Label;
  DateTimeOffset? resetAt = ReadResetTime(snapshot, quotaKey);
  int percent;
  bool hasCurrentUsage = HasFreshSnapshot(now) && !(resetAt <= now) &&
   !(ReadTimestamp(snapshot, quotaKey + "_fresh_until") <= now);
  if (!hasCurrentUsage && TryReadPercent(snapshot, quotaKey + "_last_pct", out percent)) {
   DateTimeOffset? observedAt = ReadTimestamp(snapshot, quotaKey + "_observed_at");
   string note = observedAt.HasValue ? "Last known · " + observedAt.Value.LocalDateTime.ToString("g") : "Last known";
   return new QuotaPopup.Row(kind, label, percent + "%", note: note);
  }
  if (!hasCurrentUsage) return new QuotaPopup.Row(kind, label, note: "Waiting for fresh usage data.");
  if (!TryReadPercent(snapshot, quotaKey + "_pct", out percent)) {
   return new QuotaPopup.Row(kind, label, note: "Quota data unavailable.");
  }
  string usage = percent + "%";
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
   popupPointerTimer.Dispose();
   increaseTypeface.Dispose();
  }
 }
}
