# UWB profile and activation audit

## Objective and authorization
Find supported explanations for Cleo's NI timeout, correct demonstrable defects, and deliver a new unsigned iPhone IPA. User explicitly authorized this work on 2026-10-23, including existing MatyAlts GitHub CLI/Actions delivery to MatyAlts/SmartTagDiagnostic. No PR, merge, owner-account requests or device operations from the build host.

This is the next feature record after completed T11. Historical evidence remains in `odd/tasks/iphone-diagnostics.md` / Engram71; that document is unchanged and near its mirror size limit. This feature uses `odd/uwb-profile-audit/tasks`, project `rea projects`, with the full current document mirrored.

## Baseline and constraints
- Branch `fix/uwb-profile-interop` from54e6dea; previous `feat/uwb-iphone-trial` remains the T11 baseline.
- Successful baseline39901089571 atd2201b3:59core+21App+2UI=82native;12Python. User observed exact decrypted35-byte echo, but NI2.0 timeout and no distance.
- Strict TDD enabled by user AGENTS.md. Runners: `swift test`, `xcodebuild test` on macOS Actions; Windows host has no native runner. Tests first, observed native RED before production, then GREEN and triangulation. Python configuration tests are supplemental.
- RDD disabled/unmanaged; no review switch enabled or native review invoked.
- Preserve auth, battery, retry cancellation barrier, canonical CBC/frame/replay validation and private logs. Only live matching NI.distance may yield meters.
- Preserve all owner untracked ZIP/JPG files in docs/. No raw configuration, keys, IV, short addresses or payload dumps in UI/logs.

## Findings and bounded uncertainty
Independent Samsung/source, Apple/primary-doc and native-sequence audits find no demonstrated missing activation command or header/role/vendor/IV mismatch. Apple normative VENDOR_ID is004c; both short-address fields are Uint16 and Apple configuration numbers are LE. Samsung's opaque Android address-array transport does not establish the cross-stack numeric representation. Exact echo is transport evidence, not firmware/radio acceptance.

One scoped premise challenge: equivalent parameters do not establish that SmartTag firmware emits Apple's required MAC messages. Full firmware/over-air evidence and external plugin consumer remain unavailable. No claim that the actual physical timeout cause has been found.

The app's NI watchdog starts before sharing/configuration while BLE ranging starts after ACK: setup can consume measurement budget. Fix these app deadlines without claiming this explains the observed framework removal(.timeout). Add observed sessionDidStartRunning and bounded phase counters/timings.

Address representation trial is an explicit experiment, not a verified fix: retain baseline, tag-only swap, phone-only swap and both. Change only Samsung offsets9–12; preserve Apple input/output numeric meaning, session/vendor/IV/header/timings. Reject effective wire-address collisions. Every trial has the same measurement success criterion.

## Tasks and routes
- [x] U1: Document the independent profile/sequence audit with primary evidence, source limitations and unknowns. Delegated direct: 4+file mapping and broad research. Read-only research completed; report source write follows this tracker. Check exact source links/offsets and distinguish facts, hypotheses and negative-search bounds.
- [x] U2: Implement the bounded Samsung address-mode codec and regression vectors. Delegated direct: nontrivial codec/diagnostic/tests files. Check default packet unchanged, exact four-mode differing offsets, asymmetric addresses, unchanged session/vendor/IV, invalid inputs and effective collisions. No unproved radio-default change.
- [x] U3: Correct stage deadlines, observe framework running, and wire explicitly experimental UI controls and safe diagnostics. Delegated direct: native bridge/UI/policy/tests multiple files. Check slow setup preserves full post-ACK budget, stale generation/events ignored, no distance from ACK/echo/running event, stage-specific failures; selected address mode reaches only Samsung encoder and is fixed during a trial.
- [x] U4: Build/test/archive, retrieve and verify IPA, record handoff. Inline remote orchestration with delegated fixes if needed. Check native/Python suites, generated metadata, archive/IPA, ZIP CRC, arm64 executable, unsigned/no profile, simulator capture. Physical tests remain owner action.

## Delivery and recovery
Forecast350–550 authored additions+deletions; 400 is advisory, never code shrinking. Cached user-selected stacked-to-main delivery applies. Prospective coherent slices: audit report; codec+vectors; native timing/UI+tests. No PR created. Each task closes with a work-unit Conventional Commit and observed checks. Rollback this branch after54e6dea to restore T11. No actual timeout-cause or UWB-success claim without physical evidence.

## Progress
- Independent audits and implementation complete; full native integration/archive verification passed. Address changes remain experiments.

- U1 completed in1784425: docs/UWB-PROFILE-AUDIT.md (100lines) read back and whitespace checked; current primary public API/official indexed tables and pinned uTag evidence distinguish facts from unresolved firmware/over-air behavior. Full Apple PDFs inaccessible; no actual timeout cause proved.
- U2 tests e42895a: native RED39951510225 missing SamsungUWBAddressMode/addressMode and collision API observed before core production8273db3. U3 tests6e467df add8policy+2bridge cases; run39951937931 will establish coreGREEN and reach AppRED before native production. Baseline localPython12PASS.

- U2 GREEN observed39951937931:63core tests and12Python pass. Production8273db3 preserves baseline and tests all four modes, collisions and invalid inputs.
- U3 App RED39951937931 observed before production90e3218. Eight policy and two bridge tests supplement unchanged baseline; full GREEN/archive run39952971278 in progress. Separate monotonic setup/post-ACK deadlines; safe observed callback/counters; UI mode locks and current-attempt ACK checks. No physical timeout-cause claim.

## Verified delivery
- U3 GREEN39952971278 at90e3218:63core+31App+2UI=96 native tests,12Python; all pass. No pre-existing failing baseline; expected test-first compile RED runs39951510225 and39951937931 preceded production. No further refactor needed after GREEN. Eight timing-policy cases include deadline boundaries, late/stale/duplicate events, missing/invalid distance and bounded diagnostics; asymmetric address vectors cover all four modes and effective collisions.
- U4 archive/package/configuration checks PASS. Downloaded build/downloads/39952971278/SmartTagDiagnostic-unsigned.ipa,221565bytes,SHA2562bd7f24ab1d074eb08d35d12827e8ad1d411cd0927d025dea1497c085448db75. ZIP CRC, arm64 Mach-O, expected bundle, no embedded provision/signature all checked. Artifact12501014132. Native capture reviewed: signed-out fixture only, not authenticated UWB UI validation. Work-unit delivery source90e3218; task evidence commitd7d5ecd and closing documentation commit follow.
- Final audit follow-up found no additional UWB state read, wake/power write or mandatory cloud prerequisite in pinned uTag VM/repository/IPC/service/ConnectedTagConnection path; Samsung support-service internals remain a boundary. Full Apple PDF downloads unavailable; official indexed specification excerpts/public API evidence used. No firmware/over-air proof, no actual meters observed; physical Cleo test pending.
- Running authored branch diff before closure: approximately716 additions+deletions, generated files excluded. Cached stacked-to-main applies; coherent future slices are audit1784425, codec e42895a+8273db3, and native tests6e467df+production90e3218; no PR created. RDD disabled/unmanaged.
- Handoff: sign/install IPA, profile2.0; test Base, tag-only, phone-only, both separately. Stop between trials, capture Bluetooth and NI logs for each. Profile1.1 still correctly rejects unsupported3600RSTU slot; do not silently coerce timing. No host device/account requests or secret logging. Owner ZIP/JPG untouched.