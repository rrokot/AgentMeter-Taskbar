#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildDirectory
  #error BuildDirectory is required
#endif
#ifndef OutputDirectory
  #error OutputDirectory is required
#endif

[Setup]
AppId={{B8D2F322-40F2-4265-8551-1E9417B52FDD}
AppName=AgentMeter Taskbar
AppVersion={#AppVersion}
AppPublisher=rrokot
AppPublisherURL=https://github.com/rrokot/AgentMeter-Taskbar
AppSupportURL=https://github.com/rrokot/AgentMeter-Taskbar/issues
AppUpdatesURL=https://github.com/rrokot/AgentMeter-Taskbar/releases/latest
DefaultDirName={localappdata}\AgentMeterTaskbar
DefaultGroupName=AgentMeter Taskbar
UninstallDisplayName=AgentMeter Taskbar
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.22000
DisableDirPage=yes
DisableProgramGroupPage=yes
CloseApplications=no
RestartApplications=no
RestartIfNeededByRun=no
SetupMutex=AgentMeterTaskbarInstaller
WizardStyle=modern
OutputDir={#OutputDirectory}
OutputBaseFilename=AgentMeter-Taskbar-Setup-v{#AppVersion}
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: "autoupdate"; Description: "Install verified updates automatically"
Name: "claudecode"; Description: "Connect Claude Code if it has no custom status line"; Flags: unchecked

[Files]
Source: "{#BuildDirectory}\AgentMeterBand-{#AppVersion}.dll"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist uninsrestartdelete
Source: "..\src\QuotaData.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\ClaudeStatusLine.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\RefreshQuota.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\RefreshQuota.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "ManageInstallation.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "ClaudeConnection.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "UpdateAgentMeter.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "update-public.xml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"
Source: "..\NOTICE-AgentMeter.txt"; DestDir: "{app}"

[Icons]
Name: "{group}\Check for updates"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\UpdateAgentMeter.ps1"" -Interactive"; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 239
Name: "{group}\Setup guide"; Filename: "https://github.com/rrokot/AgentMeter-Taskbar#install"
Name: "{group}\Uninstall AgentMeter Taskbar"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: files; Name: "{app}\data.json"
Type: files; Name: "{app}\claude-usage.json"
Type: files; Name: "{app}\collector.lock"
Type: files; Name: "{app}\claude-usage.lock"
Type: files; Name: "{app}\updates.lock"
Type: files; Name: "{app}\updates.log"

[Code]
function InitializeSetup: Boolean;
var
  LegacyTaskbar: Cardinal;
begin
  Result := RegQueryDWordValue(HKCU, 'Software\StartIsBack', 'LegacyTaskbar', LegacyTaskbar) and
    (LegacyTaskbar = 1);
  if not Result then
    SuppressibleMsgBox('Enable the classic taskbar in StartAllBack before installing AgentMeter Taskbar.',
      mbError, MB_OK, IDOK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  InstalledVersion: String;
  InstalledVersionNumber, SetupVersionNumber: Int64;
begin
  Result := '';
  if CompareText(ExpandConstant('{app}'), ExpandConstant('{localappdata}\AgentMeterTaskbar')) <> 0 then
    Result := 'Install AgentMeter Taskbar in its default local application directory.'
  else if RegQueryStringValue(HKCU, 'Software\AgentMeterTaskbar', 'Version', InstalledVersion) and
    StrToVersion(InstalledVersion, InstalledVersionNumber) and
    StrToVersion('{#AppVersion}', SetupVersionNumber) and
    (ComparePackedVersion(InstalledVersionNumber, SetupVersionNumber) > 0) then
    Result := 'A newer version of AgentMeter Taskbar is already installed.';
end;

function RunInstallationAction(const Action: String): Boolean;
var
  Arguments: String;
  ExitCode: Integer;
begin
  Arguments := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\ManageInstallation.ps1') + '" -Operation ' + Action +
    ' -ProductVersion {#AppVersion}';
  if (Action = 'Install') and WizardIsTaskSelected('autoupdate') then
    Arguments := Arguments + ' -AutomaticUpdates';
  if (Action = 'Install') and WizardIsTaskSelected('claudecode') then
    Arguments := Arguments + ' -ConnectClaude';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments,
    ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ExitCode) and (ExitCode = 0);
  if not Result then
    Log('AgentMeter ' + Action + ' integration returned ' + IntToStr(ExitCode));
end;

procedure CurStepChanged(Step: TSetupStep);
begin
  if Step = ssPostInstall then
    if not RunInstallationAction('Install') then
      RaiseException('Could not register AgentMeter Taskbar with Windows.');
end;

function InitializeUninstall: Boolean;
begin
  Result := RunInstallationAction('Uninstall');
  if not Result then
    SuppressibleMsgBox('Could not unregister AgentMeter Taskbar. Run the uninstaller again after signing out and back in.',
      mbError, MB_OK, IDOK);
end;

procedure CurPageChanged(PageID: Integer);
begin
  if PageID = wpFinished then
    WizardForm.FinishedLabel.Caption :=
      'AgentMeter Taskbar is installed. Right-click the classic taskbar and choose Toolbars > AgentMeter Quotas. ' +
      'Windows loads updated toolbar code the next time Explorer starts.';
end;
