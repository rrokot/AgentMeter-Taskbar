using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

internal static class ToolbarUpdater {
    internal enum Status { Failed, Busy, Current, Available, Installed }

    internal struct Result {
        internal readonly Status Outcome;
        internal readonly Version Version;

        internal Result(Status outcome, Version version) {
            Outcome = outcome;
            Version = version;
        }
    }

    private const int CheckTimeoutMilliseconds = 45000;
    private const int InstallTimeoutMilliseconds = 300000;
    private const int RestartTimeoutMilliseconds = 45000;
    internal static readonly Version RunningVersion = ReadRunningVersion();

    internal static Task<Result> RequestAsync(string directory, Version targetVersion) {
        return Task.Run(() => {
            string arguments = targetVersion == null ? "check" : "install " + targetVersion;
            int timeout = targetVersion == null ? CheckTimeoutMilliseconds : InstallTimeoutMilliseconds;
            string output = RunUpdater(directory, arguments, timeout);
            if (output == null) return default(Result);
            try {
                var reply = new JavaScriptSerializer().Deserialize<Dictionary<string, string>>(output);
                string status, versionText;
                if (reply == null || !reply.TryGetValue("status", out status)) return default(Result);
                if (status == "busy") return new Result(Status.Busy, null);
                Version version;
                if (!reply.TryGetValue("version", out versionText) || !Version.TryParse(versionText, out version) ||
                    version.Build < 0 || version.Revision >= 0) return default(Result);
                switch (status) {
                    case "current": return new Result(Status.Current, version);
                    case "available": return new Result(Status.Available, version);
                    case "installed": return new Result(Status.Installed, version);
                    default: return default(Result);
                }
            } catch (ArgumentException) { return default(Result); }
            catch (InvalidOperationException) { return default(Result); }
        });
    }

    internal static Task<bool> RestartExplorerAsync(string directory) {
        return Task.Run(() => RunUpdater(directory, "restart-explorer", RestartTimeoutMilliseconds) != null);
    }

    private static string RunUpdater(string directory, string arguments, int timeout) {
        try {
            var installedVersion = Registry.GetValue(@"HKEY_CURRENT_USER\Software\AgentMeterTaskbar", "Version", null) as string;
            Version version;
            if (!Version.TryParse(installedVersion, out version) || version.Build < 0 || version.Revision >= 0) return null;
            string updater = Path.Combine(directory, "AgentMeterUpdater-" + version + ".exe");
            using (Process process = Process.Start(new ProcessStartInfo {
                FileName = updater,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true
            })) {
                if (process == null) return null;
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                if (!process.WaitForExit(timeout) || process.ExitCode != 0) return null;
                return output.GetAwaiter().GetResult();
            }
        } catch (Win32Exception) { return null; }
        catch (IOException) { return null; }
        catch (InvalidOperationException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        catch (System.Security.SecurityException) { return null; }
    }

    private static Version ReadRunningVersion() {
        var attribute = (AssemblyInformationalVersionAttribute)Attribute.GetCustomAttribute(
            typeof(ToolbarUpdater).Assembly, typeof(AssemblyInformationalVersionAttribute));
        Version version;
        return attribute != null && Version.TryParse(attribute.InformationalVersion, out version) ? version : null;
    }
}
