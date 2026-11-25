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
DefaultDirName={localappdata}\{#InstallDirectoryName}
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
#ifdef InstallTestFixture
OutputBaseFilename=AgentMeter-Taskbar-Setup-TestFixture-v{#AppVersion}
#else
OutputBaseFilename=AgentMeter-Taskbar-Setup-v{#AppVersion}
#endif
Compression=lzma2
SolidCompression=yes

[Files]
Source: "{#BuildDirectory}\{#ToolbarFileName}"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist uninsrestartdelete
Source: "{#BuildDirectory}\{#CollectorFileName}"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist uninsrestartdelete
Source: "{#BuildDirectory}\{#UpdaterFileName}"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist uninsrestartdelete
Source: "InstallationLayout.psd1"; DestDir: "{app}"; Flags: ignoreversion
Source: "ManageInstallation.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "ClaudeConnection.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Updater\update-public.xml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"
Source: "..\NOTICE-AgentMeter.txt"; DestDir: "{app}"

[Icons]
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
#ifndef InstallTestFixture
const
  RebarGetBandCount = $040C;
  AbortIfHung = $0002;
  ProbeTimeoutMilliseconds = 500;

{ Inno Setup 6 scripts run in a 32-bit process even in 64-bit install mode. }
function FindChildWindow(Parent, PreviousChild: HWND; ClassName: String; WindowName: Cardinal): HWND;
  external 'FindWindowExW@user32.dll stdcall';

function QueryWindow(Wnd: HWND; Msg, WParam: Cardinal; LParam: LongInt;
  Flags, TimeoutMilliseconds: Cardinal; var Reply: Cardinal): LongInt;
  external 'SendMessageTimeoutW@user32.dll stdcall';

function HasClassicTaskbarHost: Boolean;
var
  Taskbar, BandContainer: HWND;
  BandCount: Cardinal;
begin
  Result := False;
  Taskbar := FindWindowByClassName('Shell_TrayWnd');
  if Taskbar = 0 then
    Exit;

  { Explorer's classic rebar contains the Win32 task switcher and hosts DeskBand toolbars. }
  BandContainer := FindChildWindow(Taskbar, 0, 'ReBarWindow32', 0);
  if BandContainer = 0 then
    Exit;
  if FindChildWindow(BandContainer, 0, 'MSTaskSwWClass', 0) = 0 then
    Exit;

  BandCount := 0;
  Result := (QueryWindow(BandContainer, RebarGetBandCount, 0, 0, AbortIfHung, ProbeTimeoutMilliseconds, BandCount) <> 0)
    and (BandCount > 0);
end;
#endif

function InitializeSetup: Boolean;
begin
#ifdef InstallTestFixture
  Result := True;
#else
  Result := HasClassicTaskbarHost;
  if not Result then
  begin
    Log('No DeskBand-compatible taskbar was detected.');
    SuppressibleMsgBox(
      'AgentMeter Taskbar needs a classic taskbar that supports DeskBand toolbars. Enable a compatible taskbar and run Setup again.',
      mbError, MB_OK, IDOK);
  end;
#endif
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  InstalledVersion: String;
  InstalledVersionNumber, SetupVersionNumber: Int64;
begin
  Result := '';
  if CompareText(ExpandConstant('{app}'), ExpandConstant('{localappdata}\{#InstallDirectoryName}')) <> 0 then
    Result := 'Install AgentMeter Taskbar in its default local application directory.'
  else if RegQueryStringValue(HKCU, '{#ProductRegistrySubKey}', '{#RegistryVersionValueName}', InstalledVersion) and
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
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments,
    ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ExitCode) and (ExitCode = 0);
  if not Result then
    Log('AgentMeter ' + Action + ' integration returned ' + IntToStr(ExitCode));
end;

procedure RestartExplorerAfterSetup;
var
  ExitCode: Integer;
begin
  if not Exec(ExpandConstant('{app}\{#UpdaterFileName}'), 'restart-explorer-after-setup',
    ExpandConstant('{app}'), SW_HIDE, ewNoWait, ExitCode) then
  begin
    Log('Could not start the Explorer restart helper: ' + IntToStr(ExitCode));
    SuppressibleMsgBox('AgentMeter is installed. Restart Windows Explorer to load the new toolbar.',
      mbInformation, MB_OK, IDOK);
  end;
end;

procedure CurStepChanged(Step: TSetupStep);
begin
  if Step = ssPostInstall then
    if not RunInstallationAction('Install') then
      RaiseException('Could not register AgentMeter Taskbar with Windows.');
  if (Step = ssDone) and not WizardSilent then
    RestartExplorerAfterSetup;
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
      'Windows Explorer will restart when you finish Setup. This can close open Explorer windows.';
end;
