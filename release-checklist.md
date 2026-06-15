# Framwise Release Checklist

This checklist covers Developer ID / DMG distribution for Framwise. Run it on the notarized DMG produced by `scripts/release/build_dmg.sh`.

Distribution shape: Developer ID DMG, non-sandbox. Framwise does not currently implement security-scoped bookmarks, so App Store or sandbox distribution must be planned separately before enabling `com.apple.security.app-sandbox`.

## 1. Build And Notarize

Scenario: Produce a reproducible release artifact.

Steps:
1. Configure the local notarytool profile once:
   ```bash
   xcrun notarytool store-credentials framwise-notary
   ```
2. Build the DMG:
   ```bash
   FRAMWISE_TEAM_ID=XXXXXXXXXX \
   FRAMWISE_NOTARY_PROFILE=framwise-notary \
   scripts/release/build_dmg.sh
   ```

Expected result:
- The script exits successfully.
- The final artifact is `build/release/Framwise-<version>-<build>.dmg`.
- The script confirms the exported app version and build match `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- The script confirms the exported app minimum macOS version matches `MACOSX_DEPLOYMENT_TARGET`.
- The script confirms the exported app executable contains both `arm64` and `x86_64` slices.
- The script confirms the app executable does not link against local `/Users`, `/opt/homebrew`, or `/usr/local` dynamic libraries.
- The script confirms the exported app is not sandboxed.
- The script prints a SHA256 checksum.
- `stapler validate` and `spctl` checks pass.

## 2. Gatekeeper First Launch

Scenario: Simulate a downloaded DMG on another Mac.

Steps:
1. Add quarantine to the DMG:
   ```bash
   xattr -w com.apple.quarantine "0081;$(date +%s);Safari;Framwise" build/release/Framwise-<version>-<build>.dmg
   ```
2. Double-click the DMG in Finder.
3. Launch Framwise from the mounted image.

Expected result:
- Gatekeeper does not show an "unidentified developer" block.
- Framwise opens the main window on first launch.

## 3. Applications Folder Launch

Scenario: Verify normal user installation.

Steps:
1. Drag `Framwise.app` from the mounted DMG to `/Applications`.
2. Launch `/Applications/Framwise.app`.
3. Quit and launch it again.

Expected result:
- The app starts both times without Gatekeeper or signature warnings.
- No data is written inside `Framwise.app`.

## 4. Core Video Workflow

Scenario: Verify Hardened Runtime does not block AVFoundation workflows.

Steps:
1. Import a local video file.
2. Import a folder containing multiple supported video files.
3. Wait for clip analysis and thumbnail generation.
4. Open a clip preview.
5. Select one or more clips and export EDL or FCPXML.
6. Try a zero-byte `.mov`, a renamed non-video file with a video extension, and a video encoded with a codec unavailable on the test Mac.

Expected result:
- Import, analysis, thumbnails, preview, and export all complete without runtime security errors.
- Failures for unsupported or inaccessible files are visible in the UI.
- Media that has no video track, invalid duration, or no decodable frames is skipped with an import error/warning instead of creating a successful empty clip.
- Rapidly switching filters or clearing the session while thumbnails are loading does not leave stale thumbnails, obsolete progress, or a stuck loading state.

## 5. File Access Restore

Scenario: Verify the non-sandbox release can restore user-selected media across launches.

Steps:
1. Install the notarized app in `/Applications`.
2. Import videos from Desktop, Downloads, and Documents.
3. Import a folder from an external drive or SD card.
4. Import a folder from a mounted SMB or network volume.
5. Wait for thumbnails and preview to work.
6. Quit and relaunch Framwise.
7. Open previews and export selected clips from the restored session.

Expected result:
- Previously imported sources restore without requiring Xcode.
- Thumbnails, preview, and export continue to work for still-accessible files.
- Missing or inaccessible files are removed or reported in the UI instead of silently appearing successful.

## 6. Restricted Or Missing Sources

Scenario: Verify inaccessible paths fail visibly and do not hang import.

Steps:
1. Drag in a folder that contains an unreadable child folder.
2. Drag in a folder from a slow or disconnected external/network volume.
3. Import a valid video, quit Framwise, move or delete the source file, then relaunch.

Expected result:
- Accessible videos still import.
- Slow external or network folders show a "Reading sources" state while scanning.
- The main window remains responsive during source scanning.
- Fully inaccessible drops show a clear access error, not a generic "No supported video files found" state.
- Partially inaccessible drops import accessible videos and show a skipped-source warning.
- Moved or deleted restored sources do not crash the app and do not appear as successfully usable clips.
- Relaunch after moved/deleted sources shows "Some restored sources were unavailable" in the workspace/grid.
- Import and folder scanning remain responsive.

## 7. Release Log Privacy

Scenario: Verify release logs do not publicly expose full user paths.

Steps:
1. Launch the notarized app from `/Applications`.
2. Trigger a recoverable file error, such as importing a missing, moved, or inaccessible video file.
3. Inspect Framwise logs in Console.app.

Expected result:
- Public log fields include an error summary with type, domain, and code.
- Public log fields do not include full `/Users/...` paths, private folders, or `NSError.userInfo`.
- File context appears only as a short file or folder reference such as `name#hash`.

## 8. Persistence And Writable Locations

Scenario: Verify the notarized app works from a read-only bundle location.

Steps:
1. Launch the app from `/Applications`.
2. Import footage and create a workspace.
3. Quit Framwise.
4. Relaunch Framwise.
5. Export selected clips to a user-writable folder.

Expected result:
- The previous session is restored or any restore issue is shown in the UI.
- Session data is stored under Application Support.
- Temporary export files are cleaned up after save/cancel.
- The app does not attempt to write into its own `.app` bundle.

## 9. Future Sandbox Guardrail

Scenario: Avoid accidentally shipping a sandboxed build without bookmark support.

Steps:
1. Run `scripts/release/build_dmg.sh` for every release.
2. If App Store or sandbox distribution becomes a goal, stop and implement security-scoped bookmark storage, restoration, stale bookmark refresh, and access lifetime management first.

Expected result:
- The current release script fails if the exported app contains `com.apple.security.app-sandbox = true`.
- Sandbox/App Store work is tracked as a separate engineering change, not a release-script-only switch.

## 10. Clean Mac Compatibility

Scenario: Verify the release behaves on a Mac that is not the developer machine.

Steps:
1. Test on a clean macOS user account with no existing Framwise Application Support folder.
2. Test on Apple Silicon by launching normally from `/Applications`.
3. Test on Intel Mac hardware, or on Apple Silicon through Rosetta if Intel hardware is unavailable.
4. Confirm the test Mac is running macOS 14 or later.

Expected result:
- First launch starts with the empty workspace and no stale session assumptions.
- Import, preview, thumbnail generation, and export work without Xcode, Homebrew, custom fonts, or command line tools installed.
- The app refuses to install or launch only on macOS versions older than the declared minimum.
