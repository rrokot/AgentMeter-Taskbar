# AgentMeter Taskbar

Windows taskbar toolbar for Claude Code and Codex usage limits. It shows the five-hour and weekly windows for each service and reveals usage and reset times on hover.

[Документация на русском](docs/README.ru.md)

![The AgentMeter taskbar bars and quota popup in the dark Windows theme](docs/taskbar-preview.png)

## Install

Use Windows 11 x64 with the classic taskbar enabled in StartAllBack.

1. Download `AgentMeter-Taskbar-Setup-v*.exe` from [GitHub Releases](https://github.com/rrokot/AgentMeter-Taskbar/releases/latest).
2. Open Setup and follow the wizard. It installs for your Windows account. Windows may show **Unknown publisher** on first launch. Setup also upgrades installations from the original ZIP release.
3. Right-click the taskbar and choose **Toolbars → AgentMeter Quotas**. If it is missing from the menu, sign out of Windows and sign back in.

Codex quotas appear once a local Codex CLI session has recorded rate limits. The collector reads the latest matching entry in the session logs under `CODEX_HOME` or `%USERPROFILE%\.codex`.

### Claude Code setup

Claude Code can send its five-hour and weekly usage to AgentMeter through its [status-line command](https://code.claude.com/docs/en/statusline#rate-limit-usage). The CLI supplies these fields for supported claude.ai plans after the first response in a session.

Run this in Windows PowerShell to produce the settings entry for your installation:

```powershell
$scriptPath = (Join-Path $env:LOCALAPPDATA 'AgentMeterTaskbar\ClaudeStatusLine.ps1').Replace('\', '/')
$command = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
@{ statusLine = @{ type = 'command'; command = $command } } | ConvertTo-Json -Depth 3
```

Add the `statusLine` entry to `%USERPROFILE%\.claude\settings.json` or the settings file in `CLAUDE_CONFIG_DIR`. Merge it with any other settings in the file. If you already have a status-line command, feed the same JSON to the AgentMeter script with `-Quiet` from your existing script to keep its output.

Complete a turn in Claude Code and allow up to one minute for the taskbar to update. AgentMeter displays the latest reported value until its reset time. A value with no reset time is shown for 15 minutes from the status-line update.

## How it works

The bars are ordered Claude Code 5h, Claude Code 7d, Codex 5h, Codex 7d. A gray bar means that usage is unavailable. When both windows increase, the weekly increase takes priority in the animation.

The collector runs once a minute under your Windows user account. Claude Code supplies its quotas through the status line, and AgentMeter reads Codex CLI session files on the same machine. The saved data contains quota values, timestamps, and display status.

## Update or uninstall

Setup enables automatic updates by default. AgentMeter checks GitHub at sign-in and daily, verifies the release signature and installer checksum, and installs newer packages in the background. The toolbar loads the updated DLL the next time Explorer starts. Use **AgentMeter Taskbar → Check for updates** in Start to check on demand, or rerun Setup to change the automatic-update option.

Remove **AgentMeter Taskbar** from **Settings → Apps → Installed apps**. If you added AgentMeter to Claude Code, remove that status-line entry from Claude Code or remove the call from your own script. An Explorer process that has already loaded the toolbar releases it when that process exits.

## Development

Run the tests from Windows PowerShell 5.1 with Pester 3.4. The tests compile the toolbar and use local quota fixtures.

```powershell
powershell.exe -NoProfile -Command "Invoke-Pester .\tests -EnableExit"
```

Windows CI builds the installer and tests setup, upgrade, update preferences, and uninstall. See [the release process](docs/RELEASING.md) for packaging and signing.

AgentMeter Taskbar is distributed under the [MIT License](LICENSE). Parts of the project originated in [AgentMeter v0.2.0](https://github.com/fabianramirez-code/AgentMeter/tree/v0.2.0). Its MIT notice is included in [NOTICE-AgentMeter.txt](NOTICE-AgentMeter.txt).
