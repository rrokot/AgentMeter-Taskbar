using System;
using System.IO;

internal static class AgentMeterCollector {
    private static int Main(string[] args) {
        try {
            if (args.Length == 1 && args[0] == "claude-status") {
                ClaudeStatusLine.Publish(AppDomain.CurrentDomain.BaseDirectory, Console.In, Console.Out);
                return 0;
            }
            if (args.Length != 0) return 1;
            string codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
            if (string.IsNullOrEmpty(codexHome)) {
                codexHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
            }
            string claudeDesktopHistory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                @"Claude\plan-usage-history.json");
            QuotaSnapshot.Collect(AppDomain.CurrentDomain.BaseDirectory, codexHome, claudeDesktopHistory);
            return 0;
        } catch (IOException) {
            return 1;
        } catch (UnauthorizedAccessException) {
            return 1;
        }
    }
}
