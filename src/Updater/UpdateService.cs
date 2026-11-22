using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using Microsoft.Win32;

internal static class UpdateService {
    private const string RegistryPath = @"Software\AgentMeterTaskbar";
    private const string ReleaseBase = "https://github.com/rrokot/AgentMeter-Taskbar/releases";
    private const string ManifestFile = "agentmeter-update.json";
    private const string PublicKeyFile = "update-public.xml";

    internal enum Mode { Automatic, Check, Install }
    internal enum Status { Busy, Current, Available, Installed }

    internal sealed class Result {
        public Status Outcome { get; private set; }
        public Version Version { get; private set; }

        internal Result(Status outcome, Version version) {
            Outcome = outcome;
            Version = version;
        }
    }

    internal static Result Run(string directory, Mode mode, Version targetVersion, Action<Uri, string, int> download) {
        using (var updateLock = OpenUpdateLock(Path.Combine(directory, "updates.lock"))) {
            if (updateLock == null) return new Result(Status.Busy, null);

            string temporaryDirectory = Path.Combine(Path.GetTempPath(), "AgentMeterUpdate-" + Guid.NewGuid().ToString("N"));
            string manifestPath = Path.Combine(temporaryDirectory, ManifestFile);
            string installerPath = Path.Combine(temporaryDirectory, "AgentMeter-Setup.exe");
            try {
                var installedVersion = ReadInstalledVersion();
                Directory.CreateDirectory(temporaryDirectory);
                download(new Uri(ReleaseBase + "/latest/download/" + ManifestFile), manifestPath, 30);
                var release = UpdateManifest.Read(manifestPath, Path.Combine(directory, PublicKeyFile));
                if (release.Version <= installedVersion) return new Result(Status.Current, installedVersion);
                if (mode == Mode.Check || (mode == Mode.Install && release.Version != targetVersion)) {
                    return new Result(Status.Available, release.Version);
                }

                string releaseName = "v" + release.Version;
                var installerUri = new Uri(ReleaseBase + "/download/" + releaseName +
                    "/AgentMeter-Taskbar-Setup-" + releaseName + ".exe");
                download(installerUri, installerPath, 90);
                release.VerifyInstaller(installerPath);
                installedVersion = ReadInstalledVersion();
                if (release.Version <= installedVersion) return new Result(Status.Current, installedVersion);

                Install(installerPath);
                if (ReadInstalledVersion() != release.Version) {
                    throw new InvalidOperationException("Setup did not register the expected version.");
                }
                WriteLog(directory, "Installed " + release.Version);
                return new Result(Status.Installed, release.Version);
            } finally {
                TryDelete(manifestPath);
                TryDelete(installerPath);
                TryDeleteDirectory(temporaryDirectory);
            }
        }
    }

    internal static void Download(Uri url, string path, int timeoutSeconds) {
        var elapsed = Stopwatch.StartNew();
        bool isManifest = Path.GetFileName(path) == ManifestFile;
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        var request = (HttpWebRequest)WebRequest.Create(url);
        request.UserAgent = "AgentMeter-Taskbar";
        request.Timeout = timeoutSeconds * 1000;
        request.ReadWriteTimeout = timeoutSeconds * 1000;
        using (var response = request.GetResponse())
        using (var network = response.GetResponseStream())
        using (var file = File.Create(path)) {
            var buffer = new byte[8192];
            int count;
            while ((count = network.Read(buffer, 0, buffer.Length)) != 0) {
                if (elapsed.Elapsed.TotalSeconds > timeoutSeconds) throw new TimeoutException("Update download timed out.");
                if (isManifest && file.Length + count > UpdateManifest.MaximumBytes) {
                    throw new InvalidDataException("Update manifest is too large.");
                }
                file.Write(buffer, 0, count);
            }
        }
    }

    internal static void WriteLog(string directory, string message) {
        try {
            string path = Path.Combine(directory, "updates.log");
            if (File.Exists(path) && new FileInfo(path).Length > 65536) File.Delete(path);
            File.AppendAllText(path, DateTimeOffset.Now.ToString("o", CultureInfo.InvariantCulture) +
                " " + message + Environment.NewLine);
        } catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static Version ReadInstalledVersion() {
        Version version;
        var text = Registry.GetValue(@"HKEY_CURRENT_USER\" + RegistryPath, "Version", null) as string;
        if (!UpdateManifest.TryParseVersion(text, out version)) {
            throw new InvalidOperationException("AgentMeter is not installed for this user.");
        }
        return version;
    }

    private static void Install(string executable) {
        using (var process = Process.Start(new ProcessStartInfo {
            FileName = executable,
            Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-",
            UseShellExecute = false,
            CreateNoWindow = true
        })) {
            process.WaitForExit();
            if (process.ExitCode != 0) {
                throw new InvalidOperationException("AgentMeter Setup returned exit code " + process.ExitCode + ".");
            }
        }
    }

    private static FileStream OpenUpdateLock(string path) {
        try {
            return new FileStream(path, FileMode.OpenOrCreate, FileAccess.Write, FileShare.None);
        } catch (IOException error) {
            const int SharingViolation = unchecked((int)0x80070020);
            if (error.HResult != SharingViolation) throw;
            return null;
        }
    }

    private static void TryDelete(string path) {
        try { File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void TryDeleteDirectory(string path) {
        try { Directory.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
