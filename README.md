# AgentMeter Taskbar

Windows taskbar toolbar for Claude Code and Codex usage limits. It shows the five-hour and weekly windows for each service and reveals usage and reset times on hover.

[Документация на русском](docs/README.ru.md)

![The AgentMeter taskbar bars and quota popup in the dark Windows theme](docs/taskbar-preview.png)

## Install

Use Windows 11 x64 with the classic taskbar enabled in StartAllBack. The installer runs under 64-bit Windows PowerShell and builds the toolbar with the .NET Framework compiler included with Windows.

1. Extract the ZIP from [GitHub Releases](https://github.com/rrokot/AgentMeter-Taskbar/releases/latest) and open Windows PowerShell in the extracted folder.
2. Run the installer. This execution policy applies to the PowerShell process started by the command.

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   ```

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

Run `Install.ps1` again from a newer release. Restart Windows Explorer or sign out and sign back in to load the new toolbar.

To uninstall, turn off **AgentMeter Quotas** in the taskbar menu. If you added AgentMeter to Claude Code, remove that status-line entry or remove it from your own script. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

If Windows Explorer still has the DLL open, sign out and back in, then rerun the uninstaller.

## Development

Run the tests from Windows PowerShell 5.1 with Pester 3.4. The tests compile the toolbar and use local quota fixtures.

```powershell
powershell.exe -NoProfile -Command "Invoke-Pester .\tests -EnableExit"
```

AgentMeter Taskbar is distributed under the [MIT License](LICENSE). Parts of the project originated in [AgentMeter v0.2.0](https://github.com/fabianramirez-code/AgentMeter/tree/v0.2.0). Its MIT notice is included in [NOTICE-AgentMeter.txt](NOTICE-AgentMeter.txt).
