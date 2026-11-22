# AgentMeter Taskbar

## Releasing product changes

When the user asks to push completed changes to the toolbar, collector, or installer, ship them as a release. If the user explicitly asks for a narrower scope, follow that scope.

1. Bump `VERSION`, commit the changes, and push the release commit.
2. Wait for Windows CI to pass on that commit. Publish the tested installer, its SHA-256 checksum, and the signed update manifest under the matching tag. Follow [the release process](docs/RELEASING.md).
3. On the maintainer's Windows PC, run the installed scheduled updater and verify the installed version.
4. Restart Explorer in the current Windows session and verify it loaded the released toolbar DLL.
