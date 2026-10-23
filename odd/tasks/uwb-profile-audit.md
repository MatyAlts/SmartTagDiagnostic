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
- [ ] U1: Document the independent profile/sequence audit with primary evidence, source limitations and unknowns. Delegated direct: 4+file mapping and broad research. Read-only research completed; report source write follows this tracker. Check exact source links/offsets and distinguish facts, hypotheses and negative-search bounds.
- [ ] U2: Implement the bounded Samsung address-mode codec and regression vectors. Delegated direct: nontrivial codec/diagnostic/tests files. Check default packet unchanged, exact four-mode differing offsets, asymmetric addresses, unchanged session/vendor/IV, invalid inputs and effective collisions. No unproved radio-default change.
- [ ] U3: Correct stage deadlines, observe framework running, and wire explicitly experimental UI controls and safe diagnostics. Delegated direct: native bridge/UI/policy/tests multiple files. Check slow setup preserves full post-ACK budget, stale generation/events ignored, no distance from ACK/echo/running event, stage-specific failures; selected address mode reaches only Samsung encoder and is fixed during a trial.
- [ ] U4: Build/test/archive, retrieve and verify IPA, record handoff. Inline remote orchestration with delegated fixes if needed. Check native/Python suites, generated metadata, archive/IPA, ZIP CRC, arm64 executable, unsigned/no profile, simulator capture. Physical tests remain owner action.

## Delivery and recovery
Forecast350–550 authored additions+deletions; 400 is advisory, never code shrinking. Cached user-selected stacked-to-main delivery applies. Prospective coherent slices: audit report; codec+vectors; native timing/UI+tests. No PR created. Each task closes with a work-unit Conventional Commit and observed checks. Rollback this branch after54e6dea to restore T11. No actual timeout-cause or UWB-success claim without physical evidence.

## Progress
- Initial audits complete read-only; source work not yet started. Track profile changes as experiments unless supported independently.
