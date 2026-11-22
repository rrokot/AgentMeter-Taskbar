using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

internal static class QuotaSnapshot {
    internal static void Collect(string dataDirectory, string codexHome, string claudeDesktopHistory,
        DateTimeOffset? collectionTime = null) {
        using (var writerLock = QuotaJson.OpenWriterLock(Path.Combine(dataDirectory, "collector.lock"))) {
            if (writerLock == null) return;

            string codexMessage = "Start a Codex CLI session with a ChatGPT subscription to refresh usage.";
            Dictionary<QuotaPeriod, QuotaWindow> codexWindows;
            try {
                codexWindows = CodexQuotaSource.Read(codexHome);
            } catch (ArgumentException) {
                codexWindows = new Dictionary<QuotaPeriod, QuotaWindow>();
                codexMessage = "Codex session logs could not be read.";
            } catch (NotSupportedException) {
                codexWindows = new Dictionary<QuotaPeriod, QuotaWindow>();
                codexMessage = "Codex session logs could not be read.";
            }

            var now = collectionTime ?? DateTimeOffset.UtcNow;
            string snapshotPath = Path.Combine(dataDirectory, "data.json");
            string claudeMessage;
            var claudeWindows = ClaudeQuotaSource.Read(Path.Combine(dataDirectory, "claude-usage.json"),
                claudeDesktopHistory, QuotaJson.ReadObjectOrNull(snapshotPath), now, out claudeMessage);

            var snapshot = new Dictionary<string, string> { { "updated_at", QuotaJson.IsoTimestamp(now) } };
            AddProvider(snapshot, "codex", codexWindows, codexMessage, now);
            AddProvider(snapshot, "claude", claudeWindows, claudeMessage, now);
            QuotaJson.ReplaceFile(snapshotPath, snapshot);
        }
    }

    private static void AddProvider(Dictionary<string, string> snapshot, string provider,
        Dictionary<QuotaPeriod, QuotaWindow> windows, string message, DateTimeOffset now) {
        snapshot[provider + "_status"] = windows.Count > 0 ? "ok" : "error";
        snapshot[provider + "_msg"] = windows.Count > 0 ? "" : message;

        AddWindow(snapshot, provider + "_five_hour", windows, QuotaPeriod.FiveHour, now);
        AddWindow(snapshot, provider + "_weekly", windows, QuotaPeriod.Weekly, now);
    }

    private static void AddWindow(Dictionary<string, string> snapshot, string prefix,
        Dictionary<QuotaPeriod, QuotaWindow> windows, QuotaPeriod period, DateTimeOffset now) {
        snapshot[prefix + "_pct"] = "";
        snapshot[prefix + "_reset_at"] = "";

        QuotaWindow window;
        if (!windows.TryGetValue(period, out window)) return;
        string percent = window.UsedPercent.ToString(CultureInfo.InvariantCulture);
        snapshot[prefix + "_reset_at"] = QuotaJson.IsoTimestamp(window.ResetAt);
        if (window.IsCurrent(now)) snapshot[prefix + "_pct"] = percent;
        if (window.ObservedAt.HasValue) {
            snapshot[prefix + "_last_pct"] = percent;
            snapshot[prefix + "_observed_at"] = QuotaJson.IsoTimestamp(window.ObservedAt);
            snapshot[prefix + "_fresh_until"] = QuotaJson.IsoTimestamp(window.FreshUntil);
        }
    }
}
