using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

internal static class ClaudeStatusLine {
    internal static void Publish(string directory, TextReader input, TextWriter output) {
        string json = input.ReadToEnd();
        if (string.IsNullOrWhiteSpace(json)) return;
        var limits = QuotaJson.ObjectField(QuotaJson.ParseObject(json), "rate_limits");
        var now = DateTimeOffset.UtcNow;
        var fiveHour = ParseWindow(limits, "five_hour", now);
        var weekly = ParseWindow(limits, "seven_day", now);
        if (fiveHour == null && weekly == null) return;

        var labels = new List<string>(2);
        if (fiveHour != null) labels.Add("5h: " + fiveHour.UsedPercent.ToString(CultureInfo.InvariantCulture) + "%");
        if (weekly != null) labels.Add("7d: " + weekly.UsedPercent.ToString(CultureInfo.InvariantCulture) + "%");
        output.WriteLine(string.Join(" | ", labels));

        using (var writerLock = QuotaJson.OpenWriterLock(Path.Combine(directory, "claude-usage.lock"))) {
            if (writerLock == null) return;
            string path = Path.Combine(directory, "claude-usage.json");
            var previous = QuotaJson.ReadObjectOrNull(path);
            var snapshot = new Dictionary<string, object>();
            SaveLatestWindow(snapshot, "five_hour", fiveHour, previous);
            SaveLatestWindow(snapshot, "seven_day", weekly, previous);
            QuotaJson.ReplaceFile(path, snapshot);
        }
    }

    private static QuotaWindow ParseWindow(IDictionary<string, object> limits, string period, DateTimeOffset now) {
        var window = QuotaJson.ObjectField(limits, period);
        return QuotaWindow.Parse(QuotaJson.Field(window, "used_percentage"),
            QuotaJson.UnixSeconds(QuotaJson.Field(window, "resets_at")), now);
    }

    private static void SaveLatestWindow(Dictionary<string, object> snapshot, string period, QuotaWindow incoming,
        IDictionary<string, object> previous) {
        var saved = QuotaJson.ObjectField(previous, period);
        var savedAt = QuotaJson.Timestamp(QuotaJson.Field(saved, "observed_at"));
        if (savedAt.HasValue && (incoming == null || savedAt > incoming.ObservedAt)) {
            var savedWindow = QuotaWindow.Parse(QuotaJson.Field(saved, "percent"),
                QuotaJson.Timestamp(QuotaJson.Field(saved, "reset")), savedAt);
            if (savedWindow != null) incoming = savedWindow;
        }
        if (incoming == null) return;
        snapshot[period] = new Dictionary<string, object> {
            { "percent", incoming.UsedPercent },
            { "reset", QuotaJson.IsoTimestamp(incoming.ResetAt) },
            { "observed_at", QuotaJson.IsoTimestamp(incoming.ObservedAt) }
        };
    }
}
