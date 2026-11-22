using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using RestartFileTime = System.Runtime.InteropServices.ComTypes.FILETIME;

internal static class ExplorerRestart {
    private const uint ShutdownOnlyRegisteredApplications = 0x10;
    private const int ShellStartTimeoutMilliseconds = 5000;

    [StructLayout(LayoutKind.Sequential)]
    private struct RestartTarget {
        internal uint ProcessId;
        internal RestartFileTime StartTime;

        internal RestartTarget(uint processId, long creationTime) {
            ProcessId = processId;
            StartTime = new RestartFileTime {
                dwLowDateTime = unchecked((int)creationTime),
                dwHighDateTime = (int)(creationTime >> 32)
            };
        }
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmStartSession(out uint handle, uint flags, StringBuilder key);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmRegisterResources(uint handle, uint fileCount, string[] files,
        uint processCount, [In] RestartTarget[] processes, uint serviceCount, string[] services);
    [DllImport("rstrtmgr.dll")]
    private static extern int RmShutdown(uint handle, uint flags, IntPtr statusCallback);
    [DllImport("rstrtmgr.dll")]
    private static extern int RmRestart(uint handle, uint flags, IntPtr statusCallback);
    [DllImport("rstrtmgr.dll")]
    private static extern int RmEndSession(uint handle);

    internal static void Run() {
        uint previousShellId = DesktopShellProcessId();
        if (previousShellId == 0) return;

        string explorerPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
        using (var explorer = Process.GetProcessById((int)previousShellId))
        using (var current = Process.GetCurrentProcess()) {
            if (explorer.SessionId != current.SessionId ||
                !string.Equals(explorer.MainModule.FileName, explorerPath, StringComparison.OrdinalIgnoreCase)) {
                throw new InvalidOperationException("The desktop shell is not Windows Explorer in this session.");
            }

            var target = new RestartTarget(previousShellId, explorer.StartTime.ToFileTimeUtc());
            uint session;
            CheckResult(RmStartSession(out session, 0, new StringBuilder(33)), "start Restart Manager");
            int shutdownStatus;
            try {
                CheckResult(RmRegisterResources(session, 0, null, 1, new[] { target }, 0, null), "register Explorer");
                shutdownStatus = RmShutdown(session, ShutdownOnlyRegisteredApplications, IntPtr.Zero);
                if (shutdownStatus == 0 || explorer.HasExited) RmRestart(session, 0, IntPtr.Zero);
            } finally {
                RmEndSession(session);
            }

            if (WaitForReplacementShell(previousShellId)) return;
            if (explorer.HasExited && DesktopShellProcessId() == 0) {
                using (Process.Start(explorerPath)) { }
                if (WaitForReplacementShell(previousShellId)) return;
            }
            throw new InvalidOperationException("Windows Explorer did not restart (" + shutdownStatus + ").");
        }
    }

    private static uint DesktopShellProcessId() {
        IntPtr window = GetShellWindow();
        if (window == IntPtr.Zero) return 0;
        uint processId;
        GetWindowThreadProcessId(window, out processId);
        return processId;
    }

    private static bool WaitForReplacementShell(uint previousShellId) {
        var elapsed = Stopwatch.StartNew();
        while (elapsed.ElapsedMilliseconds < ShellStartTimeoutMilliseconds) {
            uint shellId = DesktopShellProcessId();
            if (shellId != 0 && shellId != previousShellId) return true;
            Thread.Sleep(200);
        }
        return false;
    }

    private static void CheckResult(int status, string action) {
        if (status != 0) throw new InvalidOperationException("Could not " + action + " (" + status + ").");
    }
}
