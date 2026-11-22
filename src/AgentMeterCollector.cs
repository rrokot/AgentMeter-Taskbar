using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;

internal static class AgentMeterCollector {
    private static int Main() {
        string installDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string collectorScript = Path.Combine(installDirectory, "RefreshQuota.ps1");
        if (!File.Exists(collectorScript)) return 1;

        var processInfo = new ProcessStartInfo {
            FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
            Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + collectorScript + "\"",
            WorkingDirectory = installDirectory,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        try {
            using (var collector = Process.Start(processInfo)) {
                collector.WaitForExit();
                return collector.ExitCode;
            }
        } catch (Win32Exception) {
            return 1;
        }
    }
}
