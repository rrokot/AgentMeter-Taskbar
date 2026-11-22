using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Windows.Forms;

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

 internal void UpdateContentAndPosition(List<Row> content, bool lightTheme, int ownerDpi, Rectangle bandBounds,
  Rectangle workArea, bool isVerticalTaskbar) {
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
  Bounds = new Rectangle(GetPopupLocation(bandBounds, workArea, popupSize, Scale(GapFromTaskbar), isVerticalTaskbar), popupSize);
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

 private static Point GetPopupLocation(Rectangle bandBounds, Rectangle workArea, Size popupSize, int gap, bool isVerticalTaskbar) {
  int left = bandBounds.Left;
  int top = bandBounds.Top;
  if (isVerticalTaskbar) {
   bool onLeftEdge = bandBounds.Left + bandBounds.Width / 2 < workArea.Left + workArea.Width / 2;
   left = onLeftEdge ? bandBounds.Right + gap : bandBounds.Left - gap - popupSize.Width;
  } else {
   bool onTopEdge = bandBounds.Top + bandBounds.Height / 2 < workArea.Top + workArea.Height / 2;
   top = onTopEdge ? bandBounds.Bottom + gap : bandBounds.Top - gap - popupSize.Height;
  }
  return new Point(Math.Max(workArea.Left, Math.Min(left, workArea.Right - popupSize.Width)),
   Math.Max(workArea.Top, Math.Min(top, workArea.Bottom - popupSize.Height)));
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
