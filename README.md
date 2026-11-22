# AgentMeter Taskbar

Windows taskbar toolbar for Claude and Codex usage limits. It shows the five-hour and weekly windows for each service and reveals usage, available reset times, and the running toolbar version on hover.

| Quotas on hover | Usage increase |
| --- | --- |
| ![The AgentMeter popup shows Claude and Codex usage, reset times, and the installed version](docs/taskbar-preview.png) | <img src="docs/taskbar-animation.gif" width="50" alt="Five-hour and weekly increases rise over the Claude quota bars"> |

Captured from the running toolbar with sample usage.

## Install

Use Windows 11 x64 with the classic taskbar enabled in StartAllBack.

1. Download `AgentMeter-Taskbar-Setup-v*.exe` from [GitHub Releases](https://github.com/rrokot/AgentMeter-Taskbar/releases/latest).
2. Open Setup and follow the wizard. It installs for your Windows account. Windows may show **Unknown publisher** on first launch. Setup also upgrades installations from the original ZIP release.
3. Right-click the taskbar and choose **Toolbars → AgentMeter Quotas**. If it is missing from the menu, sign out of Windows and sign back in.

## Show your limits

- **Claude Code**. Select **Connect Claude Code** in Setup. Limits appear after Claude Code answers your first request. Setup preserves any custom status line. If you use one, Claude Desktop can supply your limits.
- **Claude Desktop**. Open the app. If the percentages are still missing, open **Settings → Usage** in Claude Desktop.
- **Codex**. Limits appear automatically once a local Codex session reports them.

Allow up to one minute for the taskbar to refresh.

## Read the bars

- **Horizontal taskbar**. Each service has two stacked bars with five-hour usage above weekly usage.
- **Vertical taskbar**. From left to right, the bars are Claude 5h, Claude 7d, Codex 5h, and Codex 7d.
- **Hover over the bars** to see percentages, reset times when available, and the installed version. If both limits for a service increase, the animation shows the weekly increase.

An empty bar can mean 0% usage or missing data. The popup shows which applies. AgentMeter keeps the last known Claude percentages across restarts. A dimmed fill and a **Last known** note with the observation time mark an older value. A Claude reading with no reset time counts as current for 15 minutes.

## Update or uninstall

Automatic updates are on by default. AgentMeter checks at sign-in and once a day. To check now, open **Start → AgentMeter Taskbar → Check for updates**. Restart Windows Explorer to load the new version. Rerun Setup to change the automatic update setting.

To uninstall, open **Settings → Apps → Installed apps → AgentMeter Taskbar**. Setup removes the Claude Code entry it added. If the toolbar is still visible after uninstalling, restart Windows Explorer.

[MIT License](LICENSE)
