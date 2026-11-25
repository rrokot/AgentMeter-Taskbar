using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class SetupTestDesktop {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo {
        public int Size;
        public string Reserved, Desktop, Title;
        public int X, Y, Width, Height, Columns, Rows, FillAttribute, Flags;
        public short ShowWindow, ReservedLength;
        public IntPtr ReservedBytes, Input, Output, Error;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInfo {
        public IntPtr Process, Thread;
        public int ProcessId, ThreadId;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr deviceMode, uint flags, uint access, IntPtr attributes);

    [DllImport("user32.dll")]
    private static extern bool CloseDesktop(IntPtr desktop);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcess(string application, StringBuilder commandLine, IntPtr processAttributes,
        IntPtr threadAttributes, bool inheritHandles, uint flags, IntPtr environment, string directory, ref StartupInfo startup,
        out ProcessInfo process);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(IntPtr process, out int exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    public static int Run(string installer, string arguments) {
        // Give Setup a desktop with no shell windows, regardless of the runner's taskbar.
        const uint CreateWindow = 0x0002;
        string name = "AgentMeterPrerequisite-" + Guid.NewGuid().ToString("N");
        IntPtr desktop = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, CreateWindow, IntPtr.Zero);
        if (desktop == IntPtr.Zero) throw new Win32Exception();
        try {
            var startup = new StartupInfo { Size = Marshal.SizeOf(typeof(StartupInfo)), Desktop = name, Flags = 1 };
            var commandLine = new StringBuilder("\"" + installer + "\" " + arguments);
            ProcessInfo process;
            if (!CreateProcess(installer, commandLine, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, null, ref startup, out process))
                throw new Win32Exception();
            try {
                uint wait = WaitForSingleObject(process.Process, 30000);
                if (wait == 258) throw new TimeoutException("Setup did not exit on the empty desktop.");
                if (wait != 0) throw new Win32Exception();
                int exitCode;
                if (!GetExitCodeProcess(process.Process, out exitCode)) throw new Win32Exception();
                return exitCode;
            } finally {
                CloseHandle(process.Thread);
                CloseHandle(process.Process);
            }
        } finally {
            CloseDesktop(desktop);
        }
    }
}
