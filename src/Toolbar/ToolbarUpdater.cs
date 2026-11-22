using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

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
            string arguments = targetVersion == null ? "-Mode Check" : "-Mode Install -TargetVersion " + targetVersion;
            int timeout = targetVersion == null ? CheckTimeoutMilliseconds : InstallTimeoutMilliseconds;
            string output = RunScript(directory, "UpdateAgentMeter.ps1", arguments, timeout);
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
        return Task.Run(() => RunScript(directory, "RestartExplorer.ps1", "-Quiet", RestartTimeoutMilliseconds) != null);
    }

    private static string RunScript(string directory, string name, string arguments, int timeout) {
        string script = Path.Combine(directory, name);
        if (!File.Exists(script)) return null;
        string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
        try {
            using (Process process = Process.Start(new ProcessStartInfo {
                FileName = powershell,
                Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" " + arguments,
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
    }

    private static Version ReadRunningVersion() {
        var attribute = (AssemblyInformationalVersionAttribute)Attribute.GetCustomAttribute(
            typeof(ToolbarUpdater).Assembly, typeof(AssemblyInformationalVersionAttribute));
        Version version;
        return attribute != null && Version.TryParse(attribute.InformationalVersion, out version) ? version : null;
    }
}
