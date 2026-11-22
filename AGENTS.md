# AgentMeter Taskbar

## Tests

Run the tests in Windows PowerShell 5.1 with Pester 3.4. They compile the toolbar and use local quota fixtures.

```powershell
powershell.exe -NoProfile -Command "Invoke-Pester .\tests -EnableExit"
```

Windows CI also tests installation, upgrades from a pinned public release, updates at sign-in, and uninstall.

## Releasing product changes

When the user asks to push completed changes to the toolbar, collector, or installer, ship them as a release. If the user explicitly asks for a narrower scope, follow that scope.

1. Bump `VERSION`, commit the changes, and push the release commit to `main`.
2. Run **Windows release** on `main` in GitHub Actions with **Publish the signed installer as the latest release** selected. This builds and tests Setup, signs and verifies the update manifest, and publishes the installer, checksum, and manifest under the matching `v` tag.
3. Confirm the workflow succeeded and the expected release is live. Leave the publish option clear to test the cloud build and signing without changing the public release.

The signing key is the `AGENTMETER_UPDATE_SIGNING_KEY` secret in the `release-signing` GitHub Actions environment. The job receives it only for signing. The verification key is in `packaging/update-public.xml`.

Local installation is separate from publishing. When applying a release on the maintainer's Windows PC, run the installed updater, restart Explorer in the current session, and verify it loaded the released toolbar DLL.

## License notices

AgentMeter Taskbar uses the [MIT License](LICENSE). Parts originated in [AgentMeter v0.2.0](https://github.com/fabianramirez-code/AgentMeter/tree/v0.2.0). Its MIT notice is in [NOTICE-AgentMeter.txt](NOTICE-AgentMeter.txt).
