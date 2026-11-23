using System;
using System.Globalization;
using Microsoft.Win32;

internal static partial class InstallationLayout {
    internal static Version ReadInstalledVersion() {
        var text = Registry.GetValue(@"HKEY_CURRENT_USER\" + RegistrySubKey, RegistryVersionValueName, null) as string;
        Version version;
        if (!Version.TryParse(text, out version) || version.Build < 0 || version.Revision >= 0 || version.ToString() != text) {
            throw new InvalidOperationException("AgentMeter is not installed for this user.");
        }
        return version;
    }

    internal static string UpdaterFileNameFor(Version version) {
        return string.Format(CultureInfo.InvariantCulture, UpdaterFileName, version);
    }
}
