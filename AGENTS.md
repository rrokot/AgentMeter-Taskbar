# AgentMeter Taskbar

## Project layout

- `src/Toolbar/`, `src/Collector/`, and `src/Updater/` contain the toolbar, quota collector, and installed updater.
- `packaging/` contains the Inno Setup definition and its install and uninstall hooks. The definition maps runtime files from `src/` into the per-user installation directory.
- `build/` contains build entry points. `build/release/` handles update signing and GitHub publication.
- `tests/` contains Pester tests and the Windows CI installation test.

## Code conventions

- Use names that identify the provider, quota period, and units where they matter. Keep array positions for layout and use named periods for quota data.
- Keep setup, build, release, and runtime code in their respective directories. Reuse the production build and entry points in tests.
- Document contracts that are hard to infer from the code, such as COM layouts and persisted snapshot keys.

## Tests

Run the tests in Windows PowerShell 5.1 with Pester 3.4. They compile the toolbar, collector, and updater and use local fixtures.

```powershell
powershell.exe -NoProfile -Command "Invoke-Pester .\tests -EnableExit"
```

Windows CI also tests installation, signed updates, the sign-in update trigger, and uninstall using the current build.

## Releasing product changes

When the user asks to push completed changes to the toolbar, collector, or installer, ship them as a release. If the user explicitly asks for a narrower scope, follow that scope.

1. Bump `VERSION`, commit the changes, and push the release commit to `main`.
2. Run **Windows release** on `main` in GitHub Actions with **Publish the signed installer as the latest release** selected. This builds and tests Setup, signs and verifies the update manifest, and publishes the installer, checksum, and manifest under the matching `v` tag.
3. Confirm the workflow succeeded and the expected release is live. Leave the publish option clear to test the cloud build and signing without changing the public release.

The signing key is the `AGENTMETER_UPDATE_SIGNING_KEY` secret in the `release-signing` GitHub Actions environment. The job receives it only for signing. The verification key is in `src/Updater/update-public.xml`.

Local installation is separate from publishing. When applying a release on the maintainer's Windows PC, run the installed updater, restart Explorer in the current session, and verify it loaded the released toolbar DLL.

## License notices

AgentMeter Taskbar uses the [MIT License](LICENSE). Parts originated in [AgentMeter v0.2.0](https://github.com/fabianramirez-code/AgentMeter/tree/v0.2.0). Its MIT notice is in [NOTICE-AgentMeter.txt](NOTICE-AgentMeter.txt).
