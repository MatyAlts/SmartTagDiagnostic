# Build and install

## Local macOS

Install Xcode with an iOS 17-or-later SDK and XcodeGen (`brew install xcodegen`). From the repository:

```sh
python3 scripts/verify_project.py
swift test
xcodegen generate
xcrun simctl list devices available
xcodebuild test -project SmartTagDiagnostic.xcodeproj -scheme SmartTagDiagnostic -destination 'platform=iOS Simulator,id=<available-iPhone-UDID>' CODE_SIGNING_ALLOWED=NO
```

Select a UDID from the actual runtime. UI tests use `-ui-testing`, disabling login and avoiding Samsung requests. Simulator tests cannot establish physical Bluetooth interoperability.

## GitHub Actions

The prepared workflow runs by manual dispatch or pull request after the user publishes this repository. Nothing was pushed or dispatched during creation. It logs Xcode's version, tests the core, generates the project, selects an installed iPhone simulator, tests the app, and archives an unsigned device app. Only the unsigned IPA and simulator test results are uploaded; no signing secrets are needed.

Compilation, simulator tests and visual screenshots remain pending until an authorized macOS run. The installed SDK must support the deployment target, rather than match the phone's exact OS version.

## Signing

Download the `SmartTagDiagnostic-unsigned-needs-signing` artifact and extract the IPA. Sign with your Apple identity using your preferred Windows signing tool, or open the generated project in Xcode, select your team and a unique bundle identifier, then run on the iPhone. The IPA cannot be installed unsigned. Provisioning and Developer Mode requirements depend on your signing method/account.

This app declares no Samsung App Groups. Preserve its `ms-app` callback scheme when re-signing. Re-signing does not establish Samsung's acceptance of the iOS flow. Keep passwords, tokens, tag keys and signing identities out of issues, CI logs and artifacts.

## Physical acceptance

1. Launch; when you later start scanning, check the Bluetooth permission explanation.
2. Start browser login explicitly; confirm return to the app or the reported failure.
3. Select the owned tag. Missing metadata and unsupported cipher must block authentication.
4. Scan, explicitly select a nearby peripheral, and authenticate/read battery.
5. Check wrong proof, interruptions and timeouts; no failed connection may show a successful battery read.
6. Disconnect and sign out; verify saved session removal and cleared state.
7. Review VoiceOver, large text, light/dark and native back navigation; capture real Simulator screenshots.

No live account or hardware acceptance checks were run in this session.
