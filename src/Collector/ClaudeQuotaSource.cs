using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;

internal static class ClaudeQuotaSource {
    internal static Dictionary<QuotaPeriod, QuotaWindow> Read(string statusLinePath, string desktopHistoryPath,
        IDictionary<string, object> previousSnapshot, DateTimeOffset now, out string message) {
        var statusLine = QuotaJson.ReadObjectOrNull(statusLinePath);
        var desktopSample = ReadLatestDesktopSample(desktopHistoryPath, now);
        var fiveHour = SelectWindow(
            ReadStatusLineWindow(statusLine, "five_hour", now),
            ReadDesktopWindow(desktopSample, "fh"),
            ReadSavedWindow(previousSnapshot, "claude_five_hour", now), now);
        var weekly = SelectWindow(
            ReadStatusLineWindow(statusLine, "seven_day", now),
            ReadDesktopWindow(desktopSample, "sd"),
            ReadSavedWindow(previousSnapshot, "claude_weekly", now), now);

        var windows = new Dictionary<QuotaPeriod, QuotaWindow>();
        if (fiveHour != null) windows.Add(QuotaPeriod.FiveHour, fiveHour);
        if (weekly != null) windows.Add(QuotaPeriod.Weekly, weekly);

        if (statusLine != null) {
            message = "Waiting for current Claude usage. Open Usage in Claude Desktop or run a turn in Claude Code.";
        } else if (File.Exists(statusLinePath)) {
            message = "Claude Code status-line data could not be read.";
        } else {
            message = "Open Usage in Claude Desktop or enable the AgentMeter status line in Claude Code.";
        }
        return windows;
    }

    private static QuotaWindow ReadStatusLineWindow(IDictionary<string, object> snapshot, string field,
        DateTimeOffset now) {
        var window = QuotaJson.ObjectField(snapshot, field);
        var observedAt = QuotaJson.Timestamp(QuotaJson.Field(window, "observed_at"));
        if (!observedAt.HasValue || observedAt > now) return null;

        var resetAt = QuotaJson.Timestamp(QuotaJson.Field(window, "reset"));
        return QuotaWindow.Parse(QuotaJson.Field(window, "percent"), resetAt, observedAt);
    }

    private static IDictionary<string, object> ReadLatestDesktopSample(string path, DateTimeOffset now) {
        var history = QuotaJson.ReadObjectOrNull(path);
        var samples = QuotaJson.Field(history, "samples") as IList;
        if (QuotaJson.Integer(QuotaJson.Field(history, "version")) != 2 || samples == null) return null;

        long nowMilliseconds = now.ToUnixTimeMilliseconds();
        long latestMilliseconds = 1;
        IDictionary<string, object> latestSample = null;
        foreach (var sample in samples) {
            var record = sample as IDictionary<string, object>;
            long? timestamp = QuotaJson.Integer(QuotaJson.Field(record, "t"));
            if (!timestamp.HasValue || timestamp < latestMilliseconds || timestamp > nowMilliseconds) continue;
            latestMilliseconds = timestamp.Value;
            latestSample = record;
        }
        return latestSample;
    }

    private static QuotaWindow ReadDesktopWindow(IDictionary<string, object> sample, string field) {
        if (sample == null) return null;
        long timestamp = QuotaJson.Integer(QuotaJson.Field(sample, "t")).Value;
        var percentages = QuotaJson.ObjectField(sample, "u");
        return QuotaWindow.Parse(QuotaJson.Field(percentages, field), null,
            DateTimeOffset.FromUnixTimeMilliseconds(timestamp));
    }

    private static QuotaWindow ReadSavedWindow(IDictionary<string, object> snapshot, string prefix,
        DateTimeOffset now) {
        var observedAt = QuotaJson.Timestamp(QuotaJson.Field(snapshot, prefix + "_observed_at"));
        if (!observedAt.HasValue || observedAt > now) return null;

        var resetAt = QuotaJson.Timestamp(QuotaJson.Field(snapshot, prefix + "_reset_at"));
        return QuotaWindow.Parse(QuotaJson.Field(snapshot, prefix + "_last_pct"), resetAt, observedAt);
    }

    private static QuotaWindow SelectWindow(QuotaWindow statusLine, QuotaWindow desktop,
        QuotaWindow saved, DateTimeOffset now) {
        QuotaWindow latest = null;
        // Current values take precedence by source. Once they expire, keep the newest observation.
        foreach (var window in new[] { statusLine, desktop, saved }) {
            if (window == null) continue;
            if (window.IsCurrent(now)) return window;
            if (latest == null || window.ObservedAt > latest.ObservedAt) latest = window;
        }
        return latest;
    }
}
