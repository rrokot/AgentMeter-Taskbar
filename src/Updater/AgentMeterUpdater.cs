using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class AgentMeterUpdater {
    [STAThread]
    private static int Main(string[] args) {
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        bool notifyAboutRestartFailure = args.Length == 1 && args[0] == "restart-explorer-after-setup";
        try {
            if (notifyAboutRestartFailure || (args.Length == 1 && args[0] == "restart-explorer")) {
                ExplorerRestart.Run();
                return 0;
            }
            if (args.Length == 4 && args[0] == "verify-release") {
                var release = UpdateManifest.Read(args[1], Path.Combine(directory, "update-public.xml"));
                if (release.Version.ToString() != args[3]) throw new InvalidDataException("Unexpected release version.");
                release.VerifyInstaller(args[2]);
                return 0;
            }

            Version target = null;
            UpdateService.Mode mode;
            if (args.Length == 1 && args[0] == "automatic") {
                mode = UpdateService.Mode.Automatic;
            } else if (args.Length == 1 && args[0] == "check") {
                mode = UpdateService.Mode.Check;
            } else if (args.Length == 2 && args[0] == "install" && UpdateManifest.TryParseVersion(args[1], out target)) {
                mode = UpdateService.Mode.Install;
            } else {
                return 1;
            }

            var result = UpdateService.Run(directory, mode, target, UpdateService.Download);
            if (mode != UpdateService.Mode.Automatic) {
                Console.WriteLine(new JavaScriptSerializer().Serialize(new Dictionary<string, string> {
                    { "status", result.Outcome.ToString().ToLowerInvariant() },
                    { "version", result.Version == null ? null : result.Version.ToString() }
                }));
            }
            return 0;
        } catch (Exception error) {
            UpdateService.WriteLog(directory, error.Message);
            if (notifyAboutRestartFailure) {
                MessageBox.Show("AgentMeter is installed. Restart Windows Explorer or sign out and back in to load the toolbar.",
                    "AgentMeter Taskbar", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            return 1;
        }
    }
}
