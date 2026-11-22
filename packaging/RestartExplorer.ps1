$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using RestartFileTime = System.Runtime.InteropServices.ComTypes.FILETIME;

public static class AgentMeterExplorerRestart {
    [StructLayout(LayoutKind.Sequential)]
    public struct RestartTarget {
        public uint ProcessId;
        public RestartFileTime StartTime;

        public RestartTarget(uint processId, long creationTime) {
            ProcessId = processId;
            StartTime = new RestartFileTime {
                dwLowDateTime = unchecked((int)creationTime),
                dwHighDateTime = (int)(creationTime >> 32)
            };
        }
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    public static extern int RmStartSession(out uint handle, uint flags, StringBuilder key);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    public static extern int RmRegisterResources(uint handle, uint fileCount, string[] files,
        uint processCount, RestartTarget[] processes, uint serviceCount, string[] services);
    [DllImport("rstrtmgr.dll")]
    public static extern int RmShutdown(uint handle, uint flags, IntPtr statusCallback);
    [DllImport("rstrtmgr.dll")]
    public static extern int RmRestart(uint handle, uint flags, IntPtr statusCallback);
    [DllImport("rstrtmgr.dll")]
    public static extern int RmEndSession(uint handle);
}
'@

function Get-DesktopShellProcessId {
    $desktopWindow = [AgentMeterExplorerRestart]::GetShellWindow()
    if ($desktopWindow -eq [IntPtr]::Zero) { return 0 }
    [uint32]$desktopProcessId = 0
    [void][AgentMeterExplorerRestart]::GetWindowThreadProcessId($desktopWindow, [ref]$desktopProcessId)
    return $desktopProcessId
}

function Wait-ForReplacementShell([uint32]$PreviousProcessId) {
    for ($attempt = 0; $attempt -lt 25; $attempt++) {
        $desktopProcessId = Get-DesktopShellProcessId
        if ($desktopProcessId -and $desktopProcessId -ne $PreviousProcessId) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

try {
    $previousShellId = Get-DesktopShellProcessId
    if (!$previousShellId) { return }

    $explorer = Get-Process -Id $previousShellId
    $explorerPath = Join-Path ([Environment]::GetFolderPath('Windows')) 'explorer.exe'
    if ($explorer.SessionId -ne (Get-Process -Id $PID).SessionId -or $explorer.Path -ne $explorerPath) {
        throw 'The desktop shell is not Windows Explorer in this session.'
    }

    $target = [AgentMeterExplorerRestart+RestartTarget]::new($previousShellId, $explorer.StartTime.ToFileTimeUtc())
    [uint32]$restartSession = 0
    $sessionKey = [Text.StringBuilder]::new(33)
    $result = [AgentMeterExplorerRestart]::RmStartSession([ref]$restartSession, 0, $sessionKey)
    if ($result -ne 0) { throw "Restart Manager could not start ($result)." }
    try {
        $result = [AgentMeterExplorerRestart]::RmRegisterResources($restartSession, 0, $null, 1, @($target), 0, $null)
        if ($result -ne 0) { throw "Restart Manager could not register Explorer ($result)." }

        $shutdownOnlyRestartableApplications = 0x10
        $shutdownResult = [AgentMeterExplorerRestart]::RmShutdown($restartSession, $shutdownOnlyRestartableApplications, [IntPtr]::Zero)
        if ($shutdownResult -eq 0 -or $explorer.HasExited) {
            [void][AgentMeterExplorerRestart]::RmRestart($restartSession, 0, [IntPtr]::Zero)
        }
    } finally {
        [void][AgentMeterExplorerRestart]::RmEndSession($restartSession)
    }

    if (Wait-ForReplacementShell $previousShellId) { return }
    if ($explorer.HasExited -and !(Get-DesktopShellProcessId)) {
        Start-Process -FilePath $explorerPath
        if (Wait-ForReplacementShell $previousShellId) { return }
    }
    throw "Windows Explorer did not restart ($shutdownResult)."
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show(
        'AgentMeter is installed. To load the new toolbar, restart Windows Explorer or sign out of Windows and sign back in.',
        'AgentMeter Taskbar')
    exit 1
}
