# NotiShift

NotiShift is a native macOS menu bar app for repositioning system notification banners.

It uses the macOS Accessibility API to observe Notification Center windows and move the
window that contains the active notification banner. This is the same broad approach used
by PingPlace, with additional compatibility layers for older macOS versions.

## Build

```sh
make build
```

The installable app bundle is generated at:

```text
dist/NotiShift.app
```

The distributable archive is generated at:

```text
dist/NotiShift.app.tar.gz
```

## First Run

Because this build is ad-hoc signed, macOS may require users to right-click the app and
choose Open the first time. NotiShift also requires Accessibility permission:

System Settings -> Privacy & Security -> Accessibility -> NotiShift

For local testing:

1. Build with `make package`.
2. Open `dist/NotiShift.app`, or move it to `/Applications` first.
3. If macOS blocks the first launch, right-click `NotiShift.app` and choose Open.
4. Grant Accessibility permission when prompted.
5. Use the menu bar bell icon to choose a notification position.
6. Choose `Send System Notification` from the menu and verify the macOS notification banner appears at the selected position.

If a macOS version does not work, use the menu item:

```text
Export Diagnostics
```

and inspect the generated text file.

## Distribution Notes

This repository currently builds an ad-hoc signed app. It is suitable for local testing,
but Gatekeeper will not treat it as a trusted public download. A fully smooth public
download requires Apple Developer ID signing and notarization.

## Updates

NotiShift checks GitHub Releases for new versions and opens the release page when an
update is available. It does not download, install, or replace the app automatically.

Release tags should use semantic versions with a leading `v`, for example:

```text
v0.1.1
```

Attach `NotiShift.app.tar.gz` to the GitHub release and include the SHA256 checksum in
the release notes or as a separate `.sha256` asset.

## Compatibility

The app is designed with multiple detection strategies:

- Notification Center process resolution by bundle id, process name, and CGWindow owner.
- AXObserver events for window creation and children changes.
- Polling fallback.
- Exact banner subrole detection plus heuristic fallback.
- Diagnostics export for version-specific compatibility fixes.

## Multiple Displays

NotiShift keeps notification banners on the display where macOS creates the
notification window, then applies the selected position within that display's visible
frame. The Preferences status summary and diagnostics summary include the number of
detected displays to make multi-display reports easier to interpret.
