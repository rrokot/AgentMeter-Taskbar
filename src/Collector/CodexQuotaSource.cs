using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

internal static class CodexQuotaSource {
    private const int RecentSessionLogCount = 10;

    internal static Dictionary<QuotaPeriod, QuotaWindow> Read(string codexHome) {
        var latestWindows = new Dictionary<QuotaPeriod, QuotaWindow>();
        DateTimeOffset latestTimestamp = DateTimeOffset.MinValue;
        var sessionsDirectory = new DirectoryInfo(Path.Combine(codexHome, "sessions"));
        var recentLogs = EnumerateSessionLogs(sessionsDirectory)
            .OrderByDescending(log => log.LastWriteTimeUtc)
            .Take(RecentSessionLogCount);

        foreach (var log in recentLogs) {
            try {
                using (var reader = QuotaJson.OpenSharedReader(log.FullName)) {
                    string line;
                    while ((line = reader.ReadLine()) != null) {
                        if (!line.Contains("\"rate_limits\"")) continue;
                        var record = QuotaJson.ParseObject(line);
                        var payload = QuotaJson.ObjectField(record, "payload");
                        var limits = QuotaJson.ObjectField(payload, "rate_limits");
                        if (limits == null || !MatchesOrMissing(limits, "limit_id", "codex")
                            || !MatchesOrMissing(payload, "type", "token_count")) continue;

                        var timestamp = QuotaJson.Timestamp(QuotaJson.Field(record, "timestamp")) ?? log.LastWriteTimeUtc;
                        if (timestamp < latestTimestamp) continue;

                        var windows = new Dictionary<QuotaPeriod, QuotaWindow>();
                        ReadWindow(windows, QuotaJson.ObjectField(limits, "primary"), QuotaPeriod.FiveHour);
                        ReadWindow(windows, QuotaJson.ObjectField(limits, "secondary"), QuotaPeriod.Weekly);
                        if (windows.Count == 0) continue;
                        latestTimestamp = timestamp;
                        latestWindows = windows;
                    }
                }
            } catch (IOException) {
                // Codex may remove or rotate a session file while it is being read.
            } catch (UnauthorizedAccessException) {
                // Other session files may still provide usage.
            }
        }
        return latestWindows;
    }

    private static IEnumerable<FileInfo> EnumerateSessionLogs(DirectoryInfo directory) {
        FileInfo[] logs;
        DirectoryInfo[] subdirectories;
        try {
            logs = directory.GetFiles("rollout-*.jsonl");
            subdirectories = directory.GetDirectories();
        } catch (IOException) {
            yield break;
        } catch (UnauthorizedAccessException) {
            yield break;
        }

        foreach (var log in logs) yield return log;
        foreach (var subdirectory in subdirectories) {
            if ((subdirectory.Attributes & FileAttributes.ReparsePoint) != 0) continue;
            foreach (var log in EnumerateSessionLogs(subdirectory)) yield return log;
        }
    }

    private static bool MatchesOrMissing(IDictionary<string, object> record, string field, string expected) {
        string value = QuotaJson.Text(QuotaJson.Field(record, field));
        return string.IsNullOrEmpty(value) || string.Equals(value, expected, StringComparison.OrdinalIgnoreCase);
    }

    private static void ReadWindow(Dictionary<QuotaPeriod, QuotaWindow> windows,
        IDictionary<string, object> source, QuotaPeriod defaultPeriod) {
        QuotaPeriod period;
        switch (QuotaJson.Text(QuotaJson.Field(source, "window_minutes"))) {
            case "300": period = QuotaPeriod.FiveHour; break;
            case "10080": period = QuotaPeriod.Weekly; break;
            case "": period = defaultPeriod; break;
            default: return;
        }

        var resetAt = QuotaJson.UnixSeconds(QuotaJson.Field(source, "resets_at"));
        var window = QuotaWindow.Parse(QuotaJson.Field(source, "used_percent"), resetAt);
        if (window != null) windows[period] = window;
    }
}
