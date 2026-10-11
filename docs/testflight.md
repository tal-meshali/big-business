# Getting the iOS build onto TestFlight

From a Godot export to testers' phones. The Godot side is `client/export_presets.cfg` (preset "iOS") and `tools/ios-export.sh`; the rest happens in Xcode, the Apple Developer portal and App Store Connect. Apple renames menus from time to time; where this guide is unsure of a current name it says so.

## 1. Prerequisites

1. **Apple Developer Program**: a paid membership (99 USD a year), enrolled by you at developer.apple.com with your own Apple ID. The free personal team that runs debug builds on your iPhone cannot upload to App Store Connect. After enrolling, check the Team ID on the Membership page; it must match `application/app_store_team_id` in the iOS preset (`K6X8PQ2VZN` today).
2. **Final bundle id**: `com.talmeshali.bigbusiness` is a placeholder. Pick the permanent one now; it cannot change after the first upload. Set it in both presets (`application/bundle_identifier` for iOS, `package/unique_name` for Android) and in the server's `APPLE_BUNDLE_ID` (`docs/deploy.md`, Social sign-in).
3. **Deployed server**: done. The server runs at `https://big-business-server.fly.dev` (`docs/deploy.md`, Fly.io), and `SERVER_ADDRESS` / `SERVER_KEY` in `client/scripts/game/app_info.gd` already point at it, so testers connect there without typing anything.
4. **Support email and privacy policy URL**: fill `SUPPORT_EMAIL` and `PRIVACY_URL` in `client/scripts/game/app_info.gd`. The Help screen shows them, and App Store Connect asks for a privacy policy URL and a feedback email for external testing.
5. **Xcode** 26.6 is installed. In Xcode, Settings, Accounts, add the Apple ID that holds the paid membership.

## 2. App ID and app record

1. **App ID** (developer.apple.com, Certificates, Identifiers & Profiles, Identifiers, "+"): type App IDs, then App. Description "Big Business", Bundle ID "Explicit" with the final bundle id. Tick Sign in with Apple only when the native Apple sign-in plugin is added (`docs/TODO-local.md` E); capabilities can be added later. Xcode's automatic signing can also create the App ID on first archive, but registering it yourself makes the next step simpler.
2. **App record** (appstoreconnect.apple.com, Apps, "+", New App):
   - Platforms: iOS.
   - Name: "Big Business" (must be unique on the store; if it is taken, add a word, for example "Big Business: Startups". The name under the home-screen icon stays as set in Godot).
   - Primary language: English (U.S.), or the language the store page is written in.
   - Bundle ID: pick the App ID from step 1 in the dropdown.
   - SKU: any private string you will recognise, for example `bigbusiness-ios`.
   - User access: Full Access.
3. Nothing else on the app record is needed for internal TestFlight testing.

## 3. Version and build numbers

In `client/export_presets.cfg`, preset "iOS" (`[preset.1.options]`):

1. `application/short_version` is the version players see (`CFBundleShortVersionString`, today `0.1.0`). Keep it equal to `config/version` in `client/project.godot`, which the app shows as its version.
2. `application/version` is the build number (`CFBundleVersion`, today `1`).
3. **Every upload needs a new build number** for the same version: App Store Connect refuses a duplicate. Bump `application/version` (2, 3, ...) before each export. When `short_version` goes up, the build number may restart, but always increasing is simplest.

## 4. Export, archive and upload

1. **Export a release project.** `tools/ios-export.sh` exports with `--export-debug`, which is right for running on your phone from Xcode but puts the debug engine library in the project. For TestFlight, run the same export as release:

   ```
   ~/Applications/Godot.app/Contents/MacOS/Godot --headless --path client --export-release "iOS" ../build/ios/BigBusiness.ipa
   ```

   With `export_project_only=true` this writes `build/ios/BigBusiness.xcodeproj` and does not build an `.ipa`. The script's x86_64 simulator `ARCHS` edit only affects simulator builds, so it is not needed here (and harmless if present).
2. **Open** `build/ios/BigBusiness.xcodeproj` in Xcode.
3. **Signing**: select the BigBusiness project, target BigBusiness, Signing & Capabilities. Tick "Automatically manage signing", Team: your paid team (not "(Personal Team)"). Check the Bundle Identifier is the final one. Xcode creates the distribution certificate and provisioning profile itself.
4. **Destination**: in the toolbar's run destination menu choose "Any iOS Device (arm64)". Archive is greyed out while a simulator is selected.
5. **Archive**: Product, Archive. The Organizer opens with the new archive when it finishes.
6. **Upload**: in the Organizer select the archive, Distribute App, choose App Store Connect (in recent Xcode versions the option may be labelled "App Store Connect" or "TestFlight & App Store"; pick the one that uploads), then Upload. Keep the defaults (upload symbols, automatic signing) and confirm.
7. Re-exporting from Godot overwrites the Xcode project, so redo step 3 after every export unless the team is already right (the preset's team id carries over).

## 5. Export compliance

Apple asks whether the app uses encryption. Big Business only uses HTTPS and WSS through the system's TLS, which is exempt, so the answer is "no non-exempt encryption".

1. **Godot 4.6.3 already writes the key.** The exported `build/ios/BigBusiness/BigBusiness-Info.plist` contains `ITSAppUsesNonExemptEncryption` set to `false`, so App Store Connect should not show the question. Check that file after each export.
2. Do **not** add the key again through `application/additional_plist_content`: the plist would then hold it twice. Only if a future Godot version stops writing it, append it to the existing value:

   ```
   application/additional_plist_content="<key>NSLocalNetworkUsageDescription</key><string>Connect to a Big Business server on your local network.</string><key>ITSAppUsesNonExemptEncryption</key><false/>"
   ```

3. If a build still shows "Missing Compliance" in TestFlight, open the build and answer the encryption question by hand (none / exempt standard encryption). It applies to that build only.

## 6. TestFlight

1. **Processing**: after the upload, the build appears in App Store Connect, your app, TestFlight, usually within 5 to 30 minutes (sometimes longer). Apple emails you when it is ready, or when it is rejected with an ITMS error.
2. **Internal testers** (no review): people on your App Store Connect team, up to 100. Add them in Users and Access first (any role works; they accept an email invitation), then in TestFlight create an internal group, add them, and add the build to the group. "Automatic distribution" sends every new build to the group.
3. **External testers** (anyone with an email address or a public link, up to 10,000): create an external group and add the build. The first build of each version goes through Beta App Review (often a day or less). Before submitting, fill Test Information: beta app description, feedback email (use `SUPPORT_EMAIL`), contact details, privacy policy URL, and sign-in information. Big Business signs in as a guest, so say no sign-in is required. Reviewers need the deployed server running.
4. **Installing**: testers install the TestFlight app from the App Store, then open the invitation email (or the public link) on the iPhone and tap Accept or Install. Updates arrive in the TestFlight app. Builds expire 90 days after upload.
5. Testers send screenshots and comments from the TestFlight app; they appear under TestFlight, Feedback in App Store Connect.

## 7. Common failures

- **Missing or invalid 1024 icon**: the App Store icon must be 1024x1024 PNG with no alpha channel. `client/icons/icon_1024.png` is 1024 px and has no alpha today (`sips -g hasAlpha client/icons/icon_1024.png` prints `no`). If a new icon has alpha, flatten it: `sips -s format jpeg icon.png --out /tmp/i.jpg && sips -s format png /tmp/i.jpg --out icon_1024.png`. The preset's `icons/icon_1024x1024` must point at it.
- **Missing Compliance** on a build: see section 5; answer it in the build's page or check the plist key.
- **Invalid bundle id / no matching app record** at upload: the bundle id in Xcode must match the App ID and the app record exactly (case included). Fix `application/bundle_identifier`, re-export, re-archive.
- **Signing or provisioning errors** ("No profiles for ... were found", "requires a development team"): in Signing & Capabilities pick the paid team, keep automatic signing on, and make sure Xcode, Settings, Accounts shows the membership. A profile left over from the personal team can be cleared with "Download Manual Profiles" or by removing and re-adding the account. "Communication with Apple failed" usually means the App ID is not registered under the paid team (section 2, step 1).
- **Duplicate build number** ("bundle version must be higher"): bump `application/version` (section 3) and export again.
- **ITMS-90683 missing purpose string**: Godot always writes `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`, empty unless set, and Xcode warns about them. Leaving the preset options empty does not remove the keys; it only leaves them empty, which Apple can reject. Fill them in the iOS preset:

  ```
  privacy/camera_usage_description="Big Business does not use the camera."
  privacy/microphone_usage_description="Big Business does not use the microphone."
  ```

  `privacy/photolibrary_usage_description` is already set for Designer. If a later feature uses the camera or microphone, replace the sentence with what it does.
- **Archive greyed out**: a simulator is selected; choose "Any iOS Device (arm64)".
- **Testers cannot connect**: the build still points at the local default. Check `SERVER_ADDRESS` and `SERVER_KEY` in `app_info.gd` before exporting, and that `curl https://<domain>/` answers.
