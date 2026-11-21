# Release process

Update `VERSION` and run the Windows CI workflow. CI builds the x64 DLL with the .NET Framework compiler and packages it with the pinned Inno Setup compiler. It publishes the tested Setup executable as the `windows-installer` artifact.

Download the artifact from the successful run for the release commit. Create the signed update feed on the maintainer's Windows account:

```powershell
.\packaging\Sign-UpdateFeed.ps1 -Version 0.2.0 -Installer .\AgentMeter-Taskbar-Setup-v0.2.0.exe
```

The script uses a Windows DPAPI-protected key from `%LOCALAPPDATA%\AgentMeterReleaseKeys\update-signing-key.dpapi`. Keep that key outside Git and the release package. Existing installations trust the public key in `packaging/update-public.xml`.

Create a GitHub release for the matching `v` tag and attach both the Setup executable and `agentmeter-update.json`. Publish it as the latest release after verifying the files. The updater verifies the signature and checksum before it launches Setup, and only accepts a higher version.
