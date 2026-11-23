using System;
using System.IO;
using System.Text;

internal static class AgentMeterCollector {
    private static int Main(string[] args) {
        try {
            if (args.Length == 1 && args[0] == "claude-status") {
                var utf8 = new UTF8Encoding(false);
                using (var input = new StreamReader(Console.OpenStandardInput(), utf8, true))
                using (var output = new StreamWriter(Console.OpenStandardOutput(), utf8)) {
                    ClaudeStatusLine.Publish(AppDomain.CurrentDomain.BaseDirectory, input, output);
                }
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
